#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

echo "Step 1/7: Checking dependencies..."
require_command docker
require_command tar
docker compose version >/dev/null
echo "  Dependencies available."

echo "Step 2/7: Loading and validating configuration..."
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
case "${RCON_ENABLED}" in
    true|false) ;;
    *)
        echo "ERROR: RCON_ENABLED must be true or false." >&2
        exit 1
        ;;
esac
if [ "${RCON_ENABLED}" = "true" ]; then
    if [ -z "${RCON_PASSWORD}" ] || [ "${RCON_PASSWORD}" = "CHANGE_ME" ]; then
        echo "ERROR: Set a non-placeholder RCON_PASSWORD when RCON is enabled." >&2
        exit 1
    fi
    if [ -z "${RCON_HOST_ADDRESS}" ] || [ -z "${RCON_BIND_ADDRESS}" ]; then
        echo "ERROR: RCON_HOST_ADDRESS and RCON_BIND_ADDRESS must not be empty." >&2
        exit 1
    fi
fi

if [ -n "${VR_DIFFICULTY_PRESET+x}" ] && [ -n "${VR_DIFFICULTY_PRESET}" ]; then
    case "${VR_DIFFICULTY_PRESET}" in
        Difficulty_Easy|Difficulty_Normal|Difficulty_Brutal) ;;
        *)
            echo "ERROR: VR_DIFFICULTY_PRESET must be empty or a shipped difficulty preset." >&2
            exit 1
            ;;
    esac
fi
if [ -n "${VR_AUTOSAVESMARTKEEP+x}" ] && [ -n "${VR_AUTOSAVESMARTKEEP}" ] &&
    ! [[ "${VR_AUTOSAVESMARTKEEP}" =~ ^[0-9]+:[0-9]+:[0-9]+(,[0-9]+:[0-9]+:[0-9]+)*$ ]]; then
    echo "ERROR: VR_AUTOSAVESMARTKEEP must use minutes:newest:oldest buckets." >&2
    exit 1
fi
if [ -n "${VR_LAN_MODE+x}" ]; then
    case "${VR_LAN_MODE}" in
        true|false) ;;
        *)
            echo "ERROR: VR_LAN_MODE must be true or false." >&2
            exit 1
            ;;
    esac
fi
if [ -n "${VR_RESET_DAYS_INTERVAL+x}" ] &&
    ! [[ "${VR_RESET_DAYS_INTERVAL}" =~ ^[0-9]+$ ]]; then
    echo "ERROR: VR_RESET_DAYS_INTERVAL must be zero or a positive integer." >&2
    exit 1
fi
if [ -n "${VR_DAY_OF_RESET+x}" ]; then
    case "${VR_DAY_OF_RESET}" in
        Any|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday) ;;
        *)
            echo "ERROR: VR_DAY_OF_RESET must be Any or a weekday name." >&2
            exit 1
            ;;
    esac
fi
for reconnect_name in VR_SAFE_RECONNECT_TIME VR_SAFE_RECONNECT_SLOTS; do
    if [ -n "${!reconnect_name+x}" ] && ! [[ "${!reconnect_name}" =~ ^[0-9]+$ ]]; then
        echo "ERROR: ${reconnect_name} must be zero or a positive integer." >&2
        exit 1
    fi
done

port_names=(GAME_PORT QUERY_PORT)
if [ "${RCON_ENABLED}" = "true" ]; then
    port_names+=(RCON_PORT)
fi
for port_name in "${port_names[@]}"; do
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

echo "Step 3/7: Creating persistent directories..."
mkdir -p "${DATA_ROOT}/steamcmd" "${SERVERFILES_DIR}" "${BACKUP_DIR}"
chown -R "${RUN_UID}:${GID}" "${DATA_ROOT}/steamcmd" "${SERVERFILES_DIR}" "${BACKUP_DIR}"
echo "  Persistent directories are ready at ${DATA_ROOT}."

echo "Step 4/7: Validating Docker Compose..."
compose config --quiet
echo "  Compose configuration is valid."

echo "Step 5/7: Starting V Rising..."
compose up -d
echo "  Container started. First installation can take several minutes."

echo "Step 6/7: Waiting for server readiness..."
if ! wait_for_healthy 1200; then
    echo "Inspect startup logs with:" >&2
    echo "  ${COMPOSE_CMD[*]} logs --tail=200 ${SERVICE_NAME}" >&2
    exit 1
fi

echo "Step 7/7: Verifying settings and declarative admins..."
SETTINGS_DIR="${SAVE_DATA_DIR}/Settings"
if [ -z "${ADMIN_STEAM_IDS:-}" ]; then
    echo "  ADMIN_STEAM_IDS is empty; adminlist.txt remains manually managed."
else
    ADMIN_FILE="${SETTINGS_DIR}/adminlist.txt"
    if [ ! -f "${ADMIN_FILE}" ]; then
        echo "  Restarting once to apply ADMIN_STEAM_IDS after first-time installation..."
        compose restart --timeout 120 "${SERVICE_NAME}"
        if ! wait_for_healthy 1200; then
            echo "ERROR: Server did not become healthy after applying ADMIN_STEAM_IDS." >&2
            exit 1
        fi
    fi
    if [ ! -f "${ADMIN_FILE}" ]; then
        echo "ERROR: Declarative admin file was not created: ${ADMIN_FILE}" >&2
        exit 1
    fi
    echo "  Declarative adminlist.txt is present."
fi

echo "Setup complete."
echo "Logs: ${COMPOSE_CMD[*]} logs -f ${SERVICE_NAME}"
