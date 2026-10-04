#!/usr/bin/env bash
# chmod +x fail2ban_install.sh
# sudo ./fail2ban_install.sh

# curl -fsSL https://raw.githubusercontent.com/wjadams17/fail2ban/main/fail2ban_install.sh | sudo bash


set -euo pipefail

# ============================================================
# Fail2Ban Central Configuration Installer
#
# Supported:
#   - RHEL / Rocky / AlmaLinux / CentOS
#   - Ubuntu / Debian
#
# What this script does:
#   1. Checks whether Fail2Ban is installed
#   2. Installs it if necessary
#   3. Downloads jail.local from GitHub
#   4. Backs up the existing jail.local
#   5. Validates the new configuration
#   6. Installs the new configuration
#   7. Restarts/reloads Fail2Ban
# ============================================================

# -------- CONFIGURATION -------------------------------------

# Change this to your GitHub raw file URL.
GITHUB_CONFIG_URL="https://raw.githubusercontent.com/wjadams/Fail2Ban/main/jail.local"

FAIL2BAN_CONFIG="/etc/fail2ban/jail.local"
BACKUP_DIR="/etc/fail2ban/backup"

# ------------------------------------------------------------

if [[ "$EUID" -ne 0 ]]; then
    echo "ERROR: This script must be run as root."
    echo "Try: sudo $0"
    exit 1
fi

echo "=========================================="
echo " Fail2Ban Configuration Installer"
echo "=========================================="
echo

# ------------------------------------------------------------
# Detect operating system
# ------------------------------------------------------------

if [[ ! -f /etc/os-release ]]; then
    echo "ERROR: Cannot determine operating system."
    exit 1
fi

source /etc/os-release

echo "Detected OS: ${PRETTY_NAME:-unknown}"
echo

# ------------------------------------------------------------
# Determine package manager
# ------------------------------------------------------------

if command -v apt-get >/dev/null 2>&1; then
    PACKAGE_MANAGER="apt"

elif command -v dnf >/dev/null 2>&1; then
    PACKAGE_MANAGER="dnf"

elif command -v yum >/dev/null 2>&1; then
    PACKAGE_MANAGER="yum"

else
    echo "ERROR: Unsupported package manager."
    exit 1
fi

# ------------------------------------------------------------
# Install Fail2Ban if necessary
# ------------------------------------------------------------

if command -v fail2ban-server >/dev/null 2>&1; then

    echo "Fail2Ban is already installed."

    FAIL2BAN_VERSION=$(fail2ban-server --version 2>/dev/null | head -n 1 || true)

    if [[ -n "$FAIL2BAN_VERSION" ]]; then
        echo "Installed version: $FAIL2BAN_VERSION"
    fi

else

    echo "Fail2Ban is NOT installed."
    echo "Installing Fail2Ban..."

    case "$PACKAGE_MANAGER" in

        apt)
            export DEBIAN_FRONTEND=noninteractive

            apt-get update
            apt-get install -y fail2ban

            ;;

        dnf)
            dnf install -y fail2ban

            ;;

        yum)
            yum install -y fail2ban

            ;;

    esac

    echo "Fail2Ban installed successfully."
fi

echo

# ------------------------------------------------------------
# Make sure configuration directory exists
# ------------------------------------------------------------

mkdir -p /etc/fail2ban
mkdir -p "$BACKUP_DIR"

# ------------------------------------------------------------
# Download configuration from GitHub
# ------------------------------------------------------------

TEMP_CONFIG=$(mktemp)

trap 'rm -f "$TEMP_CONFIG"' EXIT

echo "Downloading centralized configuration..."
echo "Source:"
echo "$GITHUB_CONFIG_URL"
echo

if command -v curl >/dev/null 2>&1; then

    curl \
        --fail \
        --silent \
        --show-error \
        --location \
        --connect-timeout 10 \
        --max-time 30 \
        "$GITHUB_CONFIG_URL" \
        -o "$TEMP_CONFIG"

elif command -v wget >/dev/null 2>&1; then

    wget \
        --quiet \
        --timeout=30 \
        --output-document="$TEMP_CONFIG" \
        "$GITHUB_CONFIG_URL"

else

    echo "ERROR: Neither curl nor wget is installed."
    exit 1

fi

# ------------------------------------------------------------
# Make sure we actually downloaded something
# ------------------------------------------------------------

if [[ ! -s "$TEMP_CONFIG" ]]; then
    echo "ERROR: Downloaded configuration is empty."
    exit 1
fi

echo "Configuration downloaded successfully."
echo

# ------------------------------------------------------------
# Display a basic sanity check
# ------------------------------------------------------------

if ! grep -q "^\[DEFAULT\]" "$TEMP_CONFIG"; then
    echo "WARNING: Downloaded file does not contain [DEFAULT]."
    echo "Continuing, but please verify the configuration."
    echo
fi

# ------------------------------------------------------------
# Back up existing configuration
# ------------------------------------------------------------

if [[ -f "$FAIL2BAN_CONFIG" ]]; then

    TIMESTAMP=$(date '+%Y%m%d-%H%M%S')

    BACKUP_FILE="$BACKUP_DIR/jail.local.$TIMESTAMP"

    echo "Backing up existing configuration:"
    echo "$BACKUP_FILE"

    cp -p "$FAIL2BAN_CONFIG" "$BACKUP_FILE"

    echo

fi

# ------------------------------------------------------------
# Temporarily install configuration for validation
# ------------------------------------------------------------

cp "$TEMP_CONFIG" "$FAIL2BAN_CONFIG"

echo "Testing Fail2Ban configuration..."

if fail2ban-client -t; then

    echo
    echo "Configuration test PASSED."

else

    echo
    echo "ERROR: Configuration test FAILED."
    echo "Restoring previous configuration..."

    if [[ -n "${BACKUP_FILE:-}" && -f "$BACKUP_FILE" ]]; then
        cp -p "$BACKUP_FILE" "$FAIL2BAN_CONFIG"
    else
        rm -f "$FAIL2BAN_CONFIG"
    fi

    echo "Previous configuration restored."
    exit 1

fi

echo

# ------------------------------------------------------------
# Enable and start Fail2Ban
# ------------------------------------------------------------

systemctl enable fail2ban >/dev/null 2>&1 || true

if systemctl is-active --quiet fail2ban; then

    echo "Reloading Fail2Ban..."

    fail2ban-client reload

else

    echo "Fail2Ban is not currently running."
    echo "Starting Fail2Ban..."

    systemctl start fail2ban

fi

# ------------------------------------------------------------
# Verify service
# ------------------------------------------------------------

echo
echo "Checking Fail2Ban status..."
echo

if systemctl is-active --quiet fail2ban; then

    echo "SUCCESS: Fail2Ban is running."

else

    echo "ERROR: Fail2Ban failed to start."
    systemctl status fail2ban --no-pager || true
    exit 1

fi

echo
echo "Enabled jails:"
fail2ban-client status || true

echo
echo "=========================================="
echo " Installation/update completed"
echo "=========================================="
