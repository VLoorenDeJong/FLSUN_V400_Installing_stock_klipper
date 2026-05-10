#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive

INSTALLER_URL="https://raw.githubusercontent.com/Guilouz/Klipper-Flsun-Speeder-Pad/main/Downloads/sp_installer1.sh"
TARGET_DIR="/home/pi"
TARGET_SCRIPT="${TARGET_DIR}/sp_installer1.sh"
STATE_DIR="/var/lib/linuxsetups"
STATE_FILE="${STATE_DIR}/flsun_speeder_pad_installer.done"
FORCE_RUN="${FORCE_RUN_FL_SPEEDEDPAD_INSTALLER:-0}"

if [ "$(id -u)" -ne 0 ]; then
    echo -e "\e[31m❌ This script must run with sudo/root privileges.\e[0m"
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    echo -e "\e[34m🔧 Installing curl\e[0m"
    apt-get update -qq
    apt-get install -y -qq curl
fi

if [ ! -d "$TARGET_DIR" ]; then
    echo -e "\e[31m❌ Target directory does not exist: $TARGET_DIR\e[0m"
    echo -e "\e[33m💡 This installer expects the Speeder Pad/pi environment.\e[0m"
    exit 1
fi

if [ -f "$STATE_FILE" ] && [ "$FORCE_RUN" != "1" ]; then
    echo -e "\e[33m⚠️ Speeder Pad installer already executed before. Skipping.\e[0m"
    echo -e "\e[33m💡 To force rerun: FORCE_RUN_FL_SPEEDEDPAD_INSTALLER=1 sudo bash $0\e[0m"
    exit 0
fi

echo -e "\e[34m🔧 Downloading Speeder Pad installer to $TARGET_SCRIPT\e[0m"
curl -fsSL "$INSTALLER_URL" -o "$TARGET_SCRIPT"
chmod +x "$TARGET_SCRIPT"

echo -e "\e[34m🚀 Running Speeder Pad installer\e[0m"
bash "$TARGET_SCRIPT"

mkdir -p "$STATE_DIR"
date -u +"%Y-%m-%dT%H:%M:%SZ" > "$STATE_FILE"

echo -e "\e[32m✅ Speeder Pad installer completed\e[0m"
