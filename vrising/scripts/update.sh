#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

ORIGINAL_WAS_RUNNING=false
MAINTENANCE_STARTED=false
REPLACEMENT_ATTEMPTED=false
ROLLBACK_TAG=""
TARGET_IMAGE=""

rollback_container_image() {
    if [ -z "${ROLLBACK_TAG}" ] || [ -z "${TARGET_IMAGE}" ]; then
        echo "ERROR: No previous container image is available for automatic rollback." >&2
        return 1
    fi

    echo "  Restoring ${TARGET_IMAGE} from ${ROLLBACK_TAG}..."
    if ! docker image tag "${ROLLBACK_TAG}" "${TARGET_IMAGE}"; then
        echo "ERROR: Could not restore the previous image tag." >&2
        return 1
    fi
    if ! compose up -d --force-recreate --pull never "${SERVICE_NAME}"; then
        echo "ERROR: Could not recreate the server with the previous image." >&2
        return 1
    fi
    if ! wait_for_healthy 1200; then
        echo "ERROR: The server did not become healthy after image rollback." >&2
        return 1
    fi

    echo "  Previous container image restored successfully."
}

cleanup() {
    local exit_code=$?
    set +e

    if [ "${exit_code}" -ne 0 ] && [ "${MAINTENANCE_STARTED}" = true ] &&
        [ "${REPLACEMENT_ATTEMPTED}" = false ] && [ "${ORIGINAL_WAS_RUNNING}" = true ]; then
        echo "Update failed before replacement; restarting the original container..." >&2
        if compose start "${SERVICE_NAME}"; then
            echo "  Original container restarted." >&2
        else
            echo "ERROR: Could not restart the original container." >&2
            echo "Run: ${COMPOSE_CMD[*]} start ${SERVICE_NAME}" >&2
        fi
    fi

    release_maintenance_lock
    exit "${exit_code}"
}

echo "Step 1/7: Checking dependencies and configuration..."
require_command docker
require_command tar
load_environment
compose config --quiet
echo "  Configuration is valid."

echo "Step 2/7: Acquiring maintenance lock..."
acquire_maintenance_lock
trap cleanup EXIT
echo "  Lock acquired."

echo "Step 3/7: Backing up and stopping server..."
if container_is_running; then
    ORIGINAL_WAS_RUNNING=true
fi
MAINTENANCE_STARTED=true
"${SCRIPT_DIR}/backup.sh" --leave-stopped --lock-held
echo "  Backup complete."

echo "Step 4/7: Preserving current container image..."
CURRENT_CONTAINER_ID="$(container_id)"
if [ -n "${CURRENT_CONTAINER_ID}" ]; then
    CURRENT_IMAGE_ID="$(docker inspect --format '{{.Image}}' "${CURRENT_CONTAINER_ID}")"
    TARGET_IMAGE="$(docker inspect --format '{{.Config.Image}}' "${CURRENT_CONTAINER_ID}")"
    ROLLBACK_TAG="vrising-rollback:$(date +%Y%m%d-%H%M%S)"
    docker image tag "${CURRENT_IMAGE_ID}" "${ROLLBACK_TAG}"
    echo "  Tagged current image as ${ROLLBACK_TAG}."
else
    echo "  No existing container image found; skipping rollback tag."
fi

echo "Step 5/7: Pulling container image..."
compose pull "${SERVICE_NAME}"
echo "  Image pull complete."

echo "Step 6/7: Recreating server..."
REPLACEMENT_ATTEMPTED=true
if ! compose up -d --force-recreate "${SERVICE_NAME}"; then
    echo "ERROR: Could not recreate the server with the updated image." >&2
    if ! rollback_container_image; then
        echo "Manual image recovery:" >&2
        echo "  docker image tag ${ROLLBACK_TAG:-PREVIOUS_IMAGE} ${TARGET_IMAGE:-CURRENT_IMAGE}" >&2
        echo "  ${COMPOSE_CMD[*]} up -d --force-recreate --pull never ${SERVICE_NAME}" >&2
    fi
    exit 1
fi
echo "  SteamCMD will check and update V Rising during startup."

echo "Step 7/7: Checking server readiness..."
if ! wait_for_healthy 1200; then
    echo "ERROR: Updated server did not become healthy." >&2
    echo "Inspect logs: ${COMPOSE_CMD[*]} logs --tail=200 ${SERVICE_NAME}" >&2
    echo "Attempting automatic container-image rollback..." >&2
    if ! rollback_container_image; then
        echo "Manual image recovery:" >&2
        echo "  docker image tag ${ROLLBACK_TAG:-PREVIOUS_IMAGE} ${TARGET_IMAGE:-CURRENT_IMAGE}" >&2
        echo "  ${COMPOSE_CMD[*]} up -d --force-recreate --pull never ${SERVICE_NAME}" >&2
    fi
    echo "Note: image rollback does not roll back SteamCMD-updated game files." >&2
    exit 1
fi

echo "Update complete."
if [ -n "${ROLLBACK_TAG}" ]; then
    echo "Previous image retained as ${ROLLBACK_TAG}."
fi
