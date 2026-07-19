#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

echo "Step 1/6: Checking dependencies..."
require_command docker
require_command tar
docker compose version >/dev/null
echo "  Dependencies available."

echo "Step 2/6: Loading and validating configuration..."
load_environment
if [ -z "${SERVER_PASSWORD:-}" ] || [ "${SERVER_PASSWORD}" = "CHANGE_ME" ]; then
    echo "ERROR: Set a non-placeholder SERVER_PASSWORD in ${ENV_FILE}." >&2
    exit 1
fi
if [ -z "${SERVER_NAME:-}" ] || [ -z "${WORLD_NAME:-}" ]; then
    echo "ERROR: SERVER_NAME and WORLD_NAME must not be empty." >&2
    exit 1
fi
if [[ "${WORLD_NAME}" == *"/"* ]] || [[ "${WORLD_NAME}" == *"\\"* ]]; then
    echo "ERROR: WORLD_NAME must be a directory name, not a path." >&2
    exit 1
fi
for port_name in GAME_PORT QUERY_PORT; do
    port_value="${!port_name:-}"
    if ! [[ "${port_value}" =~ ^[0-9]+$ ]] || [ "${port_value}" -lt 1 ] || [ "${port_value}" -gt 65535 ]; then
        echo "ERROR: ${port_name} must be a number from 1 to 65535." >&2
        exit 1
    fi
done
if [ "${GAME_PORT}" = "${QUERY_PORT}" ]; then
    echo "ERROR: GAME_PORT and QUERY_PORT must be different." >&2
    exit 1
fi
echo "  Configuration is valid."

echo "Step 3/6: Creating persistent directories..."
mkdir -p "${DATA_ROOT}/steamcmd" "${SERVERFILES_DIR}" "${BACKUP_DIR}"
chown -R "${RUN_UID}:${GID}" "${DATA_ROOT}/steamcmd" "${SERVERFILES_DIR}" "${BACKUP_DIR}"
echo "  Persistent directories are ready at ${DATA_ROOT}."

echo "Step 4/6: Validating Docker Compose..."
compose config --quiet
echo "  Compose configuration is valid."

echo "Step 5/6: Starting V Rising..."
compose up -d
echo "  Container started. First installation can take several minutes."

echo "Step 6/6: Waiting for server readiness..."
if ! wait_for_healthy 1200; then
    echo "Inspect startup logs with:" >&2
    echo "  ${COMPOSE_CMD[*]} logs --tail=200 ${SERVICE_NAME}" >&2
    exit 1
fi

echo "Setup complete."
echo "Logs: ${COMPOSE_CMD[*]} logs -f ${SERVICE_NAME}"
