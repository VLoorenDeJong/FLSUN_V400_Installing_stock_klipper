#!/usr/bin/env bash
set -e

# =============================================================================
# Backup wpa_supplicant.conf (WiFi credentials) for dhcpcd-based systems.
# Run this at the start of Phase 1, before any network changes.
# =============================================================================

STATE_DIR="/var/lib/linuxsetups"
BACKUP_FILE="$STATE_DIR/wpa_supplicant.conf.backup"
SRC="/etc/wpa_supplicant/wpa_supplicant.conf"

if [ "$(id -u)" -ne 0 ]; then
    echo -e "\e[31m❌ Run as root\e[0m"
    exit 1
fi

mkdir -p "$STATE_DIR"
if [ -f "$SRC" ]; then
    cp "$SRC" "$BACKUP_FILE"
    chmod 600 "$BACKUP_FILE"
    echo -e "\e[32m✅ Backed up WiFi config to $BACKUP_FILE\e[0m"
else
    echo -e "\e[33m⚠️  No wpa_supplicant.conf found at $SRC\e[0m"
fi
