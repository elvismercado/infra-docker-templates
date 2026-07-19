#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

echo "Step 1/7: Checking dependencies and configuration..."
require_command docker
require_command tar
load_environment
compose config --quiet
echo "  Configuration is valid."

echo "Step 2/7: Acquiring maintenance lock..."
acquire_maintenance_lock
trap release_maintenance_lock EXIT
echo "  Lock acquired."

echo "Step 3/7: Backing up and stopping server..."
"${SCRIPT_DIR}/backup.sh" --leave-stopped --lock-held
echo "  Backup complete."

echo "Step 4/7: Preserving current container image..."
CURRENT_IMAGE_ID="$(docker inspect --format '{{.Image}}' "$(container_id)" 2>/dev/null || true)"
ROLLBACK_TAG=""
if [ -n "${CURRENT_IMAGE_ID}" ]; then
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
compose up -d --force-recreate "${SERVICE_NAME}"
echo "  SteamCMD will check and update V Rising during startup."

echo "Step 7/7: Checking server readiness..."
if ! wait_for_healthy 1200; then
    echo "ERROR: Updated server did not become healthy." >&2
    echo "Inspect logs: ${COMPOSE_CMD[*]} logs --tail=200 ${SERVICE_NAME}" >&2
    if [ -n "${ROLLBACK_TAG}" ]; then
        echo "Previous container image: ${ROLLBACK_TAG}" >&2
        echo "Note: rolling back the image does not roll back SteamCMD-updated game files." >&2
    fi
    exit 1
fi

echo "Update complete."
if [ -n "${ROLLBACK_TAG}" ]; then
    echo "Previous image retained as ${ROLLBACK_TAG}."
fi
