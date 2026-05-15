#!/usr/bin/env bash
set -e

# =============================================================================
# Sync NetworkManager WiFi profiles with persistent backup.
# Runs on every boot (registered by preserve_nm_settings.sh).
# Also called at the start of Phase 2 re-run.
#
# Logic (two-way merge — never overwrites existing profiles):
#   1. Backup → NM : copy any profiles in backup that are missing from NM
#   2. NM → Backup : copy any profiles in NM that are missing from backup
# The backup accumulates every WiFi profile ever seen, and any that get
# wiped (e.g. by sp_installer1) are silently restored on the next boot.
# =============================================================================

print_status()  { printf "\033[34m🔧 %s\033[0m\n" "$1"; }
print_success() { printf "\033[32m✅ %s\033[0m\n" "$1"; }
print_warning() { printf "\033[33m⚠️  %s\033[0m\n" "$1"; }
print_header()  { printf "\n\033[36m=== %s ===\033[0m\n" "$1"; }

STATE_DIR="/var/lib/linuxsetups"
NM_BACKUP_DIR="${STATE_DIR}/nm_connections_backup"
NM_CONNECTIONS="/etc/NetworkManager/system-connections"

if [ "$(id -u)" -ne 0 ]; then
    printf "\033[31m❌ This script must run with sudo/root privileges.\033[0m\n"
    exit 1
fi

print_header "Sync NetworkManager WiFi Profiles"

mkdir -p "$NM_BACKUP_DIR"
mkdir -p "$NM_CONNECTIONS"

changes=0

# --- Step 1: Backup → NM (restore missing profiles) ---
if [ -n "$(ls -A "$NM_BACKUP_DIR" 2>/dev/null)" ]; then
    for src in "$NM_BACKUP_DIR"/*; do
        fname=$(basename "$src")
        dst="$NM_CONNECTIONS/$fname"
        if [ ! -f "$dst" ]; then
            cp "$src" "$dst"
            chmod 600 "$dst"
            print_status "Restored missing profile: $fname"
            changes=$((changes + 1))
        fi
    done
fi

# --- Step 2: NM → Backup (accumulate new profiles) ---
if [ -n "$(ls -A "$NM_CONNECTIONS" 2>/dev/null)" ]; then
    for src in "$NM_CONNECTIONS"/*; do
        fname=$(basename "$src")
        dst="$NM_BACKUP_DIR/$fname"
        if [ ! -f "$dst" ]; then
            cp "$src" "$dst"
            chmod 600 "$dst"
            print_status "Added new profile to backup: $fname"
            changes=$((changes + 1))
        fi
    done
fi

if [ "$changes" -eq 0 ]; then
    print_success "NM profiles and backup already in sync — nothing to do."
    exit 0
fi

# Reload NM if profiles were restored
if systemctl is-active --quiet NetworkManager 2>/dev/null; then
    print_status "Reloading NetworkManager connections..."
    nmcli connection reload 2>/dev/null || true
    sleep 3

    # Activate any WiFi connection not currently up
    WIFI_CON=$(nmcli -t -f NAME,TYPE,STATE connection show 2>/dev/null \
        | awk -F: '/802-11-wireless/ && !/activated/{print $1; exit}')
    if [ -n "$WIFI_CON" ]; then
        print_status "Activating connection: $WIFI_CON"
        nmcli connection up "$WIFI_CON" 2>/dev/null && \
            print_success "WiFi connected: $WIFI_CON" || \
            print_warning "Could not activate '$WIFI_CON' — may already be connected."
    fi
else
    systemctl start NetworkManager 2>/dev/null || true
    sleep 5
    print_success "NetworkManager started."
fi
