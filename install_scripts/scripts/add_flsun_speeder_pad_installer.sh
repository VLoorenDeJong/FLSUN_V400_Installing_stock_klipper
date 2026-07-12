#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive

print_status()  { printf "\033[34m🔧 %s\033[0m\n" "$1"; }
print_success() { printf "\033[32m✅ %s\033[0m\n" "$1"; }
print_warning() { printf "\033[33m⚠️  %s\033[0m\n" "$1"; }
print_error()   { printf "\033[31m❌ %s\033[0m\n" "$1"; }

INSTALLER_URL="https://raw.githubusercontent.com/Guilouz/Klipper-Flsun-Speeder-Pad/main/Downloads/sp_installer1.sh"
STATE_DIR="/var/lib/linuxsetups"
STATE_FILE="${STATE_DIR}/flsun_speeder_pad_installer.done"
FORCE_RUN="${FORCE_RUN_FL_SPEEDEDPAD_INSTALLER:-0}"
# Enable debug mode for this script only
DEBUG=true
LOG_FILE="/var/log/flsun_installer.log"

debug() {
    [ "$DEBUG" = "true" ] && echo "[DEBUG][speeder_pad_installer] $1" >> "$LOG_FILE"
}

if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must run with sudo/root privileges."
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    print_status "Installing curl"
    apt-get update -qq
    apt-get install -y -qq curl
fi

TARGET_USER="${SUDO_USER:-}"
if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = "root" ]; then
    if id pi >/dev/null 2>&1; then
        TARGET_USER="pi"
    else
        TARGET_USER="$(whoami)"
    fi
fi

TARGET_DIR="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
TARGET_SCRIPT="${TARGET_DIR}/sp_installer1.sh"

if [ -z "$TARGET_DIR" ]; then
    print_error "Could not determine home directory for user: $TARGET_USER"
    exit 1
fi

if [ ! -d "$TARGET_DIR" ]; then
    print_error "Target directory does not exist: $TARGET_DIR"
    print_warning "This installer expects the Speeder Pad/pi environment."
    exit 1
fi

if [ -f "$STATE_FILE" ] && [ "$FORCE_RUN" != "1" ]; then
    print_warning "Speeder Pad installer already executed before. Skipping."
    print_warning "To force rerun: FORCE_RUN_FL_SPEEDEDPAD_INSTALLER=1 sudo bash $0"
    exit 0
fi

print_status "Downloading Speeder Pad installer to $TARGET_SCRIPT"

# -------------------------------
# NEW: fallback logic
# -------------------------------

# Resolve repo root relative to this script
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FALLBACK_INSTALLER="${REPO_ROOT}/install_scripts/scripts/FallbackCopiedScripts/sp_installer1.sh"

debug "Repo root resolved to: $REPO_ROOT"
debug "Fallback installer path: $FALLBACK_INSTALLER"

if curl -fsSL "$INSTALLER_URL" -o "$TARGET_SCRIPT"; then
    debug "Remote installer downloaded successfully."
else
    print_warning "Remote installer unavailable, using fallback."
    debug "Remote installer download failed."

    if [ -f "$FALLBACK_INSTALLER" ]; then
        cp "$FALLBACK_INSTALLER" "$TARGET_SCRIPT"
        debug "Fallback installer copied to $TARGET_SCRIPT"
    else
        print_error "Fallback installer not found at: $FALLBACK_INSTALLER"
        exit 1
    fi
fi

chmod +x "$TARGET_SCRIPT"

print_status "Running Speeder Pad installer"
bash "$TARGET_SCRIPT"

mkdir -p "$STATE_DIR"
date -u +"%Y-%m-%dT%H:%M:%SZ" > "$STATE_FILE"

print_success "Speeder Pad installer completed"
