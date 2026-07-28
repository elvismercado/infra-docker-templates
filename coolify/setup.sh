#!/bin/bash
# Coolify — Idempotent Setup Script
# https://github.com/elvismercado/infra-docker-templates
#
# =============================================================================
# WHAT THIS IS
# =============================================================================
# A modified version of Coolify's manual installation, adapted for running on a
# Docker host (e.g., Unraid) where data lives under a configurable base path
# instead of the hardcoded /data/coolify.
#
# The official installation assumes a dedicated VM or cloud server with data at
# /data/coolify. This script preserves that structure under VOLUMES_BASE so it
# integrates with the host's storage layout while keeping the official CDN
# compose files working unmodified (via a symlink).
#
# =============================================================================
# HOW IT WORKS
# =============================================================================
# 1. Creates the Coolify directory tree at ${VOLUMES_BASE}/${CONTAINER_NAME}/data/coolify
# 2. Symlinks /data/coolify → that path (so CDN compose paths resolve)
# 3. Downloads the official compose files from Coolify's CDN
# 4. Merges them with a custom override (docker-compose.custom.yml) for:
#    - com.service labels (repo convention)
#    - Host-path postgres volume (Unraid-friendly, not a Docker named volume)
#    - Closed Soketi external ports (browser proxies through Coolify UI)
# 5. Generates secrets only on first run — never overwrites existing values
# 6. Pre-creates root user if ROOT_USERNAME/EMAIL/PASSWORD are all provided
#    (eliminates the open registration security window on first boot)
# 7. Disables Coolify's built-in auto-update (upgrades via setup.sh re-runs)
# 8. Pre-pulls new Docker images (while old containers still serve traffic)
# 9. Stops running Coolify containers (skipped on first install)
#
# The custom override file is always overwritten from the repo on each run.
# A timestamped backup of the server copy is created before overwriting.
#
# =============================================================================
# IDEMPOTENT = SAFE TO RE-RUN
# =============================================================================
# Every step checks for existing state before acting:
# - Directories: mkdir -p (inherently safe)
# - Symlink: skipped if already correct
# - SSH key: skipped if already exists
# - CDN files: always re-downloaded (this IS the upgrade mechanism)
# - .env secrets: only fills empty/missing values, never overwrites
# - Custom override: backed up (timestamped) then overwritten from repo
# - Docker network: skipped if already exists
# - Container stop: skipped if no containers are running (first install)
#
# Re-running this script upgrades Coolify to the latest version by pulling
# fresh CDN configs and the latest Docker images.
#
# =============================================================================
# REFERENCES
# =============================================================================
# Manual installation:   https://coolify.io/docs/get-started/installation#manual-installation
# Custom overrides:      https://coolify.io/docs/knowledge-base/custom-compose-overrides
# Official install.sh:   https://github.com/coollabsio/coolify/blob/v4.x/scripts/install.sh
# =============================================================================

set -euo pipefail

# =============================================================================
# CONFIGURATION — edit these or export them before running
# =============================================================================
VOLUMES_BASE="${VOLUMES_BASE:-/tmp}"
CONTAINER_NAME="${CONTAINER_NAME:-coolify}"
SUBNET="${SUBNET:-10.42.0.0/24}"

# Root user — pre-creates admin account on first boot (all 3 required together)
ROOT_USERNAME="${ROOT_USERNAME:-}"
ROOT_USER_EMAIL="${ROOT_USER_EMAIL:-}"
ROOT_USER_PASSWORD="${ROOT_USER_PASSWORD:-}"

# Derived paths (do not edit)
DATA_PATH="${VOLUMES_BASE}/${CONTAINER_NAME}/data/coolify"
DB_PATH="${DATA_PATH}/db"
REDIS_PATH="${DATA_PATH}/redis"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CDN="https://cdn.coollabs.io/coolify"
SSH_KEY_PATH="${DATA_PATH}/ssh/keys/id.root@host.docker.internal"
ENV_FILE="${DATA_PATH}/source/.env"

