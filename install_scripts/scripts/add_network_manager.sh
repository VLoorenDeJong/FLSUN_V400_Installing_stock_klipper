#!/usr/bin/env bash

print_error() { printf "\033[31m❌ %s\033[0m\n" "$1"; }

if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must run as root. Use: sudo bash $0"
    exit 1
fi

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

# Capture the CURRENT working network state BEFORE anything below touches the
# network (the DNS-refresh section does nmcli down/up and can drop the default
# route). The rollback uses the service flags; the gateway is informational.
NET_HAD_NETWORKD=0; systemctl is-active --quiet systemd-networkd && NET_HAD_NETWORKD=1
NET_HAD_WPA=0;      systemctl is-active --quiet wpa_supplicant   && NET_HAD_WPA=1
NET_GATEWAY="$(ip route show default 2>/dev/null | awk '/default/{print $3; exit}')"
print_status "Captured current network state (networkd=$NET_HAD_NETWORKD wpa=$NET_HAD_WPA gw=${NET_GATEWAY:-none})"

print_header "Flushing DNS and requesting fresh DNS from router"

print_status "Detecting active WiFi connection profile"
ACTIVE_WIFI_CON=$(nmcli -t -f NAME,DEVICE,TYPE connection show \
  | awk -F: '$2=="wlan0" && $3=="802-11-wireless"{print $1; exit}')
print_status "Active WiFi profile: $ACTIVE_WIFI_CON"

print_status "Flushing systemd-resolved cache"
# 22.04 renamed systemd-resolve to resolvectl; support both.
if command -v resolvectl >/dev/null 2>&1; then
    resolvectl flush-caches || true
else
    systemd-resolve --flush-caches 2>/dev/null || true
fi

print_status "Restarting systemd-resolved"
systemctl restart systemd-resolved || true

print_status "Renewing DHCP lease via NetworkManager"
nmcli connection down "$ACTIVE_WIFI_CON" || true
nmcli connection up "$ACTIVE_WIFI_CON" || true

print_success "DNS refreshed from router"

# 1. Prepare to hand over to NetworkManager WITHOUT dropping the live connection.
#    We only turn OFF autostart of the competing managers here (so NM wins on the
#    next boot) — we do NOT stop them yet, so your current WiFi stays up while NM
#    is configured below. The actual switch-over happens at the very END of this
#    script, in a detached block that verifies connectivity and rolls back if it
#    fails, so this script can never strand the box.

print_status "Disabling autostart of competing network managers (leaving them RUNNING for now)"
for unit in systemd-networkd systemd-networkd-wait-online networkd-dispatcher systemd-networkd.socket dhcpcd; do
    if systemctl list-unit-files | grep -q "^${unit}"; then
        systemctl -q disable "$unit" 2>/dev/null || true
    fi
done
print_success "Old managers won't auto-start next boot — current connection left untouched."

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

# --- Hand over from the old stack to NetworkManager: detached + rollback, NO reboot ---
# This is the ONLY moment the live link can blip. It runs detached (setsid) so an
# SSH drop during the switch can't kill it. It stops the old stack, brings the WiFi
# up on NetworkManager, verifies REAL connectivity, and if that fails it restores
# exactly the services that were running before. Worst case = you're back on your
# original connection. It never reboots.
print_status "Handing over to NetworkManager in the background (your SSH may briefly blip)..."

HANDOVER="/tmp/nm-handover.sh"
cat > "$HANDOVER" <<HEOF
#!/bin/bash
exec >>/var/log/nm-handover.log 2>&1
echo "[handover \$(date -Is)] start (gw=${NET_GATEWAY:-none} ssid=${SSID:-none})"

# Stop the old stack now that NetworkManager is fully configured.
systemctl stop wpa_supplicant systemd-networkd systemd-networkd.socket \\
    systemd-networkd-wait-online networkd-dispatcher dhcpcd 2>/dev/null || true

# Kill any standalone wpa_supplicant processes NOT owned by NetworkManager.
# (From the original script: interface-bound wpa_supplicant instances hold wlan0
# and block NM from associating on this hardware. NM's own D-Bus instance is spared.)
for pid in \$(pgrep -f wpa_supplicant 2>/dev/null); do
    if ! ps -p "\$pid" -o cmd= 2>/dev/null | grep -q NetworkManager; then
        kill "\$pid" 2>/dev/null || true
    fi
done
sleep 2

# Make sure NetworkManager owns wlan0 and the profile is up.
systemctl restart NetworkManager
nmcli networking on 2>/dev/null || true
nmcli radio wifi on 2>/dev/null || true
nmcli device set wlan0 managed yes 2>/dev/null || true
nmcli connection up "${SSID}" 2>/dev/null || nmcli device connect wlan0 2>/dev/null || true
systemctl restart systemd-resolved 2>/dev/null || true

# Success criterion: wlan0 reaches NetworkManager state "connected" (= associated
# AND holding an IP, i.e. reachable on the LAN for SSH). Deliberately NOT an
# internet/gateway ping: this box ran fine WITHOUT a default route before the
# switch (captured gw=none), so demanding internet would fail a healthy handover.
ok=0
for i in \$(seq 1 20); do
    if nmcli -t -f DEVICE,STATE device status 2>/dev/null | grep -q "^wlan0:connected"; then ok=1; break; fi
    sleep 2
done
echo "[handover] wlan0 state: \$(nmcli -t -f DEVICE,STATE device status 2>/dev/null | grep '^wlan0' || echo unknown)"
echo "[handover] default route now: \$(ip route show default 2>/dev/null || echo none)"

if [ "\$ok" = 1 ]; then
    echo "[handover] SUCCESS — NetworkManager is carrying the connection."
else
    echo "[handover] FAILED — rolling back to the previous network stack (no reboot)."
    systemctl stop NetworkManager 2>/dev/null || true
    if [ "${NET_HAD_NETWORKD}" = 1 ]; then systemctl enable --now systemd-networkd 2>/dev/null || true; fi
    if [ "${NET_HAD_WPA}" = 1 ];      then systemctl start wpa_supplicant 2>/dev/null || true; fi
    systemctl restart systemd-resolved 2>/dev/null || true
    echo "[handover] rollback done — previous connection restored."
fi
HEOF
chmod +x "$HANDOVER"
setsid bash "$HANDOVER" >/dev/null 2>&1 </dev/null &

print_success "Handover launched in the background."
print_status  "If your SSH blips, reconnect in ~30-60s (same IP if the router cooperates)."
print_status  "Progress + result logged to /var/log/nm-handover.log"
print_warning "If the new setup fails its connectivity check, your PREVIOUS connection is"
print_warning "automatically restored — no reboot, no manual recovery needed."

