#!/bin/bash
set -e

# Launch KIAUH interactively.

TARGET_USER="${SUDO_USER:-}"
if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = "root" ]; then
    if id pi >/dev/null 2>&1; then
        TARGET_USER="pi"
    else
        TARGET_USER="$(whoami)"
    fi
fi

TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
if [ -z "$TARGET_HOME" ]; then
    echo -e "\e[31m❌ Could not determine home directory for user: $TARGET_USER\e[0m"
    exit 1
fi

KIAUH_SCRIPT="${TARGET_HOME}/kiauh/kiauh.sh"

if [ ! -f "$KIAUH_SCRIPT" ]; then
    echo -e "\e[31m❌ KIAUH script not found: $KIAUH_SCRIPT\e[0m"
    echo -e "\e[33m💡 Run add_kiauh.sh first to clone KIAUH.\e[0m"
    exit 1
fi

chmod +x "$KIAUH_SCRIPT"

if pgrep -f "[k]iauh.sh" >/dev/null 2>&1; then
    echo -e "\e[33m⚠️ KIAUH is already running. Skipping new launch.\e[0m"
    exit 0
fi

echo -e "\e[34m🚀 Starting KIAUH as user: $TARGET_USER\e[0m"

if [ "$(id -u)" -eq 0 ] && [ "$TARGET_USER" != "root" ]; then
    exec sudo -u "$TARGET_USER" bash "$KIAUH_SCRIPT"
else
    exec bash "$KIAUH_SCRIPT"
fi
