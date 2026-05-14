#!/usr/bin/env bash
set -e

export DEBIAN_FRONTEND=noninteractive

# --- User detection ---
if [ -n "$SUDO_USER" ]; then
    ACTUAL_USER="$SUDO_USER"
    ACTUAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    ACTUAL_USER=$(whoami)
    ACTUAL_HOME="$HOME"
fi

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
print_warning "OPTIONAL STEP: NetworkManager is not required on all systems."
print_warning "Installing it disables dhcpcd (the default DHCP client)."
print_warning "This can cause network issues such as losing your internet connection"
print_warning "or being unable to reach websites until a reboot or manual reconnection."
printf "\n"
read -rp "Install NetworkManager? This is optional and might cause connection issues (y/N): " INSTALL_NM
printf "\n"

if [[ "${INSTALL_NM,,}" != "y" ]]; then
    print_warning "Skipping NetworkManager installation."
    exit 0
fi

# Step 1: Install network-manager
if ! dpkg -s network-manager &>/dev/null; then
    show_progress "📦 Installing network-manager" \
        "apt-get install -y -qq network-manager >/dev/null 2>&1"
    print_success "network-manager installed."
else
    print_success "network-manager already installed."
fi

# Step 2: Create polkit config so any user can manage connections
print_status "Configuring NetworkManager polkit policy..."
sudo mkdir -p "$NM_CONF_DIR"
if [ ! -f "$NM_CONF_FILE" ]; then
    printf "[main]\nauth-polkit=false\n" | sudo tee "$NM_CONF_FILE" >/dev/null
    print_success "Created $NM_CONF_FILE"
else
    print_success "$NM_CONF_FILE already exists, skipping."
fi

# Step 3: Disable dhcpcd and switch to NetworkManager
print_status "Disabling dhcpcd service..."
sudo systemctl -q disable dhcpcd 2>/dev/null || true
sudo systemctl -q stop dhcpcd 2>/dev/null || true

print_status "Enabling NetworkManager service..."
sudo systemctl enable NetworkManager
sudo systemctl start NetworkManager
print_success "NetworkManager enabled and started."

# Step 3.5: Auto-migrate existing WiFi credentials from wpa_supplicant
print_header "Migrating existing WiFi configuration"
WPA_CONF=""
for _f in /etc/wpa_supplicant/wpa_supplicant-wlan0.conf \
           /etc/wpa_supplicant/wpa_supplicant.conf; do
    [[ -f "$_f" ]] && WPA_CONF="$_f" && break
done

if [[ -n "$WPA_CONF" ]]; then
    print_status "Found: $WPA_CONF"
    # Give NetworkManager a moment to fully initialise
    sleep 3

    WPA_SSID=$(grep -oP '(?<=ssid=")[^"]+' "$WPA_CONF" | head -1)
    # Quoted PSK = plaintext password; unquoted 64-char hex = raw hash — both accepted by nmcli
    WPA_PSK=$(grep -oP '(?<=psk=")[^"]+' "$WPA_CONF" | head -1)
    [[ -z "$WPA_PSK" ]] && \
        WPA_PSK=$(awk '/^\s*psk=[^"]/{sub(/^\s*psk=[ \t]*/, ""); print; exit}' "$WPA_CONF")

    if [[ -n "$WPA_SSID" ]]; then
        if nmcli -t -f NAME connection show | grep -qF "migrated-wifi"; then
            print_warning "Migrated WiFi connection already exists — skipping."
        elif [[ -n "$WPA_PSK" ]]; then
            print_status "Migrating WiFi connection: '$WPA_SSID'"
            if nmcli connection add \
                    type wifi \
                    con-name "migrated-wifi" \
                    ssid "$WPA_SSID" \
                    wifi-sec.key-mgmt wpa-psk \
                    wifi-sec.psk "$WPA_PSK" \
                    connection.autoconnect yes \
                    connection.autoconnect-priority 10 2>/dev/null; then
                print_success "WiFi '$WPA_SSID' migrated — will auto-connect after reboot."
            else
                print_warning "nmcli migration failed. You may need to reconnect WiFi manually after reboot."
            fi
        else
            print_warning "SSID '$WPA_SSID' found but no PSK — manual reconnect required after reboot."
        fi
    else
        print_warning "Could not parse SSID from $WPA_CONF — manual reconnect required after reboot."
    fi
else
    print_warning "No wpa_supplicant config found — WiFi auto-migration skipped."
    print_warning "If you lose WiFi after reboot, reconnect with:"
    print_warning "  nmcli device wifi connect \"<SSID>\" password \"<PASSWORD>\""
fi

# Step 4: Prompt for WiFi credentials and connect (skip if migration already succeeded)
print_header "Connect to WiFi via NetworkManager"
if nmcli -t -f NAME connection show | grep -qF "migrated-wifi"; then
    print_success "Skipping manual WiFi setup — credentials were migrated from wpa_supplicant."
    CONNECT_WIFI="n"
else
    read -rp "Do you want to connect to a WiFi network now? (y/N): " CONNECT_WIFI
    printf "\n"
fi

if [[ "${CONNECT_WIFI,,}" != "y" ]]; then
    print_warning "Skipping WiFi connection. You can connect manually later with:"
    print_warning "  nmcli device wifi connect \"<SSID>\" password \"<PASSWORD>\""
else
    print_status "Available WiFi networks:"
    nmcli device wifi list 2>/dev/null || print_warning "Could not list WiFi networks."
    printf "\n"

    read -rp "Enter your WiFi SSID (network name): " WIFI_SSID
    read -rsp "Enter your WiFi password: " WIFI_PASSWORD
    printf "\n"
fi

if [[ "${CONNECT_WIFI,,}" == "y" ]]; then
    if [ -n "$WIFI_SSID" ] && [ -n "$WIFI_PASSWORD" ]; then
        print_status "Connecting to '$WIFI_SSID'..."
        if nmcli device wifi connect "$WIFI_SSID" password "$WIFI_PASSWORD" 2>/dev/null; then
            print_success "Connected to '$WIFI_SSID'."
        else
            print_warning "Could not connect to '$WIFI_SSID'. Check SSID and password."
            print_warning "To retry manually: nmcli device wifi connect \"<SSID>\" password \"<PASSWORD>\""
        fi
    else
        print_warning "No SSID or password entered. Skipping WiFi connection."
    fi
fi

unset WIFI_PASSWORD

print_status "Network device status:"
nmcli device status 2>/dev/null || true

print_success "NetworkManager setup complete."
print_warning "A reboot may be required before the next installation step."
