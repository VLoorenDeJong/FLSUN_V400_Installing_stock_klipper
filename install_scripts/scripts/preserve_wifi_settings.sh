#!/bin/bash
set -e

# =============================================================================
# Preserve WiFi Settings Across Reboots / Distro Upgrades
#
# Problems this fixes:
#   1. Distro upgrade enables "predictable" interface names (wlan0 → wlp2s0),
#      breaking wpa_supplicant config that references wlan0.
#   2. wpa_supplicant / dhcpcd services not enabled for the interface after
#      an upgrade, so WiFi never comes up on next boot.
#
# What it does:
#   - Backs up wpa_supplicant.conf to /etc/wpa_supplicant/backup/
#   - Creates a udev rule that pins the WiFi interface MAC → wlan0
#   - Ensures wpa_supplicant and dhcpcd are enabled at boot
# =============================================================================

print_status()  { printf "\033[34m🔧 %s\033[0m\n" "$1"; }
print_success() { printf "\033[32m✅ %s\033[0m\n" "$1"; }
print_warning() { printf "\033[33m⚠️  %s\033[0m\n" "$1"; }
print_error()   { printf "\033[31m❌ %s\033[0m\n" "$1"; }
print_header()  { printf "\n\033[36m=== %s ===\033[0m\n" "$1"; }

if [ "$(id -u)" -ne 0 ]; then
    print_error "Please run as root (use sudo)."
    exit 1
fi

print_header "Preserve WiFi Settings"

# ---------------------------------------------------------------------------
# 1. Detect current WiFi interface
# ---------------------------------------------------------------------------
WIFI_IFACE=""
if command -v iw &>/dev/null; then
    WIFI_IFACE=$(iw dev 2>/dev/null | awk '/Interface/{print $2; exit}')
fi
# Fallback: look for wlan* in /sys
if [[ -z "$WIFI_IFACE" ]]; then
    WIFI_IFACE=$(ls /sys/class/net/ | grep -E '^wlan' | head -1 || true)
fi
# Last resort default
[[ -z "$WIFI_IFACE" ]] && WIFI_IFACE="wlan0"

print_status "Detected WiFi interface: $WIFI_IFACE"

# ---------------------------------------------------------------------------
# 2. Back up wpa_supplicant config
# ---------------------------------------------------------------------------
BACKUP_DIR="/etc/wpa_supplicant/backup"
mkdir -p "$BACKUP_DIR"

WPA_CONF=""
for _f in "/etc/wpa_supplicant/wpa_supplicant-${WIFI_IFACE}.conf" \
           /etc/wpa_supplicant/wpa_supplicant.conf; do
    [[ -f "$_f" ]] && WPA_CONF="$_f" && break
done

if [[ -n "$WPA_CONF" ]]; then
    BACKUP_FILE="$BACKUP_DIR/$(basename "$WPA_CONF").bak"
    cp "$WPA_CONF" "$BACKUP_FILE"
    print_success "Backed up: $WPA_CONF → $BACKUP_FILE"
else
    print_warning "No wpa_supplicant config found — nothing to back up."
    print_warning "Expected: /etc/wpa_supplicant/wpa_supplicant.conf"
    print_warning "Enter your WiFi credentials via the Speeder Pad UI before running Phase 1."
fi

# ---------------------------------------------------------------------------
# 3. Pin interface name to wlan0 via udev (survives predictable-names change)
# ---------------------------------------------------------------------------
UDEV_RULE="/etc/udev/rules.d/70-wifi-name.rules"

MAC=$(cat "/sys/class/net/$WIFI_IFACE/address" 2>/dev/null || true)
if [[ -n "$MAC" ]]; then
    if [[ -f "$UDEV_RULE" ]]; then
        print_success "udev WiFi name rule already exists ($UDEV_RULE) — skipping."
    else
        printf 'SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="%s", NAME="wlan0"\n' "$MAC" \
            > "$UDEV_RULE"
        print_success "Created udev rule: $WIFI_IFACE (MAC $MAC) → always named wlan0 after reboot."
    fi
else
    print_warning "Could not read MAC address for $WIFI_IFACE — interface name not pinned."
    print_warning "If WiFi breaks after reboot, the interface may have been renamed."
    print_warning "Check with: ip link show"
fi

# ---------------------------------------------------------------------------
# 4. Ensure wpa_supplicant is enabled at boot
# ---------------------------------------------------------------------------
# Prefer the per-interface service (wpa_supplicant@wlan0) if the config file exists.
WPA_IFACE_CONF="/etc/wpa_supplicant/wpa_supplicant-wlan0.conf"

if [[ ! -f "$WPA_IFACE_CONF" && -n "$WPA_CONF" ]]; then
    # Create the per-interface config symlink/copy so the @ service can find it
    cp "$WPA_CONF" "$WPA_IFACE_CONF"
    print_success "Created $WPA_IFACE_CONF from $WPA_CONF"
fi

if systemctl list-unit-files "wpa_supplicant@wlan0.service" &>/dev/null; then
    systemctl enable "wpa_supplicant@wlan0.service" 2>/dev/null && \
        print_success "Enabled: wpa_supplicant@wlan0.service" || true
elif systemctl list-unit-files "wpa_supplicant.service" &>/dev/null; then
    systemctl enable wpa_supplicant.service 2>/dev/null && \
        print_success "Enabled: wpa_supplicant.service" || true
else
    print_warning "wpa_supplicant service unit not found — may need manual configuration."
fi

# ---------------------------------------------------------------------------
# 5. Ensure dhcpcd is enabled at boot
# ---------------------------------------------------------------------------
if systemctl list-unit-files dhcpcd.service &>/dev/null; then
    systemctl enable dhcpcd.service 2>/dev/null && \
        print_success "Enabled: dhcpcd.service" || \
        print_warning "Could not enable dhcpcd — check manually."
else
    print_warning "dhcpcd.service not found. Is dhcpcd installed?"
    print_warning "Install with: sudo apt-get install -y dhcpcd5"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
print_success "WiFi persistence configured."
print_status  "After reboot, WiFi should auto-connect to your saved network."
print_status  "If it does not, restore the backup:"
print_status  "  sudo cp $BACKUP_DIR/wpa_supplicant.conf.bak /etc/wpa_supplicant/wpa_supplicant.conf"
print_status  "  sudo systemctl restart wpa_supplicant dhcpcd"
echo ""
