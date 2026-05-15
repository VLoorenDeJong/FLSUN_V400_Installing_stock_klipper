#!/usr/bin/env bash
set -e

# =============================================================================
# Preserve NetworkManager WiFi profiles before sp_installer1 runs.
# sp_installer1 installs/reconfigures NetworkManager and reboots the system.
# This script backs up all NM connection profiles so restore_nm_settings.sh
# can put them back on the next Phase 2 re-run, allowing auto-reconnect.
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

print_header "Preserve NetworkManager WiFi Profiles"

if [ ! -d "$NM_CONNECTIONS" ] || [ -z "$(ls -A "$NM_CONNECTIONS" 2>/dev/null)" ]; then
    print_warning "No NetworkManager connection profiles found at $NM_CONNECTIONS"
    print_warning "If WiFi was configured via the Speeder Pad UI, profiles should be here."
    print_warning "Skipping backup — you may need to reconnect manually after sp_installer1 reboots."
    exit 0
fi

mkdir -p "$NM_BACKUP_DIR"
cp -r "$NM_CONNECTIONS/." "$NM_BACKUP_DIR/"
chmod 600 "$NM_BACKUP_DIR"/* 2>/dev/null || true

PROFILE_COUNT=$(ls -1 "$NM_BACKUP_DIR" | wc -l)
print_success "Backed up $PROFILE_COUNT connection profile(s) to $NM_BACKUP_DIR"

# --- Install a systemd oneshot service that restores WiFi on the next boot ---
# sp_installer1 reboots the system. Without this, WiFi won't come back up and
# the user can't SSH in at all. The service fires early in boot, restores NM
# profiles, and then disables itself so it only runs once.
RESTORE_SCRIPT_SRC="$(cd "$(dirname "$0")" && pwd)/restore_nm_settings.sh"
RESTORE_SCRIPT_DST="/usr/local/sbin/restore_nm_settings_once.sh"
SERVICE_FILE="/etc/systemd/system/restore-nm-settings.service"

if [ -f "$RESTORE_SCRIPT_SRC" ]; then
    cp "$RESTORE_SCRIPT_SRC" "$RESTORE_SCRIPT_DST"
    chmod +x "$RESTORE_SCRIPT_DST"

    cat > "$SERVICE_FILE" <<'EOF'
[Unit]
Description=Sync NetworkManager WiFi profiles with persistent backup (runs every boot)
After=network-pre.target
Before=NetworkManager.service
DefaultDependencies=no

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/restore_nm_settings_once.sh
RemainAfterExit=yes

[Install]
WantedBy=sysinit.target
EOF

    systemctl daemon-reload
    systemctl enable restore-nm-settings.service
    print_success "Registered persistent boot service: restore-nm-settings.service"
    print_success "WiFi profiles will be synced with backup on every boot."
else
    print_warning "restore_nm_settings.sh not found next to this script — boot service not created."
    print_warning "After sp_installer1 reboots, you will need to reconnect WiFi manually."
fi

print_warning "sp_installer1.sh will reboot the system when it finishes."
print_warning "WiFi will restore on boot. Reconnect via SSH and re-run Phase 2 to continue."
