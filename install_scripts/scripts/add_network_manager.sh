#!/usr/bin/env bash

if [ "$(id -u)" -ne 0 ]; then
    echo -e "\e[31m❌ This script must run as root. Use: sudo bash $0\e[0m"
    exit 1
fi

# --- SAFETY NET: Timed rollback for remote SSH ---
# This will reboot the device in 5 minutes unless you cancel it (kill %1 or pkill -f 'sleep 300 && reboot')
(
    sleep 300
    echo "[SAFETY] No cancel detected, rebooting to restore network..."
    if [ "$(id -u)" -eq 0 ]; then
        systemctl --no-wall reboot 2>/dev/null || reboot
    else
        echo "[SAFETY] Not running as root; skipping automatic reboot."
    fi
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

# Inline helpers (print_* defined later; these carry us through pre-flight)
_hdr()  { printf "\n\033[36m  ┌─ %s\033[0m\n" "$1"; }
_val()  { printf "\033[90m  │\033[0m  %s\n" "$1"; }
_none() { printf "\033[90m  │  (none / not found)\033[0m\n"; }

printf "\n\033[36m╔══════════════════════════════════════════════════════╗\033[0m\n"
printf   "\033[36m║   PRE-FLIGHT DIAGNOSTICS  (before any changes)      ║\033[0m\n"
printf   "\033[36m╚══════════════════════════════════════════════════════╝\033[0m\n"

_hdr "IP addresses"
ip addr show 2>/dev/null | grep -E '^\s*(inet|inet6|[0-9]+:)' | while IFS= read -r line; do _val "$line"; done || _none

_hdr "Default routes"
ip route show 2>/dev/null | while IFS= read -r line; do _val "$line"; done || _none

_hdr "DNS  (/etc/resolv.conf)"
grep -v '^\s*#' /etc/resolv.conf 2>/dev/null | grep -v '^\s*$' | while IFS= read -r line; do _val "$line"; done || _none

_hdr "/etc/network/interfaces"
grep -v '^\s*#' /etc/network/interfaces 2>/dev/null | grep -v '^\s*$' | while IFS= read -r line; do _val "$line"; done || _none

_hdr "wpa_supplicant.conf  (PSK redacted)"
if [ -f "/etc/wpa_supplicant/wpa_supplicant.conf" ]; then
    sed 's/psk=.*/psk=***REDACTED***/' /etc/wpa_supplicant/wpa_supplicant.conf \
        | grep -v '^\s*#' | grep -v '^\s*$' | while IFS= read -r line; do _val "$line"; done
else
    _none
fi

_hdr "Service states  (network-related)"
for svc in wpa_supplicant dhcpcd NetworkManager systemd-networkd connman; do
    if systemctl list-unit-files --no-pager 2>/dev/null | grep -q "^${svc}\.service"; then
        state=$(systemctl is-active "$svc" 2>/dev/null || echo "inactive")
        enabled=$(systemctl is-enabled "$svc" 2>/dev/null || echo "disabled")
        _val "$(printf '%-32s  active=%-10s  enabled=%s' "$svc" "$state" "$enabled")"
    fi
done

_hdr "NM connection profiles"
nmcli -t -f NAME,TYPE,STATE connection show 2>/dev/null \
    | while IFS=: read -r name type state; do _val "$(printf '%-30s  %-25s  %s' "$name" "$type" "$state")"; done \
    || _none

_hdr "NM device status"
nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device status 2>/dev/null \
    | while IFS=: read -r dev type state conn; do _val "$(printf '%-12s  %-12s  %-15s  %s' "$dev" "$type" "$state" "$conn")"; done \
    || _none

if [[ "${FLSUN_DEBUG:-0}" -eq 1 ]]; then
    _hdr "NM conf.d"
    ls /etc/NetworkManager/conf.d/ 2>/dev/null | while IFS= read -r f; do _val "$f"; done || _none
    cat /etc/NetworkManager/conf.d/*.conf 2>/dev/null | while IFS= read -r line; do _val "$line"; done || true

    _hdr "iw reg  (WiFi country)"
    iw reg get 2>/dev/null | while IFS= read -r line; do _val "$line"; done || _none
fi

printf "\n\033[36m══════════════════════════════════════════════════════\033[0m\n\n"
sync

export DEBIAN_FRONTEND=noninteractive

# --- User detection (removed unused variables) ---

# --- Inline utility functions ---
show_progress() {
    local message="$1"
    local command="$2"
    local interval="${3:-3}"
    local timeout="${4:-300}"
    local log_file="/tmp/flsun-progress-$(date +%s)-$$.log"
    printf "\033[34m%s\033[0m\n" "$message"

    if [[ "${FLSUN_DEBUG:-0}" -eq 1 ]]; then
        eval "$command" &
    else
        # Keep normal mode concise; preserve full command output in a temp log.
        eval "$command" >"$log_file" 2>&1 &
    fi

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

    if [[ $exit_code -ne 0 && "${FLSUN_DEBUG:-0}" -ne 1 ]]; then
        print_warning "Command failed. Showing last 40 log lines: $log_file"
        tail -40 "$log_file" 2>/dev/null || true
    fi

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

# 1. Disable competing network managers so they do NOT restart after reboot.
#    This system uses systemd-networkd (not dhcpcd) — it MUST be disabled.
#    wpa_supplicant runs in D-Bus mode (-u -s); NM reuses it, so only STOP it.

print_status "Disabling systemd-networkd (actual network manager on this system)"
if systemctl list-unit-files | grep -q '^systemd-networkd\.service'; then
    systemctl -q disable systemd-networkd 2>/dev/null || true
    systemctl stop systemd-networkd 2>/dev/null || true
    print_success "systemd-networkd disabled and stopped"
else
    print_status "systemd-networkd.service does not exist. Skipping."
fi

print_status "Disabling systemd-networkd-wait-online (depends on systemd-networkd)"
if systemctl list-unit-files | grep -q '^systemd-networkd-wait-online\.service'; then
    systemctl -q disable systemd-networkd-wait-online 2>/dev/null || true
    systemctl stop systemd-networkd-wait-online 2>/dev/null || true
    print_success "systemd-networkd-wait-online disabled and stopped"
fi

print_status "Disabling networkd-dispatcher (companion to systemd-networkd, can re-activate it)"
if systemctl list-unit-files | grep -q '^networkd-dispatcher\.service'; then
    systemctl -q disable networkd-dispatcher 2>/dev/null || true
    systemctl stop networkd-dispatcher 2>/dev/null || true
    print_success "networkd-dispatcher disabled and stopped"
else
    print_status "networkd-dispatcher.service not found — skipping."
fi

print_status "Disabling systemd-networkd.socket (can re-activate systemd-networkd)"
if systemctl list-unit-files | grep -q '^systemd-networkd\.socket'; then
    systemctl -q disable systemd-networkd.socket 2>/dev/null || true
    systemctl stop systemd-networkd.socket 2>/dev/null || true
    print_success "systemd-networkd.socket disabled and stopped"
fi

print_status "Stopping wpa_supplicant (NM will reuse it via D-Bus — NOT disabling)"
# wpa_supplicant runs with -u -s (D-Bus mode); NetworkManager manages it after this point.
# Disabling would prevent NM from using it for WiFi, so we only stop the standalone service.
if systemctl list-unit-files | grep -q '^wpa_supplicant\.service'; then
    systemctl stop wpa_supplicant 2>/dev/null || true
    print_success "wpa_supplicant stopped (left enabled for NM D-Bus reuse)"
else
    print_warning "wpa_supplicant.service does not exist. Skipping."
fi

print_status "Disabling dhcpcd (if present)"
if systemctl list-unit-files | grep -q '^dhcpcd\.service'; then
    systemctl -q disable dhcpcd 2>/dev/null || true
    systemctl stop dhcpcd 2>/dev/null || true
    print_success "dhcpcd disabled and stopped"
else
    print_status "dhcpcd.service not found — skipping (expected on this system)."
fi
# Kill any standalone wpa_supplicant processes that are NOT the D-Bus instance NM will reuse.
# The D-Bus instance (started with -u) will be restarted by NM; interface-bound ones conflict.
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
        # Start tailing NetworkManager logs in background (debug mode only)
        TAIL_PID=""
        if [[ "${FLSUN_DEBUG:-0}" -eq 1 ]]; then
            print_status "Tailing NetworkManager logs in background (see /tmp/nm-tail.log)..."
            journalctl -u NetworkManager -f > /tmp/nm-tail.log 2>&1 &
            TAIL_PID=$!
        fi
        # Ensure NetworkManager is enabled at boot and running
        print_status "Enabling NetworkManager at boot..."
        systemctl enable NetworkManager
        if ! systemctl is-active --quiet NetworkManager; then
            print_status "Starting NetworkManager service..."
            systemctl -q --no-block start NetworkManager
            sleep 3
        fi
        # Give NM a moment to settle before making profile changes
        sleep 2
        # Stop tailing logs and print if in debug mode
        if [[ "${FLSUN_DEBUG:-0}" -eq 1 ]] && [ -n "$TAIL_PID" ]; then
            kill $TAIL_PID >/dev/null 2>&1
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
        fi
        # --- Delete all stale NM WiFi profiles before adding a clean one ---
        print_status "Removing any existing NM WiFi profiles (avoids stale/duplicate profiles)"
        nmcli -t -f NAME,TYPE connection show | awk -F: '$2=="802-11-wireless"{print $1}' | while read -r old_profile; do
            nmcli connection delete "$old_profile" && print_success "Deleted stale profile: $old_profile" || true
        done

        # --- Add a single clean WiFi profile with autoconnect and bring it up ---
        print_status "Adding WiFi network ($SSID_OBF) to NetworkManager"
        if [ -n "$SSID" ] && [ -n "$PSK" ]; then
            # Add the profile explicitly — no import, no duplicate creation
            if nmcli connection add \
                type wifi \
                ifname wlan0 \
                con-name "$SSID" \
                ssid "$SSID" \
                wifi-sec.key-mgmt wpa-psk \
                wifi-sec.psk "$PSK" \
                connection.autoconnect yes \
                connection.autoconnect-priority 10; then
                print_success "WiFi profile '$SSID_OBF' created with autoconnect"
            else
                print_warning "Failed to add WiFi profile for $SSID_OBF"
            fi
            # Bring the connection up explicitly
            print_status "Bringing up WiFi connection ($SSID_OBF)..."
            if nmcli connection up "$SSID"; then
                print_success "WiFi connected: $SSID_OBF"
            else
                print_warning "nmcli connection up failed — NM will retry autoconnect on reboot"
            fi
        else
            print_warning "Could not extract SSID/PSK from wpa_supplicant.conf"
        fi
        # --- Check if nmcli settings match ifupdown (interfaces) settings (debug only) ---
        if [[ "${FLSUN_DEBUG:-0}" -eq 1 ]]; then
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
        fi  # end FLSUN_DEBUG interface comparison
    else
        print_error "nmcli not found after supposed install. Skipping WiFi import."
    fi
fi


# 3. Ensure polkit and NM config for user management
print_status "Ensuring polkit and NetworkManager config for user management"
mkdir -p "$NM_CONF_DIR"
echo -e "[main]\nauth-polkit=false" > "$NM_CONF_FILE"
chmod 644 "$NM_CONF_FILE"

# 4. Configure NM to use systemd-resolved for DNS (resolv.conf is managed by systemd-resolved on this system)
print_status "Configuring NetworkManager to hand DNS to systemd-resolved"
NM_DNS_CONF="${NM_CONF_DIR}/dns.conf"
cat > "$NM_DNS_CONF" <<'EOF'
[main]
dns=systemd-resolved
EOF
chmod 644 "$NM_DNS_CONF"
# Ensure the symlink that systemd-resolved expects is in place
if [ "$(readlink /etc/resolv.conf)" != "/run/systemd/resolve/stub-resolv.conf" ]; then
    ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
    print_success "Linked /etc/resolv.conf -> /run/systemd/resolve/stub-resolv.conf"
else
    print_success "resolv.conf symlink already correct"
fi
systemctl enable systemd-resolved 2>/dev/null || true
systemctl start systemd-resolved 2>/dev/null || true
print_success "NetworkManager DNS handed to systemd-resolved"

# 5. Set NetworkManager to manage all interfaces (ifupdown not present, but set for safety)
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
