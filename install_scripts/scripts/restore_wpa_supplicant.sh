#!/usr/bin/env bash
set -e

# =============================================================================
# Restore wpa_supplicant.conf (WiFi credentials) for dhcpcd-based systems.
# Run this after reboot if WiFi is not working.
# =============================================================================

STATE_DIR="/var/lib/linuxsetups"
BACKUP_FILE="$STATE_DIR/wpa_supplicant.conf.backup"
DST="/etc/wpa_supplicant/wpa_supplicant.conf"

if [ "$(id -u)" -ne 0 ]; then
    echo -e "\e[31m❌ Run as root\e[0m"
    exit 1
fi

if [ -f "$BACKUP_FILE" ]; then
    cp "$BACKUP_FILE" "$DST"
    chmod 600 "$DST"
    echo -e "\e[32m✅ Restored WiFi config from $BACKUP_FILE\e[0m"
    systemctl restart dhcpcd || true
else
    echo -e "\e[31m❌ No backup found at $BACKUP_FILE\e[0m"
fi
