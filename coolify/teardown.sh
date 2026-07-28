#!/bin/bash
# Coolify — Teardown Script
# https://github.com/elvismercado/infra-docker-templates
#
# Reverses everything setup.sh creates. By default, data is preserved.
# Pass --remove-data to also delete the data directory (database, configs, etc.)
#
# Usage:
#   ./teardown.sh                # Stop containers, remove network/symlink/SSH keys. Keep data.
#   ./teardown.sh --remove-data  # Same as above, plus delete all data. IRREVERSIBLE.

set -euo pipefail

# =============================================================================
# CONFIGURATION — must match setup.sh values
# =============================================================================
VOLUMES_BASE="${VOLUMES_BASE:-/tmp}"
CONTAINER_NAME="${CONTAINER_NAME:-coolify}"

# Derived paths (mirrors setup.sh)
DATA_PATH="${VOLUMES_BASE}/${CONTAINER_NAME}/data/coolify"
ENV_FILE="${DATA_PATH}/source/.env"

# =============================================================================
# Parse arguments
# =============================================================================
REMOVE_DATA=false
for arg in "$@"; do
    case "$arg" in
        --remove-data) REMOVE_DATA=true ;;
        *) echo "Unknown option: $arg"; echo "Usage: $0 [--remove-data]"; exit 1 ;;
    esac
done

# =============================================================================
# Confirmation
# =============================================================================
echo "==========================================="
echo "  Coolify Teardown"
echo "==========================================="
echo ""
echo "  VOLUMES_BASE:   ${VOLUMES_BASE}"
echo "  CONTAINER_NAME: ${CONTAINER_NAME}"
echo "  DATA_PATH:      ${DATA_PATH}"
echo ""
echo "  This will:"
echo "    - Stop and remove Coolify containers"
echo "    - Remove the 'coolify' Docker network"
echo "    - Remove SSH authorized_keys entries"
echo "    - Remove the /data/coolify symlink"
if [ "${REMOVE_DATA}" = true ]; then
    echo "    - DELETE all data at ${VOLUMES_BASE}/${CONTAINER_NAME} (IRREVERSIBLE)"
else
    echo "    - Keep data at ${DATA_PATH}"
fi
echo ""

read -r -p "Proceed? [y/N] " response
case "${response}" in
    [yY][eE][sS]|[yY]) ;;
    *) echo "Aborted."; exit 0 ;;
esac
echo ""

# =============================================================================
# Step 1: Stop and remove containers
# =============================================================================
echo "Step 1/5: Stopping Coolify containers..."
if [ -f "/data/coolify/source/docker-compose.yml" ] && [ -f "${ENV_FILE}" ]; then
    COMPOSE_CMD="docker compose --env-file /data/coolify/source/.env"
    COMPOSE_CMD="${COMPOSE_CMD} -f /data/coolify/source/docker-compose.yml"
    COMPOSE_CMD="${COMPOSE_CMD} -f /data/coolify/source/docker-compose.prod.yml"
    if [ -f "/data/coolify/source/docker-compose.custom.yml" ]; then
        COMPOSE_CMD="${COMPOSE_CMD} -f /data/coolify/source/docker-compose.custom.yml"
    fi
    ${COMPOSE_CMD} down --remove-orphans 2>/dev/null || true
    echo "  Containers stopped and removed."
else
    echo "  No compose files found — skipping."
fi
echo ""

# =============================================================================
# Step 2: Remove Docker network
# =============================================================================
echo "Step 2/5: Removing Docker network..."
if docker network inspect coolify >/dev/null 2>&1; then
    docker network rm coolify
    echo "  Network 'coolify' removed."
else
    echo "  Network 'coolify' not found — skipping."
fi
echo ""

# =============================================================================
# Step 3: Remove SSH authorized_keys entries
# =============================================================================
echo "Step 3/5: Cleaning SSH authorized_keys..."
if [ -f ~/.ssh/authorized_keys ] && grep -q "coolify" ~/.ssh/authorized_keys 2>/dev/null; then
    sed -i '/coolify/d' ~/.ssh/authorized_keys
    echo "  Removed coolify entries from authorized_keys."
else
    echo "  No coolify entries found — skipping."
fi
echo ""

# =============================================================================
# Step 4: Remove symlink
# =============================================================================
echo "Step 4/5: Removing /data/coolify symlink..."
if [ -L "/data/coolify" ]; then
    rm -f /data/coolify
    echo "  Symlink removed."
    # Clean up empty /data directory
    if [ -d "/data" ] && [ -z "$(ls -A /data 2>/dev/null)" ]; then
        rmdir /data
        echo "  Removed empty /data directory."
    fi
elif [ -d "/data/coolify" ]; then
    echo "  /data/coolify is a real directory — not removing (manual cleanup needed)."
else
    echo "  No symlink found — skipping."
fi
echo ""

# =============================================================================
# Step 5: Remove data directory
# =============================================================================
echo "Step 5/5: Data directory..."
if [ "${REMOVE_DATA}" = true ]; then
    if [ -d "${VOLUMES_BASE}/${CONTAINER_NAME}" ]; then
        rm -rf "${VOLUMES_BASE}/${CONTAINER_NAME}"
        echo "  Deleted ${VOLUMES_BASE}/${CONTAINER_NAME}."
    else
        echo "  Directory not found — skipping."
    fi
else
    echo "  Preserved (pass --remove-data to delete)."
fi
echo ""

# =============================================================================
echo "==========================================="
echo "  Teardown complete."
echo "==========================================="
