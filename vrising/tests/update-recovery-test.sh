#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEST_ROOT="$(mktemp -d)"

cleanup() {
    rm -rf -- "${TEST_ROOT}"
}
trap cleanup EXIT

prepare_scenario() {
    local scenario_name="$1"

    SCENARIO_DIR="${TEST_ROOT}/${scenario_name}"
    mkdir -p "${SCENARIO_DIR}/bin" "${SCENARIO_DIR}/project/scripts" "${SCENARIO_DIR}/state"
    cp "${PROJECT_DIR}/scripts/common.sh" "${SCENARIO_DIR}/project/scripts/common.sh"
    cp "${PROJECT_DIR}/scripts/update.sh" "${SCENARIO_DIR}/project/scripts/update.sh"
    : > "${SCENARIO_DIR}/project/docker-compose.yml"
    cat > "${SCENARIO_DIR}/project/.env" <<EOF
VOLUMES_BASE=${SCENARIO_DIR}/data
CONTAINER_NAME=vrising
BACKUP_RETENTION=14
WATCHTOWER_ENABLE=false
WUD_ENABLE=false
RCON_ENABLED=false
EOF
    cat > "${SCENARIO_DIR}/project/scripts/backup.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' 'backup' >> "${MOCK_STATE_DIR}/calls.log"
printf '%s\n' 'stopped' > "${MOCK_STATE_DIR}/container-state"
EOF
    chmod +x "${SCENARIO_DIR}/project/scripts/backup.sh"

    cat > "${SCENARIO_DIR}/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

state_file="${MOCK_STATE_DIR}/container-state"
health_file="${MOCK_STATE_DIR}/container-health"
calls_file="${MOCK_STATE_DIR}/calls.log"

if [ "${1:-}" = "compose" ]; then
    shift
    while [ "${1:-}" = "--env-file" ] || [ "${1:-}" = "-f" ]; do
        shift 2
    done
    compose_command="$1"
    shift
    printf 'compose %s %s\n' "${compose_command}" "$*" >> "${calls_file}"

    case "${compose_command}" in
        config)
            exit 0
            ;;
        ps)
            include_stopped=false
            for argument in "$@"; do
                if [ "${argument}" = "--all" ] || [ "${argument}" = "-a" ]; then
                    include_stopped=true
                fi
            done
            if [ "${include_stopped}" = true ] || [ "$(cat "${state_file}")" = "running" ]; then
                printf '%s\n' 'container-id'
            fi
            ;;
        pull)
            if [ "${MOCK_FAIL_PULL:-false}" = true ]; then
                exit 1
            fi
            ;;
        start)
            printf '%s\n' 'running' > "${state_file}"
            ;;
        up)
            if [ "${MOCK_FAIL_UP:-false}" = true ] && [ ! -f "${MOCK_STATE_DIR}/rollback-restored" ]; then
                exit 1
            fi
            printf '%s\n' 'running' > "${state_file}"
            if [ -f "${MOCK_STATE_DIR}/rollback-restored" ]; then
                printf '%s\n' 'healthy' > "${health_file}"
            elif [ "${MOCK_FAIL_HEALTH:-false}" = true ]; then
                printf '%s\n' 'unhealthy' > "${health_file}"
            else
                printf '%s\n' 'healthy' > "${health_file}"
            fi
            ;;
        *)
            echo "Unexpected compose command: ${compose_command}" >&2
            exit 1
            ;;
    esac
    exit 0
fi

if [ "${1:-}" = "inspect" ]; then
    format="$3"
    case "${format}" in
        *State.Running*)
            if [ "$(cat "${state_file}")" = "running" ]; then
                printf '%s\n' 'true'
            else
                printf '%s\n' 'false'
            fi
            ;;
        *State.Health*)
            cat "${health_file}"
            ;;
        *Config.Image*)
            printf '%s\n' 'ghcr.io/ich777/steamcmd:vrising'
            ;;
        *.Image*)
            printf '%s\n' 'sha256:previous-image'
            ;;
        *)
            echo "Unexpected inspect format: ${format}" >&2
            exit 1
            ;;
    esac
    exit 0
fi

