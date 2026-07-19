#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${PROJECT_DIR}/.env"
SERVICE_NAME="vrising"

require_command() {
    local command_name="$1"
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "ERROR: Required command not found: ${command_name}" >&2
        return 1
    fi
}

load_environment() {
    if [ ! -f "${ENV_FILE}" ]; then
        echo "ERROR: ${ENV_FILE} does not exist." >&2
        echo "Copy ${PROJECT_DIR}/.env.example to ${ENV_FILE} and configure it first." >&2
        return 1
    fi

    set -a
    # The template is intentionally shell-compatible as well as Compose-compatible.
    # Bash reserves UID as read-only, so read that one separately.
    # shellcheck disable=SC1090
    source <(grep -vE '^[[:space:]]*UID=' "${ENV_FILE}")
    set +a

    VOLUMES_BASE="${VOLUMES_BASE:-/tmp}"
    CONTAINER_NAME="${CONTAINER_NAME:-vrising}"
    RUN_UID="$(sed -nE 's/^[[:space:]]*UID=([0-9]+)[[:space:]]*$/\1/p' "${ENV_FILE}" | tail -n 1)"
    RUN_UID="${RUN_UID:-99}"
    GID="${GID:-100}"
    BACKUP_RETENTION="${BACKUP_RETENTION:-14}"
    WATCHTOWER_ENABLE="${WATCHTOWER_ENABLE:-false}"
    WUD_ENABLE="${WUD_ENABLE:-false}"
    DATA_ROOT="${VOLUMES_BASE}/${CONTAINER_NAME}"
    SERVERFILES_DIR="${DATA_ROOT}/serverfiles"
    SAVE_DATA_DIR="${SERVERFILES_DIR}/save-data"
    BACKUP_DIR="${DATA_ROOT}/backups"
    LOCK_DIR="${DATA_ROOT}/.maintenance.lock"

    # Assemble the compose command with the same overlays used at deploy time so
    # every script (setup/backup/restore/update) recreates the container with a
    # consistent set of labels. Each overlay is appended only when its flag is
    # enabled and the file exists.
    COMPOSE_CMD=(docker compose --env-file "${ENV_FILE}" -f "${PROJECT_DIR}/docker-compose.yml")
    if [ "${WATCHTOWER_ENABLE}" = "true" ] && [ -f "${PROJECT_DIR}/docker-compose.watchtower.yml" ]; then
        COMPOSE_CMD+=(-f "${PROJECT_DIR}/docker-compose.watchtower.yml")
    fi
    if [ "${WUD_ENABLE}" = "true" ] && [ -f "${PROJECT_DIR}/docker-compose.wud.yml" ]; then
        COMPOSE_CMD+=(-f "${PROJECT_DIR}/docker-compose.wud.yml")
    fi
}

compose() {
    "${COMPOSE_CMD[@]}" "$@"
}

container_id() {
    compose ps -q "${SERVICE_NAME}"
}

container_is_running() {
    local id
    id="$(container_id)"
    [ -n "${id}" ] && [ "$(docker inspect --format '{{.State.Running}}' "${id}")" = "true" ]
}

container_health() {
    local id
    id="$(container_id)"
    if [ -z "${id}" ]; then
        printf '%s\n' "missing"
        return
    fi
    docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "${id}"
}

wait_for_healthy() {
    local timeout_seconds="${1:-1200}"
    local elapsed=0
    local status

    while [ "${elapsed}" -lt "${timeout_seconds}" ]; do
        status="$(container_health)"
        case "${status}" in
            healthy)
                echo "  Container is healthy."
                return 0
                ;;
            exited|dead|missing|unhealthy)
                echo "ERROR: Container status is ${status}." >&2
                return 1
                ;;
        esac
        sleep 10
        elapsed=$((elapsed + 10))
    done

    echo "ERROR: Timed out waiting for a healthy container." >&2
    return 1
}

acquire_maintenance_lock() {
    mkdir -p "${DATA_ROOT}"
    if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
        echo "ERROR: Another V Rising maintenance operation is already running." >&2
        echo "If no operation is running, remove stale lock: ${LOCK_DIR}" >&2
        return 1
    fi
    printf '%s\n' "$$" > "${LOCK_DIR}/pid"
}

release_maintenance_lock() {
    if [ -d "${LOCK_DIR}" ]; then
        rm -f "${LOCK_DIR}/pid"
        rmdir "${LOCK_DIR}"
    fi
}

create_backup_archive() {
    local prefix="${1:-vrising}"
    local timestamp
    local temporary_archive

    if [ ! -d "${SAVE_DATA_DIR}" ]; then
        echo "ERROR: Save data directory not found: ${SAVE_DATA_DIR}" >&2
        return 1
    fi

    mkdir -p "${BACKUP_DIR}"
    timestamp="$(date +%Y%m%d-%H%M%S)"
    CREATED_BACKUP="${BACKUP_DIR}/${prefix}-${timestamp}.tar.gz"
    while [ -e "${CREATED_BACKUP}" ]; do
        sleep 1
        timestamp="$(date +%Y%m%d-%H%M%S)"
        CREATED_BACKUP="${BACKUP_DIR}/${prefix}-${timestamp}.tar.gz"
    done
    temporary_archive="${CREATED_BACKUP}.partial"

    if ! tar -C "${SERVERFILES_DIR}" -czf "${temporary_archive}" save-data; then
        rm -f -- "${temporary_archive}"
        echo "ERROR: Failed to create backup archive." >&2
        return 1
    fi
    if ! tar -tzf "${temporary_archive}" >/dev/null; then
        rm -f -- "${temporary_archive}"
        echo "ERROR: Backup archive validation failed." >&2
        return 1
    fi
    mv "${temporary_archive}" "${CREATED_BACKUP}"
    echo "  Created ${CREATED_BACKUP}"
}

prune_backups() {
    local retention="${BACKUP_RETENTION}"
    local -a archives=()
    local remove_count
    local archive

    if ! [[ "${retention}" =~ ^[1-9][0-9]*$ ]]; then
        echo "ERROR: BACKUP_RETENTION must be a positive integer." >&2
        return 1
    fi

    mapfile -t archives < <(
        find "${BACKUP_DIR}" -maxdepth 1 -type f -name 'vrising-*.tar.gz' \
            -printf '%T@ %p\n' | sort -nr | cut -d' ' -f2-
    )

    if [ "${#archives[@]}" -le "${retention}" ]; then
        echo "  Retention already satisfied (${#archives[@]}/${retention})."
        return
    fi

    remove_count=$(("${#archives[@]}" - retention))
    for archive in "${archives[@]:retention:remove_count}"; do
        rm -f -- "${archive}"
        echo "  Removed old backup ${archive}"
    done
}
