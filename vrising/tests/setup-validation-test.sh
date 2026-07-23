#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
TEST_PROJECT="${TEST_ROOT}/project"

cleanup() {
    rm -rf -- "${TEST_ROOT}"
}
trap cleanup EXIT

mkdir -p "${TEST_PROJECT}/scripts" "${TEST_ROOT}/bin"
cp "${PROJECT_DIR}/scripts/common.sh" "${TEST_PROJECT}/scripts/common.sh"
cp "${PROJECT_DIR}/scripts/setup.sh" "${TEST_PROJECT}/scripts/setup.sh"
: > "${TEST_PROJECT}/docker-compose.yml"
: > "${TEST_PROJECT}/docker-compose.rcon.yml"

cat > "${TEST_ROOT}/bin/chown" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat > "${TEST_ROOT}/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

if [ "${1:-}" = "compose" ]; then
    shift
    while [ "${1:-}" = "--env-file" ] || [ "${1:-}" = "-f" ]; do
        shift 2
    done
    compose_command="$1"
    case "${compose_command}" in
        version|config|up|restart)
            exit 0
            ;;
        ps)
            printf '%s\n' 'container-id'
            exit 0
            ;;
    esac
fi

if [ "${1:-}" = "inspect" ]; then
    printf '%s\n' 'healthy'
    exit 0
fi

echo "Unexpected docker command: $*" >&2
exit 1
EOF
chmod +x "${TEST_ROOT}/bin/chown" "${TEST_ROOT}/bin/docker"

write_base_env() {
    cat > "${TEST_PROJECT}/.env" <<EOF
TZ=Europe/Amsterdam
UID=99
GID=100
UMASK=022
VOLUMES_BASE=${TEST_ROOT}/data
CONTAINER_NAME=vrising-test
SUBNET=10.42.99.0/24
IMAGE_VERSION=vrising
GAME_ID=1829350
VALIDATE=false
ENABLE_BEPINEX=false
SERVER_NAME='V Rising Test'
SERVER_DESCRIPTION='Validation test'
WORLD_NAME=test-world
SERVER_PASSWORD='server-password'
GAME_PORT=19876
QUERY_PORT=19877
HIDE_IP_ADDRESS=true
LIST_ON_STEAM=false
LIST_ON_EOS=false
GAME_SETTINGS_PRESET=StandardPvE
MAX_CONNECTED_USERS=10
MAX_CONNECTED_ADMINS=4
ADMIN_STEAM_IDS=
SERVER_FPS=30
LOWER_FPS_WHEN_EMPTY=true
LOWER_FPS_WHEN_EMPTY_VALUE=5
SECURE=true
AUTO_SAVE_COUNT=30
AUTO_SAVE_INTERVAL=120
BACKUP_RETENTION=14
WATCHTOWER_ENABLE=false
WUD_ENABLE=false
EOF
}

run_setup() {
    PATH="${TEST_ROOT}/bin:${PATH}" bash "${TEST_PROJECT}/scripts/setup.sh"
}

echo "Step 1/4: Verifying defaults with optional settings unset..."
write_base_env
printf '%s\n' 'RCON_ENABLED=false' >> "${TEST_PROJECT}/.env"
run_setup > "${TEST_ROOT}/defaults.log" 2>&1
grep -q 'Setup complete.' "${TEST_ROOT}/defaults.log"

echo "Step 2/4: Verifying valid optional settings and private RCON..."
write_base_env
cat >> "${TEST_PROJECT}/.env" <<'EOF'
VR_DIFFICULTY_PRESET=Difficulty_Normal
VR_AUTOSAVESMARTKEEP='10:1:1,60:0:1,1440:0:1'
VR_LAN_MODE=false
VR_RESET_DAYS_INTERVAL=0
VR_DAY_OF_RESET=Any
VR_SAFE_RECONNECT_TIME=300
VR_SAFE_RECONNECT_SLOTS=10
RCON_ENABLED=true
RCON_HOST_ADDRESS=127.0.0.1
RCON_BIND_ADDRESS=0.0.0.0
RCON_PORT=25575
RCON_PASSWORD='rcon-password'
EOF
run_setup > "${TEST_ROOT}/valid.log" 2>&1
grep -q 'Setup complete.' "${TEST_ROOT}/valid.log"

echo "Step 3/4: Verifying placeholder RCON password rejection..."
write_base_env
cat >> "${TEST_PROJECT}/.env" <<'EOF'
RCON_ENABLED=true
RCON_HOST_ADDRESS=127.0.0.1
RCON_BIND_ADDRESS=0.0.0.0
RCON_PORT=25575
RCON_PASSWORD='CHANGE_ME'
EOF
if run_setup > "${TEST_ROOT}/rcon-invalid.log" 2>&1; then
    echo "ERROR: setup accepted a placeholder RCON password." >&2
    exit 1
fi
grep -q 'Set a non-placeholder RCON_PASSWORD' "${TEST_ROOT}/rcon-invalid.log"

echo "Step 4/4: Verifying malformed smart-retention rejection..."
write_base_env
cat >> "${TEST_PROJECT}/.env" <<'EOF'
VR_AUTOSAVESMARTKEEP='10:1,60:0:1'
RCON_ENABLED=false
EOF
if run_setup > "${TEST_ROOT}/retention-invalid.log" 2>&1; then
    echo "ERROR: setup accepted malformed smart-retention buckets." >&2
    exit 1
fi
grep -q 'minutes:newest:oldest buckets' "${TEST_ROOT}/retention-invalid.log"

echo "All setup validation tests passed."