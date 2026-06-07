#!/usr/bin/env bash

# --- SAFETY NET: Timed rollback for remote SSH ---
# This will reboot the device in 5 minutes unless you cancel it (kill %1 or pkill -f 'sleep 300 && reboot')
(
    sleep 300 && echo "[SAFETY] No cancel detected, rebooting to restore network..." && reboot
) &
SAFETY_PID=$!
echo "[SAFETY] Rollback timer started (PID $SAFETY_PID). If network is up and stable, run: kill $SAFETY_PID to cancel reboot."
set -e

# --- ABSOLUTELY FIRST: Print WiFi credentials before anything else, no other output above this ---
WPA_CONF="/etc/wpa_supplicant/wpa_supplicant.conf"
SSID=""
PSK=""
if [ -z "$WPA_CONF" ]; then
    echo "=== (CREDENTIALS) WPA_CONF variable is unset or empty; cannot check for WiFi credentials."
    sync
elif [ -f "$WPA_CONF" ]; then
    SSID=$(awk '/network=\{/{i++} i==2 && /ssid=/{gsub(/.*ssid="|"/,"",$0); print $0}' "$WPA_CONF")
    PSK=$(awk '/network=\{/{i++} i==2 && /psk=/{gsub(/.*psk="|"/,"",$0); print $0}' "$WPA_CONF")
    # Obfuscate SSID and PSK for all console output
    obfuscate() {
        local val="$1"
        local len=${#val}
        if [ "$len" -le 2 ]; then
            printf '%s' "$val"
        else
            local first2=${val:0:2}
            printf '%s***' "$first2"
        fi
    }
    obf_ssid=$(obfuscate "$SSID")
    obf_psk=$(obfuscate "$PSK")
    echo "=== (CREDENTIALS) SSID: $obf_ssid"
    echo "=== (CREDENTIALS) PSK: $obf_psk"
    # Export for use in later debug/status output
    export SSID_OBF="$obf_ssid"
    export PSK_OBF="$obf_psk"
    sync
else
    echo "=== (CREDENTIALS) No wpa_supplicant.conf found to import WiFi credentials"
    sync
fi

# =============================================================================
# PRE-FLIGHT DIAGNOSTICS — printed in full BEFORE any service is touched
# If you lose connection, these lines will already be in the log/terminal.
# =============================================================================
echo ""
echo "============================================================"
echo "  PRE-FLIGHT DIAGNOSTICS (snapshot before any changes)"
echo "============================================================"

echo "--- Current IP addresses ---"
ip addr show 2>/dev/null || echo "ip not available"

echo "--- Default routes ---"
ip route show 2>/dev/null || echo "ip route not available"

echo "--- DNS resolv.conf ---"
cat /etc/resolv.conf 2>/dev/null || echo "not found"

echo "--- /etc/network/interfaces ---"
cat /etc/network/interfaces 2>/dev/null || echo "not found"

echo "--- wpa_supplicant status ---"
systemctl status wpa_supplicant --no-pager -l 2>/dev/null || echo "service not found"

echo "--- dhcpcd status ---"
systemctl status dhcpcd --no-pager -l 2>/dev/null || echo "service not found"

echo "--- NetworkManager status ---"
systemctl status NetworkManager --no-pager -l 2>/dev/null || echo "service not found"

echo "--- /etc/NetworkManager/NetworkManager.conf ---"
cat /etc/NetworkManager/NetworkManager.conf 2>/dev/null || echo "not found"

echo "--- /etc/NetworkManager/conf.d/ ---"
ls -la /etc/NetworkManager/conf.d/ 2>/dev/null || echo "not found"
cat /etc/NetworkManager/conf.d/*.conf 2>/dev/null || true

echo "--- NM connection profiles ---"
nmcli connection show 2>/dev/null || echo "nmcli not available yet"

echo "--- NM device status ---"
nmcli device status 2>/dev/null || echo "nmcli not available yet"

echo "--- WiFi scan (current associations) ---"
nmcli dev wifi list 2>/dev/null || echo "nmcli not available yet"

echo "--- iw reg (WiFi country) ---"
iw reg get 2>/dev/null || echo "iw not available"

echo "--- wpa_supplicant.conf (redacted PSK) ---"
if [ -f "/etc/wpa_supplicant/wpa_supplicant.conf" ]; then
    sed 's/psk=.*/psk=***REDACTED***/' /etc/wpa_supplicant/wpa_supplicant.conf
else
    echo "not found"
fi

echo "--- Systemd enabled unit summary (network-related) ---"
systemctl list-unit-files --no-pager | grep -E 'dhcpcd|wpa_supplicant|NetworkManager|connman|network' || true

echo "============================================================"
echo "  END PRE-FLIGHT DIAGNOSTICS"
echo "============================================================"
echo ""
sync

export DEBIAN_FRONTEND=noninteractive

# --- User detection (removed unused variables) ---

# --- Inline utility functions ---
show_progress() {
    local message="$1"
    local command="$2"
    local interval="${3:-3}"
    local timeout="${4:-300}"
    printf "\033[34m%s\033[0m\n" "$message"
    eval "$command" &
    local cmd_pid=$!
    local start_time
    start_time=$(date +%s)
    while kill -0 $cmd_pid 2>/dev/null; do
        printf "."
        sleep "$interval"
        local current_time
        current_time=$(date +%s)
        if (( current_time - start_time > timeout )); then
            printf "\n\033[31m❌ Command timed out after %d seconds\033[0m\n" "$timeout"
            kill -TERM $cmd_pid 2>/dev/null || true
            sleep 2
            kill -KILL $cmd_pid 2>/dev/null || true
            return 1
        fi
    done
    wait $cmd_pid 2>/dev/null
    local exit_code=$?
    printf "\n"
    return $exit_code
}

print_status()  { printf "\033[34m🔧 %s\033[0m\n" "$1"; }
print_success() { printf "\033[32m✅ %s\033[0m\n" "$1"; }
print_warning() { printf "\033[33m⚠️  %s\033[0m\n" "$1"; }
print_error()   { printf "\033[31m❌ %s\033[0m\n" "$1"; }
print_header()  { printf "\n\033[36m=== %s ===\033[0m\n" "$1"; }

# --- Variables ---
readonly NM_CONF_DIR="/etc/NetworkManager/conf.d"
readonly NM_CONF_FILE="${NM_CONF_DIR}/any-user.conf"

# --- Main ---

print_header "Install and Configure NetworkManager"

# --- Ensure NetworkManager and nmcli are installed ---
if ! command -v nmcli >/dev/null 2>&1; then
    print_status "NetworkManager/nmcli not found. Installing..."
    if command -v apt-get >/dev/null 2>&1; then
        show_progress "Installing NetworkManager..." "apt-get update && apt-get install -y -o Dpkg::Options::=\"--force-confold\" network-manager"
    else
        print_error "apt-get not found. Please install NetworkManager manually."
        exit 1
    fi
    if ! command -v nmcli >/dev/null 2>&1; then
        print_error "NetworkManager installation failed or nmcli still not found. Aborting."
        exit 1
    fi
    print_success "NetworkManager installed."
else
    print_success "NetworkManager/nmcli already installed."
fi


# --- Mitigations for connection issues ---
print_header "Mitigating NetworkManager connection issues"

# 1. Disable and stop wpa_supplicant and dhcpcd so they do NOT restart after reboot

print_status "Disabling and stopping dhcpcd and wpa_supplicant (prevents conflicts after reboot)"
if systemctl list-unit-files | grep -q '^wpa_supplicant\.service'; then
    systemctl -q disable wpa_supplicant 2>/dev/null || true
    systemctl stop wpa_supplicant 2>/dev/null || true
    print_success "wpa_supplicant disabled and stopped"
else
    print_warning "wpa_supplicant.service does not exist. Skipping."
fi
if systemctl list-unit-files | grep -q '^dhcpcd\.service'; then
    systemctl -q disable dhcpcd 2>/dev/null || true
    systemctl stop dhcpcd 2>/dev/null || true
    print_success "dhcpcd disabled and stopped"
else
    print_status "dhcpcd.service does not exist. Skipping."
fi
# --- Extra: kill any manually started wpa_supplicant processes (except those started by NetworkManager) ---
# shellcheck disable=SC2009
WPA_PIDS=$(pgrep -f wpa_supplicant | while read -r pid; do
    # Check if the process was started by NetworkManager
    if ! ps -p "$pid" -o cmd= | grep -q NetworkManager; then
        echo "$pid"
    fi
done)
if [ -n "$WPA_PIDS" ]; then
    print_warning "Killing manually started wpa_supplicant processes: $WPA_PIDS (this may drop WiFi if you are connected via wpa_supplicant directly)"
    for pid in $WPA_PIDS; do
        kill "$pid" || true
    done
    sleep 2
    print_success "Killed all non-NetworkManager wpa_supplicant processes."
else
    print_status "No manual wpa_supplicant processes found."
fi
print_success "wpa_supplicant stopped and manual processes killed."

# 2. Comment out legacy wlan0/eth0 config in /etc/network/interfaces
IFUPDOWN_CONF="/etc/network/interfaces"
if [ -f "$IFUPDOWN_CONF" ]; then
    print_status "Checking for legacy wlan0/eth0 config in $IFUPDOWN_CONF..."
    if grep -Eq '^(iface|auto) +(wlan0|eth0)' "$IFUPDOWN_CONF"; then
        print_warning "Legacy config for wlan0/eth0 found in $IFUPDOWN_CONF. Commenting out..."
        sed -i.bak '/^iface \(wlan0\|eth0\)/ s/^/#/; /^auto \(wlan0\|eth0\)/ s/^/#/' "$IFUPDOWN_CONF"
        print_success "Commented out legacy wlan0/eth0 config in $IFUPDOWN_CONF (backup at $IFUPDOWN_CONF.bak)"
    else
        print_status "No legacy wlan0/eth0 config found in $IFUPDOWN_CONF."
    fi
else
    print_status "$IFUPDOWN_CONF does not exist."
fi

# 2. Extract WiFi credentials for NetworkManager import
WPA_CONF="/etc/wpa_supplicant/wpa_supplicant.conf"
SSID=""
PSK=""
if [ -f "$WPA_CONF" ]; then
    SSID=$(awk '/network=\{/{i++} i==2 && /ssid=/{gsub(/.*ssid="|"/,"",$0); print $0}' "$WPA_CONF")
    PSK=$(awk '/network=\{/{i++} i==2 && /psk=/{gsub(/.*psk="|"/,"",$0); print $0}' "$WPA_CONF")
    print_status "(PRE-CONFIG) Extracted SSID for second network: $SSID_OBF"
    print_status "(PRE-CONFIG) Extracted PSK for second network: $PSK_OBF"
else
    print_warning "No wpa_supplicant.conf found to import WiFi credentials"
fi

# 3. Import existing wpa_supplicant WiFi credentials into NetworkManager
if [ -f "$WPA_CONF" ]; then
    print_status "Importing WiFi credentials from wpa_supplicant.conf into NetworkManager"
    if command -v nmcli >/dev/null 2>&1; then
        # Start tailing NetworkManager logs in background for debugging
        print_status "Tailing NetworkManager logs in background (see /tmp/nm-tail.log)..."
        journalctl -u NetworkManager -f > /tmp/nm-tail.log 2>&1 &
        TAIL_PID=$!
        # Ensure NetworkManager is enabled at boot and running
        print_status "Enabling NetworkManager at boot..."
        systemctl enable NetworkManager
        if ! systemctl is-active --quiet NetworkManager; then
            print_status "Starting NetworkManager service..."
            systemctl -q --no-block start NetworkManager
            sleep 3
        fi
        if nmcli connection import type wifi file "$WPA_CONF"; then
            print_success "WiFi credentials imported into NetworkManager"
        else
            print_warning "Could not import WiFi credentials (may already exist or not needed)"
        fi
        # Stop tailing logs after main NM actions
        if [ -n "$TAIL_PID" ]; then
            kill $TAIL_PID >/dev/null 2>&1
        fi
        # Save and print last 100 lines of NM log
        print_header "==== NetworkManager log tail (last 100 lines) ===="
        tail -100 /tmp/nm-tail.log
        # Preserve the log for later review
        LOG_DEST="/var/log/nm-tail.log"
        if cp /tmp/nm-tail.log "$LOG_DEST" 2>/dev/null; then
            print_status "Full NetworkManager log preserved at $LOG_DEST"
        else
            LOG_DEST="$HOME/nm-tail.log"
            cp /tmp/nm-tail.log "$LOG_DEST"
            print_warning "Could not write to /var/log, log saved to $LOG_DEST instead."
        fi
        # --- Add only the second network block (MyNetwork/MyPassword) to NetworkManager ---
        print_status "Adding WiFi network ($SSID_OBF) to NetworkManager"
        if [ -n "$SSID" ] && [ -n "$PSK" ]; then
            if nmcli dev wifi connect "$SSID" password "$PSK" ifname wlan0; then
                print_success "WiFi network ($SSID_OBF) connected via NetworkManager"
                # Ensure the connection profile persists and auto-connects after reboot
                CONN_NAME=$(nmcli -t -f NAME,TYPE connection show --active | awk -F: '$2=="802-11-wireless"{print $1; exit}')
                if [ -n "$CONN_NAME" ]; then
                    nmcli connection modify "$CONN_NAME" connection.autoconnect yes
                    print_success "Auto-connect enabled for profile: $CONN_NAME"
                else
                    print_warning "Could not find active WiFi profile to set autoconnect — checking all profiles"
                    CONN_NAME=$(nmcli -t -f NAME,TYPE connection show | awk -F: '$2=="802-11-wireless"{print $1; exit}')
                    [ -n "$CONN_NAME" ] && nmcli connection modify "$CONN_NAME" connection.autoconnect yes && \
                        print_success "Auto-connect enabled for profile: $CONN_NAME"
                fi
            else
                print_warning "Failed to connect WiFi network ($SSID_OBF) via NetworkManager"
            fi
        else
            print_warning "Could not extract SSID/PSK from wpa_supplicant.conf"
        fi
        # --- Check if nmcli settings match ifupdown (interfaces) settings ---
        IFUPDOWN_CONF="/etc/network/interfaces"
        if [ -f "$IFUPDOWN_CONF" ]; then
            print_status "Comparing NetworkManager and ifupdown (interfaces) network settings..."
            # List interfaces managed by ifupdown
            IFUPDOWN_IFS=$(awk '/iface /{print $2}' "$IFUPDOWN_CONF" | sort | uniq)
            NM_IFS=$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="ethernet"||$2=="wifi"{print $1}' | sort | uniq)
            for iface in $IFUPDOWN_IFS; do
                if echo "$NM_IFS" | grep -qw "$iface"; then
                    print_success "Interface $iface is present in both NetworkManager and ifupdown."
                else
                    print_warning "Interface $iface is in ifupdown but not managed by NetworkManager."
                fi
            done
            for iface in $NM_IFS; do
                if echo "$IFUPDOWN_IFS" | grep -qw "$iface"; then
                    : # already reported above
                else
                    print_warning "Interface $iface is managed by NetworkManager but not present in ifupdown."
                fi
            done
        fi
    else
        print_error "nmcli not found after supposed install. Skipping WiFi import."
    fi
fi


# 3. Ensure polkit and NM config for user management
print_status "Ensuring polkit and NetworkManager config for user management"
mkdir -p "$NM_CONF_DIR"
echo -e "[main]\nauth-polkit=false" > "$NM_CONF_FILE"
chmod 644 "$NM_CONF_FILE"

# 4. Set NetworkManager to manage all interfaces
NM_MAIN_CONF="/etc/NetworkManager/NetworkManager.conf"
if [ -f "$NM_MAIN_CONF" ]; then
    if grep -q '^managed=' "$NM_MAIN_CONF"; then
        sed -i 's/^managed=.*/managed=true/' "$NM_MAIN_CONF"
    else
        echo -e '\n[ifupdown]\nmanaged=true' >> "$NM_MAIN_CONF"
    fi
    print_success "NetworkManager set to manage all interfaces"
else
    print_warning "$NM_MAIN_CONF does not exist. NetworkManager may not be fully installed or started yet."
fi

# --- Cancel safety reboot if network is up ---
if nmcli -t -f STATE general | grep -q 'connected'; then
    echo "[SAFETY] Network is up. Cancelling rollback reboot timer."
    kill $SAFETY_PID
else
    echo "[SAFETY] Network not detected as up. Rollback reboot will occur unless cancelled manually."
fi

print_success "NetworkManager mitigations complete. Reboot recommended."
