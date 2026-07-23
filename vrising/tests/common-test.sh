#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEST_ENV="$(mktemp)"

cleanup() {
    rm -f -- "${TEST_ENV}"
}
trap cleanup EXIT

# shellcheck source=../scripts/common.sh
source "${PROJECT_DIR}/scripts/common.sh"

echo "Step 1/2: Verifying stopped-container lookup arguments..."
compose() {
    printf '%s\n' "$*"
}
if [ "$(container_id)" != "ps --all -q vrising" ]; then
    echo "ERROR: container_id does not include stopped containers." >&2
    exit 1
fi

echo "Step 2/2: Verifying conditional RCON overlay assembly..."
printf '%s\n' 'RCON_ENABLED=true' > "${TEST_ENV}"
ENV_FILE="${TEST_ENV}"
load_environment
case " ${COMPOSE_CMD[*]} " in
    *"docker-compose.rcon.yml"*) ;;
    *)
        echo "ERROR: RCON override was not included when enabled." >&2
        exit 1
        ;;
esac

printf '%s\n' 'RCON_ENABLED=false' > "${TEST_ENV}"
load_environment
case " ${COMPOSE_CMD[*]} " in
    *"docker-compose.rcon.yml"*)
        echo "ERROR: RCON override was included when disabled." >&2
        exit 1
        ;;
esac

echo "All common helper tests passed."