if [ "${1:-}" = "image" ] && [ "${2:-}" = "tag" ]; then
    printf 'docker image tag %s %s\n' "$3" "$4" >> "${calls_file}"
    if [[ "$3" == vrising-rollback:* ]] && [ "$4" = "ghcr.io/ich777/steamcmd:vrising" ]; then
        : > "${MOCK_STATE_DIR}/rollback-restored"
    fi
    exit 0
fi

echo "Unexpected docker command: $*" >&2
exit 1
EOF
    chmod +x "${SCENARIO_DIR}/bin/docker"
    printf '%s\n' 'running' > "${SCENARIO_DIR}/state/container-state"
    printf '%s\n' 'healthy' > "${SCENARIO_DIR}/state/container-health"
    : > "${SCENARIO_DIR}/state/calls.log"
}

run_update_expect_failure() {
    local fail_pull="$1"
    local fail_health="$2"
    local fail_up="$3"
    local exit_code

    set +e
    PATH="${SCENARIO_DIR}/bin:${PATH}" \
        MOCK_STATE_DIR="${SCENARIO_DIR}/state" \
        MOCK_FAIL_PULL="${fail_pull}" \
        MOCK_FAIL_HEALTH="${fail_health}" \
        MOCK_FAIL_UP="${fail_up}" \
        bash "${SCENARIO_DIR}/project/scripts/update.sh" \
        > "${SCENARIO_DIR}/output.log" 2>&1
    exit_code=$?
    set -e

    if [ "${exit_code}" -eq 0 ]; then
        echo "ERROR: Failure-injection scenario unexpectedly succeeded." >&2
        cat "${SCENARIO_DIR}/output.log" >&2
        exit 1
    fi
}

echo "Step 1/4: Verifying pull failure restarts the original container..."
prepare_scenario "pull-failure"
run_update_expect_failure true false false
grep -Eq '^docker image tag sha256:previous-image vrising-rollback:' "${SCENARIO_DIR}/state/calls.log"
grep -qx 'compose start vrising' "${SCENARIO_DIR}/state/calls.log"
grep -q 'Update failed before replacement; restarting the original container' "${SCENARIO_DIR}/output.log"
grep -qx 'running' "${SCENARIO_DIR}/state/container-state"
test ! -e "${SCENARIO_DIR}/data/vrising/.maintenance.lock"

echo "Step 2/4: Verifying pull failure preserves an intentionally stopped server..."
prepare_scenario "stopped-pull-failure"
printf '%s\n' 'stopped' > "${SCENARIO_DIR}/state/container-state"
run_update_expect_failure true false false
if grep -q '^compose start vrising$' "${SCENARIO_DIR}/state/calls.log"; then
    echo "ERROR: Update restarted a server that was stopped before maintenance." >&2
    exit 1
fi
grep -qx 'stopped' "${SCENARIO_DIR}/state/container-state"
test ! -e "${SCENARIO_DIR}/data/vrising/.maintenance.lock"

echo "Step 3/4: Verifying recreate failure restores the previous image..."
prepare_scenario "recreate-failure"
run_update_expect_failure false false true
grep -Eq '^docker image tag vrising-rollback:.* ghcr.io/ich777/steamcmd:vrising$' "${SCENARIO_DIR}/state/calls.log"
grep -q 'Previous container image restored successfully' "${SCENARIO_DIR}/output.log"
grep -qx 'healthy' "${SCENARIO_DIR}/state/container-health"
test ! -e "${SCENARIO_DIR}/data/vrising/.maintenance.lock"

echo "Step 4/4: Verifying unhealthy replacement restores the previous image..."
prepare_scenario "health-failure"
run_update_expect_failure false true false
grep -Eq '^docker image tag sha256:previous-image vrising-rollback:' "${SCENARIO_DIR}/state/calls.log"
grep -Eq '^docker image tag vrising-rollback:.* ghcr.io/ich777/steamcmd:vrising$' "${SCENARIO_DIR}/state/calls.log"
grep -q 'Previous container image restored successfully' "${SCENARIO_DIR}/output.log"
grep -qx 'running' "${SCENARIO_DIR}/state/container-state"
grep -qx 'healthy' "${SCENARIO_DIR}/state/container-health"
test ! -e "${SCENARIO_DIR}/data/vrising/.maintenance.lock"

echo "All update recovery tests passed."