# =============================================================================
# HELPER: update_env_var — fills empty/missing .env values, never overwrites
# Adapted from the official Coolify install.sh
# =============================================================================
update_env_var() {
    local key="$1"
    local value="$2"

    if grep -q "^${key}=$" "$ENV_FILE"; then
        # Key exists but value is empty — fill it
        sed -i "s|^${key}=$|${key}=${value}|" "$ENV_FILE"
        echo "  Updated ${key} (was empty)"
    elif ! grep -q "^${key}=" "$ENV_FILE"; then
        # Key is missing entirely — append it
        printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
        echo "  Added ${key} (was missing)"
    fi
    # If key already has a value → leave it alone (never overwrite)
}

# =============================================================================
echo "==========================================="
echo "  Coolify Setup — $(date +%Y-%m-%d)"
echo "==========================================="
echo ""
echo "  VOLUMES_BASE:   ${VOLUMES_BASE}"
echo "  CONTAINER_NAME: ${CONTAINER_NAME}"
echo "  DATA_PATH:      ${DATA_PATH}"
echo "  DB_PATH:        ${DB_PATH}"
echo "  REDIS_PATH:     ${REDIS_PATH}"
echo "  SUBNET:         ${SUBNET}"
if [ -n "${ROOT_USERNAME}" ] && [ -n "${ROOT_USER_EMAIL}" ] && [ -n "${ROOT_USER_PASSWORD}" ]; then
    echo "  ROOT_USER:      ${ROOT_USERNAME} <${ROOT_USER_EMAIL}>"
else
    echo "  ROOT_USER:      (not set — will use registration page)"
fi
echo ""

# =============================================================================
# STEP 1: Create directories
# =============================================================================
echo "Step 1/12: Creating directories..."
mkdir -p "${DATA_PATH}"/{source,ssh,applications,databases,backups,services,proxy,sentinel}
mkdir -p "${DATA_PATH}"/ssh/{keys,mux}
mkdir -p "${DATA_PATH}"/proxy/dynamic
mkdir -p "${DB_PATH}"
mkdir -p "${REDIS_PATH}"
echo "  Done."
echo ""

# =============================================================================
# STEP 2: Symlink /data/coolify → DATA_PATH
# =============================================================================
echo "Step 2/12: Configuring /data/coolify symlink..."
if [ "${DATA_PATH}" = "/data/coolify" ]; then
    echo "  DATA_PATH is /data/coolify — no symlink needed."
elif [ -L "/data/coolify" ]; then
    CURRENT_TARGET="$(readlink -f /data/coolify)"
    EXPECTED_TARGET="$(readlink -f "${DATA_PATH}")"
    if [ "${CURRENT_TARGET}" = "${EXPECTED_TARGET}" ]; then
        echo "  Symlink already correct: /data/coolify → ${DATA_PATH}"
    else
        echo "  ERROR: /data/coolify is a symlink but points to ${CURRENT_TARGET}"
        echo "         Expected: ${DATA_PATH}"
        echo "         Please remove it manually and re-run: rm /data/coolify"
        exit 1
    fi
elif [ -d "/data/coolify" ]; then
    echo "  ERROR: /data/coolify exists as a real directory."
    echo "         Please remove or move it first, then re-run."
    echo "         Example: mv /data/coolify /data/coolify.bak"
    exit 1
else
    mkdir -p /data
    ln -s "${DATA_PATH}" /data/coolify
    echo "  Created symlink: /data/coolify → ${DATA_PATH}"
fi
echo ""

# =============================================================================
# STEP 3: SSH key (first install only — Coolify manages keys after first boot)
# =============================================================================
echo "Step 3/12: Checking SSH key..."
if ls "${DATA_PATH}"/ssh/keys/ssh_key@* >/dev/null 2>&1; then
    echo "  Coolify is managing SSH keys from its database — skipping."
elif [ -f "${SSH_KEY_PATH}" ]; then
    echo "  SSH key already exists — skipping."
