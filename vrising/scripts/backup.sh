#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

LEAVE_STOPPED=false
LOCK_HELD=false
WAS_RUNNING=false
BACKUP_FINISHED=false
for argument in "$@"; do
    case "${argument}" in
        --leave-stopped) LEAVE_STOPPED=true ;;
        --lock-held) LOCK_HELD=true ;;
        *)
            echo "Usage: $0 [--leave-stopped] [--lock-held]" >&2
            exit 1
            ;;
    esac
done

echo "Step 1/6: Checking dependencies and configuration..."
require_command docker
require_command tar
load_environment
echo "  Configuration loaded."

echo "Step 2/6: Acquiring maintenance lock..."
if [ "${LOCK_HELD}" = false ]; then
    acquire_maintenance_lock
else
    if [ ! -d "${LOCK_DIR}" ]; then
        echo "ERROR: --lock-held was used without an active maintenance lock." >&2
        exit 1
    fi
    echo "  Using caller's maintenance lock."
fi

cleanup() {
    local exit_code=$?
    set +e
    if [ "${exit_code}" -ne 0 ] && [ "${WAS_RUNNING}" = true ] &&
        [ "${LEAVE_STOPPED}" = false ] && [ "${BACKUP_FINISHED}" = false ]; then
        echo "Backup failed; attempting to restore the running server state." >&2
        compose up -d
    fi
    if [ "${LOCK_HELD}" = false ]; then
        release_maintenance_lock
    fi
    exit "${exit_code}"
}
trap cleanup EXIT

echo "Step 3/6: Checking server state..."
if container_is_running; then
    WAS_RUNNING=true
    echo "  Server is running."
else
    echo "  Server is already stopped."
fi

echo "Step 4/6: Stopping server for a consistent backup..."
if [ "${WAS_RUNNING}" = true ]; then
    compose stop --timeout 120 "${SERVICE_NAME}"
    echo "  Server stopped gracefully."
else
    echo "  Stop skipped."
fi

echo "Step 5/6: Creating and pruning backups..."
create_backup_archive "vrising"
prune_backups

echo "Step 6/6: Restoring prior server state..."
if [ "${WAS_RUNNING}" = true ] && [ "${LEAVE_STOPPED}" = false ]; then
    compose up -d
    echo "  Server restarted."
else
    echo "  Server left stopped."
fi

BACKUP_FINISHED=true
echo "Backup complete: ${CREATED_BACKUP}"
