#!/bin/bash
set -e

# =============================================================================
# Install ConnMan and migrate WiFi settings from wpa_supplicant (FLSUN original)
# =============================================================================

print_status()  { printf "\033[34m🔧 %s\033[0m\n" "$1"; }
print_success() { printf "\033[32m✅ %s\033[0m\n" "$1"; }
print_warning() { printf "\033[33m⚠️  %s\033[0m\n" "$1"; }
print_header()  { printf "\n\033[36m=== %s ===\033[0m\n" "$1"; }

if [ "$(id -u)" -ne 0 ]; then
    echo -e "\e[31m❌ Please run as root (use sudo).\e[0m"
    exit 1
fi

print_header "Uninstalling NetworkManager (if present)"
if systemctl is-active --quiet NetworkManager; then
    systemctl stop NetworkManager || true
fi
if dpkg -l | grep -q network-manager; then
    apt-get remove -y network-manager || true
    apt-get purge -y network-manager || true
fi

print_warning "\n=== NOTICE: You will lose connection soon! ==="
print_warning "After this script finishes, the system will reboot."
print_warning "In 1-2 minuites reconnect with the speederpad and start phas2"
sleep 5

print_header "Installing ConnMan"
apt-get update
apt-get install -y connman
systemctl enable connman
systemctl start connman

print_header "Migrating WiFi settings from wpa_supplicant"
print_warning "\n=== NOTICE: Network Disruption Expected ==="
print_warning "This step will switch your system to ConnMan and restart network services."
print_warning "Your SSH or remote connection will be lost."
print_warning "After this script finishes, the system will reboot."
print_warning "You can reconnect via SSH or terminal after the reboot completes."
sleep 5
WPA_CONF="/etc/wpa_supplicant/wpa_supplicant.conf"
if [ ! -f "$WPA_CONF" ]; then
    print_warning "No wpa_supplicant.conf found. Skipping WiFi migration."
    exit 0
fi

SSID=$(awk -F'"' '/ssid=/{print $2; exit}' "$WPA_CONF")
PSK=$(awk -F'"' '/psk=/{print $2; exit}' "$WPA_CONF")

if [ -z "$SSID" ] || [ -z "$PSK" ]; then
    print_warning "Could not extract SSID or PSK from wpa_supplicant.conf."
    exit 0
fi


print_status "Configuring ConnMan WiFi service for SSID: $SSID"
# Remove any existing ConnMan WiFi configs
db_dir="/var/lib/connman"
rm -rf "$db_dir/wifi_*"

# Enable WiFi
type connmanctl >/dev/null 2>&1 && connmanctl enable wifi

# Configure WiFi using connmanctl
CONNMAN_LOG="/tmp/connman_wifi_connect.log"
echo -e "agent on\nscan wifi\nservices\nconnect wifi_$(echo -n "$SSID" | xxd -ps | tr -d '\n')_managed_psk\n$PSK\nquit" | connmanctl > "$CONNMAN_LOG" 2>&1 || print_warning "Manual WiFi connection may be required."

# Check if ConnMan connected successfully
sleep 5
if connmanctl services | grep -q "wifi_.*_managed_psk.*online"; then
    print_success "ConnMan WiFi connection successful."
    print_success "ConnMan installed and WiFi migration completed. Reboot to apply changes."
else
    print_warning "ConnMan WiFi connection failed. Attempting to restore original wpa_supplicant.conf and dhcpcd."
    STATE_DIR="/var/lib/linuxsetups"
    BACKUP_FILE="$STATE_DIR/wpa_supplicant.conf.backup"
    WPA_CONF="/etc/wpa_supplicant/wpa_supplicant.conf"
    if [ -f "$BACKUP_FILE" ]; then
        cp "$BACKUP_FILE" "$WPA_CONF"
        chmod 600 "$WPA_CONF"
        print_success "Restored original wpa_supplicant.conf from backup."
        systemctl restart dhcpcd || true
        print_status "Restarted dhcpcd."
        print_warning "Please check if WiFi is restored. If not, manual intervention may be required."
    else
        print_error "No backup wpa_supplicant.conf found at $BACKUP_FILE. Cannot restore."
    fi
fi

print_header "\n=== Next Steps ==="
print_success "If you see a 'lost connection' message, this is expected."
print_success "Wait for the system to reboot, then reconnect."
print_success "If you can connect after reboot, ConnMan WiFi migration was successful."
print_warning "If you cannot connect, fallback restoration was attempted. Manual recovery may be needed."