else
    ssh-keygen -f "${SSH_KEY_PATH}" -t ed25519 -N '' -C root@coolify
    echo "  SSH key generated."

    # Replace any stale "coolify" entries and add the new public key
    mkdir -p ~/.ssh
    touch ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
    sed -i '/coolify/d' ~/.ssh/authorized_keys
    cat "${SSH_KEY_PATH}.pub" >> ~/.ssh/authorized_keys
    echo "  Public key added to authorized_keys."
fi
echo ""

# =============================================================================
# STEP 4: Download CDN files (always — this IS the upgrade mechanism)
# =============================================================================
echo "Step 4/12: Downloading latest Coolify configuration from CDN..."
curl -fsSL -L "${CDN}/docker-compose.yml" -o "${DATA_PATH}/source/docker-compose.yml"
curl -fsSL -L "${CDN}/docker-compose.prod.yml" -o "${DATA_PATH}/source/docker-compose.prod.yml"
curl -fsSL -L "${CDN}/.env.production" -o "${DATA_PATH}/source/.env.production"
curl -fsSL -L "${CDN}/upgrade.sh" -o "${DATA_PATH}/source/upgrade.sh"
echo "  Done."
echo ""

# =============================================================================
# STEP 5: Setup .env (idempotent — only fills empty/missing values)
# =============================================================================
echo "Step 5/12: Configuring environment file..."
if [ ! -f "${ENV_FILE}" ]; then
    cp "${DATA_PATH}/source/.env.production" "${ENV_FILE}"
    echo "  Created .env from .env.production template."
else
    echo "  .env already exists — updating missing values only."
fi

update_env_var "APP_ID" "$(openssl rand -hex 16)"
update_env_var "APP_KEY" "base64:$(openssl rand -base64 32)"
update_env_var "DB_PASSWORD" "$(openssl rand -base64 32)"
update_env_var "REDIS_PASSWORD" "$(openssl rand -base64 32)"
update_env_var "PUSHER_APP_ID" "$(openssl rand -hex 32)"
update_env_var "PUSHER_APP_KEY" "$(openssl rand -hex 32)"
update_env_var "PUSHER_APP_SECRET" "$(openssl rand -hex 32)"

# Root user — only set if all 3 are provided (mirrors upstream install.sh)
if [ -n "${ROOT_USERNAME}" ] && [ -n "${ROOT_USER_EMAIL}" ] && [ -n "${ROOT_USER_PASSWORD}" ]; then
    update_env_var "ROOT_USERNAME" "${ROOT_USERNAME}"
    update_env_var "ROOT_USER_EMAIL" "${ROOT_USER_EMAIL}"
    update_env_var "ROOT_USER_PASSWORD" "${ROOT_USER_PASSWORD}"
fi

# Disable auto-update — upgrades happen by re-running this script
update_env_var "AUTOUPDATE" "false"
echo "  Done."
echo ""

# =============================================================================
# STEP 6: Set permissions
# =============================================================================
echo "Step 6/12: Setting permissions..."
chown -R 9999:root "${DATA_PATH}"
chmod -R 700 "${DATA_PATH}"
echo "  Done."
echo ""

# =============================================================================
# STEP 7: Copy custom override (backs up existing, then overwrites from repo)
# =============================================================================
echo "Step 7/12: Updating custom compose override..."
if [ -f "${SCRIPT_DIR}/docker-compose.custom.yml" ]; then
    if [ -f "${DATA_PATH}/source/docker-compose.custom.yml" ]; then
        BACKUP="${DATA_PATH}/source/docker-compose.custom.yml.bak.$(date +%Y%m%d-%H%M%S)"
        cp "${DATA_PATH}/source/docker-compose.custom.yml" "${BACKUP}"
        echo "  Backed up existing override to $(basename "${BACKUP}")"
    fi
    cp "${SCRIPT_DIR}/docker-compose.custom.yml" "${DATA_PATH}/source/docker-compose.custom.yml"
    echo "  Copied docker-compose.custom.yml from repo to server."
else
    echo "  WARNING: No docker-compose.custom.yml found in ${SCRIPT_DIR}"
    if [ -f "${DATA_PATH}/source/docker-compose.custom.yml" ]; then
        echo "           Keeping existing server override."
    else
        echo "           Coolify will start without custom overrides."
    fi
