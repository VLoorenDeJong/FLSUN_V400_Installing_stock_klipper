
#!/usr/bin/env bash
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
    echo "=== (CREDENTIALS) SSID: $SSID"
    echo "=== (CREDENTIALS) PSK: $PSK"
    sync
else
    echo "=== (CREDENTIALS) No wpa_supplicant.conf found to import WiFi credentials"
    sync
fi

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

# 1. Mask and stop wpa_supplicant service (if it exists)
print_status "Masking and stopping wpa_supplicant service (prevents conflicts)"
if systemctl list-unit-files | grep -q '^wpa_supplicant\.service'; then
    systemctl mask wpa_supplicant || true
    systemctl stop wpa_supplicant || true
else
    print_warning "wpa_supplicant.service does not exist. Skipping."
fi
print_success "wpa_supplicant masked/stopped"

# 2. Extract and print WiFi credentials before any NetworkManager actions
WPA_CONF="/etc/wpa_supplicant/wpa_supplicant.conf"
SSID=""
PSK=""
if [ -f "$WPA_CONF" ]; then
    SSID=$(awk '/network=\{/{i++} i==2 && /ssid=/{gsub(/.*ssid="|"/,"",$0); print $0}' "$WPA_CONF")
    PSK=$(awk '/network=\{/{i++} i==2 && /psk=/{gsub(/.*psk="|"/,"",$0); print $0}' "$WPA_CONF")
    print_status "(PRE-CONFIG) Extracted SSID for second network: $SSID"
    print_status "(PRE-CONFIG) Extracted PSK for second network: $PSK"
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
        # Ensure NetworkManager is running
        if ! systemctl is-active --quiet NetworkManager; then
            print_status "Starting NetworkManager service..."
            systemctl start NetworkManager
            sleep 2
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
        # --- Add only the second network block (MyNetwork/MyPassword) to NetworkManager ---
        print_status "Adding WiFi network ($SSID) to NetworkManager"
        if [ -n "$SSID" ] && [ -n "$PSK" ]; then
            if nmcli dev wifi connect "$SSID" password "$PSK" ifname wlan0; then
                print_success "WiFi network ($SSID) added to NetworkManager"
            else
                print_warning "Failed to add WiFi network ($SSID) to NetworkManager"
            fi
        else
            print_warning "Could not extract SSID/PSK for 'MyNetwork' from wpa_supplicant.conf"
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

print_success "NetworkManager mitigations complete. Reboot recommended."
