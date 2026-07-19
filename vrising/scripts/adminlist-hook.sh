#!/usr/bin/env bash
# Runs INSIDE the ich777 V Rising container, not on the host.
#
# The image's start script copies /opt/custom/user.sh to /opt/scripts/start-user.sh
# and executes it as root before launching the server. docker-compose.yml mounts
# this file there read-only, so it runs on every container start.
#
# Purpose: regenerate save-data/Settings/adminlist.txt from the ADMIN_STEAM_IDS
# environment variable, so in-game admins are managed declaratively from .env.
#
# Behaviour:
# - ADMIN_STEAM_IDS empty  -> do nothing (any hand-maintained adminlist.txt is
#   left untouched, preserving the manual workflow).
# - ADMIN_STEAM_IDS set    -> adminlist.txt is rewritten from it every start.
#   V Rising hot-reloads adminlist.txt, so no restart is required for changes.
#
# banlist.txt is never touched here; in-game bans persist independently.
set -uo pipefail

# Base dir is fixed inside the container. The override exists only so the parser
# can be unit-tested on a host; it is not used in normal operation.
BASE_DIR="${VRISING_SERVERFILES_DIR:-/serverdata/serverfiles}"
SETTINGS_DIR="${BASE_DIR}/save-data/Settings"
DEFAULT_SETTINGS_DIR="${BASE_DIR}/VRisingServer_Data/StreamingAssets/Settings"
ADMIN_FILE="${SETTINGS_DIR}/adminlist.txt"

if [ -z "${ADMIN_STEAM_IDS:-}" ]; then
    echo "---adminlist: ADMIN_STEAM_IDS is empty, leaving adminlist.txt unmanaged---"
    exit 0
fi

# Mirror the server's own first-run behaviour: if the persistent Settings folder
# does not exist yet, copy the shipped defaults first. This prevents pre-creating
# the folder from suppressing the default ServerHostSettings.json /
# ServerGameSettings.json that the server copies on first start.
if [ ! -d "${SETTINGS_DIR}" ]; then
    if [ -d "${DEFAULT_SETTINGS_DIR}" ]; then
        mkdir -p "${BASE_DIR}/save-data"
        cp -R "${DEFAULT_SETTINGS_DIR}" "${BASE_DIR}/save-data/"
    else
        mkdir -p "${SETTINGS_DIR}"
    fi
fi

tmp_file="${ADMIN_FILE}.tmp"
: > "${tmp_file}"

# Accept comma-, space-, or newline-separated steamID64 values. The trailing \n
# ensures the final token is not dropped by read at EOF.
printf '%s\n' "${ADMIN_STEAM_IDS}" | tr ',' '\n' | tr ' ' '\n' | while IFS= read -r raw_id; do
    id="$(printf '%s' "${raw_id}" | tr -d '[:space:]')"
    [ -z "${id}" ] && continue
    if printf '%s' "${id}" | grep -Eq '^[0-9]{17}$'; then
        printf '%s\n' "${id}" >> "${tmp_file}"
    else
        echo "---adminlist: skipping invalid Steam ID (expected 17 digits): ${id}---"
    fi
done

mv "${tmp_file}" "${ADMIN_FILE}"
echo "---adminlist: wrote $(grep -c '' "${ADMIN_FILE}") admin Steam ID(s) to adminlist.txt---"