fi
echo ""

# =============================================================================
# STEP 8: Create Docker network (idempotent — skip if exists)
# =============================================================================
echo "Step 8/12: Checking Docker network..."
if docker network inspect coolify >/dev/null 2>&1; then
    echo "  Network 'coolify' already exists — skipping."
else
    docker network create --attachable --subnet="${SUBNET}" coolify
    echo "  Created network 'coolify' with subnet ${SUBNET}."
fi
echo ""

# =============================================================================
# STEP 9: Validate configuration
# =============================================================================
echo "Step 9/12: Validating compose configuration..."
COMPOSE_CMD="docker compose --env-file /data/coolify/source/.env"
COMPOSE_CMD="${COMPOSE_CMD} -f /data/coolify/source/docker-compose.yml"
COMPOSE_CMD="${COMPOSE_CMD} -f /data/coolify/source/docker-compose.prod.yml"
if [ -f "/data/coolify/source/docker-compose.custom.yml" ]; then
    COMPOSE_CMD="${COMPOSE_CMD} -f /data/coolify/source/docker-compose.custom.yml"
fi

if ${COMPOSE_CMD} config >/dev/null 2>&1; then
    echo "  Configuration is valid."
else
    echo "  ERROR: Invalid compose configuration. Run manually to debug:"
    echo "  ${COMPOSE_CMD} config"
    exit 1
fi
echo ""

# =============================================================================
# STEP 10: Pull images (while old containers still serve traffic)
# =============================================================================
echo "Step 10/12: Pulling latest Docker images..."
${COMPOSE_CMD} pull
echo "  Done."
echo ""

# =============================================================================
# STEP 11: Stop running containers (skipped on first install)
# =============================================================================
echo "Step 11/12: Stopping running Coolify containers..."
if [ -n "$(${COMPOSE_CMD} ps -q 2>/dev/null)" ]; then
    ${COMPOSE_CMD} down --remove-orphans
    echo "  Containers stopped and removed."
    rm -f "${DATA_PATH}/ssh/mux/"*
    echo "  Cleared stale SSH mux sockets."
else
    echo "  No running containers found — skipping (first install)."
fi
echo ""

# =============================================================================
# STEP 12: Prompt to start Coolify
# =============================================================================
echo "==========================================="
echo "  Setup complete. Ready to start Coolify."
echo "==========================================="
echo ""

STARTUP_CMD="${COMPOSE_CMD} up -d --remove-orphans --force-recreate"

read -r -p "Start Coolify now? [y/N] " response
case "${response}" in
    [yY][eE][sS]|[yY])
        echo ""
        echo "Starting Coolify..."
        ${STARTUP_CMD}
        echo ""
        echo "Coolify is starting. Access it at http://<your-server-ip>:8000"
        if [ -n "${ROOT_USERNAME}" ] && [ -n "${ROOT_USER_EMAIL}" ] && [ -n "${ROOT_USER_PASSWORD}" ]; then
            echo ""
            echo "Root user will be created on first boot: ${ROOT_USERNAME} <${ROOT_USER_EMAIL}>"
        else
            echo ""
            echo "IMPORTANT: Create your admin account immediately after first start."
            echo "           Anyone who accesses the registration page first gains"
            echo "           full control of the server."
        fi
        ;;
    *)
        echo ""
        echo "Skipped. To start Coolify later, run:"
        echo ""
        echo "  ${STARTUP_CMD}"
        echo ""
        echo "Access it at http://<your-server-ip>:8000"
        if [ -n "${ROOT_USERNAME}" ] && [ -n "${ROOT_USER_EMAIL}" ] && [ -n "${ROOT_USER_PASSWORD}" ]; then
            echo "Root user will be created on first boot: ${ROOT_USERNAME} <${ROOT_USER_EMAIL}>"
        else
            echo ""
            echo "IMPORTANT: Create your admin account immediately after first start."
            echo "           Anyone who accesses the registration page first gains"
            echo "           full control of the server."
        fi
        ;;
esac
