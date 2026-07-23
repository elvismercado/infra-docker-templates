#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${PROJECT_DIR}/scripts/adminlist-hook.sh"
TEST_ROOT="$(mktemp -d)"

cleanup() {
    rm -rf -- "${TEST_ROOT}"
}
trap cleanup EXIT

run_hook() {
    local serverfiles_dir="$1"
    local admin_ids="$2"

    VRISING_SERVERFILES_DIR="${serverfiles_dir}" \
        ADMIN_STEAM_IDS="${admin_ids}" \
        bash "${HOOK}"
}

create_defaults() {
    local serverfiles_dir="$1"
    local defaults_dir="${serverfiles_dir}/VRisingServer_Data/StreamingAssets/Settings"

    mkdir -p "${defaults_dir}"
    printf '%s\n' 'default-host' > "${defaults_dir}/ServerHostSettings.json"
    printf '%s\n' 'default-game' > "${defaults_dir}/ServerGameSettings.json"
}

echo "Step 1/6: Verifying fresh-install deferral..."
fresh_dir="${TEST_ROOT}/fresh"
run_hook "${fresh_dir}" "76561198000000001"
if [ -e "${fresh_dir}/save-data/Settings" ]; then
    echo "ERROR: Fresh-install hook created Settings before defaults existed." >&2
    exit 1
fi

echo "Step 2/6: Verifying default settings initialization..."
defaults_dir="${TEST_ROOT}/defaults"
create_defaults "${defaults_dir}"
run_hook "${defaults_dir}" "76561198000000001"
test -f "${defaults_dir}/save-data/Settings/ServerHostSettings.json"
test -f "${defaults_dir}/save-data/Settings/ServerGameSettings.json"
grep -qx '76561198000000001' "${defaults_dir}/save-data/Settings/adminlist.txt"

echo "Step 3/6: Verifying partial settings are not overwritten or expanded..."
existing_dir="${TEST_ROOT}/existing"
create_defaults "${existing_dir}"
mkdir -p "${existing_dir}/save-data/Settings"
printf '%s\n' 'custom-host' > "${existing_dir}/save-data/Settings/ServerHostSettings.json"
run_hook "${existing_dir}" "76561198000000001"
grep -qx 'custom-host' "${existing_dir}/save-data/Settings/ServerHostSettings.json"
test ! -e "${existing_dir}/save-data/Settings/ServerGameSettings.json"

echo "Step 4/6: Verifying legacy admin-only settings repair..."
legacy_dir="${TEST_ROOT}/legacy"
create_defaults "${legacy_dir}"
mkdir -p "${legacy_dir}/save-data/Settings"
printf '%s\n' '76561198000000003' > "${legacy_dir}/save-data/Settings/adminlist.txt"
run_hook "${legacy_dir}" "76561198000000001"
grep -qx 'default-host' "${legacy_dir}/save-data/Settings/ServerHostSettings.json"
grep -qx 'default-game' "${legacy_dir}/save-data/Settings/ServerGameSettings.json"

echo "Step 5/6: Verifying ID parsing and invalid-entry filtering..."
parsing_dir="${TEST_ROOT}/parsing"
mkdir -p "${parsing_dir}/save-data/Settings"
run_hook "${parsing_dir}" $'76561198000000001, 76561198000000002\ninvalid-id'
printf '%s\n' '76561198000000001' '76561198000000002' > "${TEST_ROOT}/expected-adminlist.txt"
cmp "${TEST_ROOT}/expected-adminlist.txt" "${parsing_dir}/save-data/Settings/adminlist.txt"

echo "Step 6/6: Verifying empty IDs preserve manual administration..."
manual_dir="${TEST_ROOT}/manual"
mkdir -p "${manual_dir}/save-data/Settings"
printf '%s\n' '76561198000000003' > "${manual_dir}/save-data/Settings/adminlist.txt"
run_hook "${manual_dir}" ""
grep -qx '76561198000000003' "${manual_dir}/save-data/Settings/adminlist.txt"

echo "All adminlist hook tests passed."