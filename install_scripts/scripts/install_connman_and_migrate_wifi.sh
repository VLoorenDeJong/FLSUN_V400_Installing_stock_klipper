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

print_header "Installing ConnMan"
apt-get update
apt-get install -y connman
systemctl enable connman
systemctl start connman

print_header "Migrating WiFi settings from wpa_supplicant"
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
echo -e "agent on\nscan wifi\nservices\nconnect wifi_$(echo -n $SSID | xxd -ps | tr -d '\n')_managed_psk\n$PSK\nquit" | connmanctl || print_warning "Manual WiFi connection may be required."

print_success "ConnMan installed and WiFi migration attempted. Reboot to apply changes."
