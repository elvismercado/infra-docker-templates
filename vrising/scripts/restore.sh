#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

ASSUME_YES=false
ARCHIVE=""
for argument in "$@"; do
    case "${argument}" in
        --yes) ASSUME_YES=true ;;
        -*)
            echo "Unknown option: ${argument}" >&2
            echo "Usage: $0 [--yes] BACKUP_ARCHIVE" >&2
            exit 1
            ;;
        *)
            if [ -n "${ARCHIVE}" ]; then
                echo "ERROR: Specify exactly one backup archive." >&2
                exit 1
            fi
            ARCHIVE="${argument}"
            ;;
    esac
done

if [ -z "${ARCHIVE}" ]; then
    echo "Usage: $0 [--yes] BACKUP_ARCHIVE" >&2
    exit 1
fi

echo "Step 1/8: Checking dependencies and configuration..."
require_command docker
require_command tar
require_command readlink
load_environment
if [ ! -f "${ARCHIVE}" ]; then
    echo "ERROR: Backup archive not found: ${ARCHIVE}" >&2
    exit 1
fi
ARCHIVE="$(readlink -f "${ARCHIVE}")"
echo "  Restoring from ${ARCHIVE}."

echo "Step 2/8: Validating backup archive..."
tar -tzf "${ARCHIVE}" >/dev/null
while IFS= read -r entry; do
    case "/${entry}/" in
        *"/../"*|*"/./"*)
            echo "ERROR: Archive contains a traversal path: ${entry}" >&2
            exit 1
            ;;
    esac
    case "${entry}" in
        save-data|save-data/*) ;;
        *)
            echo "ERROR: Unsafe or unexpected archive member: ${entry}" >&2
            exit 1
            ;;
    esac
done < <(tar -tzf "${ARCHIVE}")
while IFS= read -r details; do
    case "${details:0:1}" in
        -|d) ;;
        *)
            echo "ERROR: Archive contains links or unsupported entry types." >&2
            exit 1
            ;;
    esac
done < <(tar -tvzf "${ARCHIVE}")
echo "  Archive contains only regular files and directories below save-data."

echo "Step 3/8: Confirming restore..."
if [ "${ASSUME_YES}" = false ]; then
    echo "This will replace ${SAVE_DATA_DIR} and restart the V Rising server."
    read -r -p "Proceed? [y/N] " response
    case "${response}" in
        [yY]|[yY][eE][sS]) ;;
        *) echo "Restore aborted."; exit 0 ;;
    esac
fi
echo "  Restore confirmed."

echo "Step 4/8: Acquiring maintenance lock..."
acquire_maintenance_lock
trap release_maintenance_lock EXIT
echo "  Lock acquired."

echo "Step 5/8: Stopping server..."
if container_is_running; then
    compose stop --timeout 120 "${SERVICE_NAME}"
    echo "  Server stopped gracefully."
else
    echo "  Server is already stopped."
fi

echo "Step 6/8: Creating pre-restore backup..."
create_backup_archive "pre-restore"

echo "Step 7/8: Restoring save data..."
RESTORE_TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
STAGING_DIR="${DATA_ROOT}/restore-staging-${RESTORE_TIMESTAMP}"
PREVIOUS_DIR="${SERVERFILES_DIR}/save-data.before-restore-${RESTORE_TIMESTAMP}"
mkdir -p "${STAGING_DIR}"
trap 'rm -rf -- "${STAGING_DIR}"; release_maintenance_lock' EXIT
tar -C "${STAGING_DIR}" -xzf "${ARCHIVE}"
if [ -e "${SAVE_DATA_DIR}" ]; then
    mv "${SAVE_DATA_DIR}" "${PREVIOUS_DIR}"
    echo "  Previous save data retained at ${PREVIOUS_DIR}."
fi
mv "${STAGING_DIR}/save-data" "${SAVE_DATA_DIR}"
rmdir "${STAGING_DIR}"
chown -R "${RUN_UID}:${GID}" "${SAVE_DATA_DIR}"
echo "  Save data restored."

echo "Step 8/8: Starting server and checking readiness..."
compose up -d
if ! wait_for_healthy 1200; then
    echo "ERROR: Restore completed, but the server did not become healthy." >&2
    echo "Previous data remains at ${PREVIOUS_DIR}." >&2
    exit 1
fi

echo "Restore complete."
echo "Pre-restore archive: ${CREATED_BACKUP}"
