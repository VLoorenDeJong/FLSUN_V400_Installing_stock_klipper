#!/usr/bin/env bash
set -e

# ==========================
# DETECT REPO ROOT
# ==========================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# ==========================
# CONFIGURATION (shared)
# ==========================
SERVICE_NAME="wifi_toggle.service"
TIMER_NAME="wifi_toggle.timer"
SCRIPT_NAME="wifi_toggle.sh"

# The toggle script lives inside the repo:
TOGGLE_SCRIPT_PATH="$REPO_ROOT/backup_config/timed_wifi_toggle/$SCRIPT_NAME"

# Where systemd stores services
SYSTEMD_DIR="/etc/systemd/system"

# Timer interval (in minutes)
TIMER_MINUTES=1     # No fractions, systemd does not support them. 1 minute is the minimum interval.

# ==========================
# PRINT HELPERS
# ==========================
print_status() {
    printf "\033[34m🔧 %s\033[0m\n" "$1"
}

print_success() {
    printf "\033[32m✅ %s\033[0m\n" "$1"
}

print_error() {
    printf "\033[31m❌ %s\033[0m\n" "$1"
}

print_warning() {
    printf "\033[33m⚠️ %s\033[0m\n" "$1"
}

# ==========================
# VERIFY SCRIPT EXISTS
# ==========================
if [ ! -f "$TOGGLE_SCRIPT_PATH" ]; then
    print_error "Cannot find $SCRIPT_NAME at:"
    echo "   $TOGGLE_SCRIPT_PATH"
    print_warning "Ensure wifi_toggle.sh is inside:"
    echo "   backup_config/timed_wifi_toggle/scripts/"
    exit 1
fi

# ==========================
# INSTALL MAIN SCRIPT
# ==========================
print_status "Installing WiFi toggle script to /usr/local/bin..."

sudo cp "$TOGGLE_SCRIPT_PATH" "/usr/local/bin/$SCRIPT_NAME"
sudo chmod +x "/usr/local/bin/$SCRIPT_NAME"

print_success "Installed: /usr/local/bin/$SCRIPT_NAME"

# ==========================
# CREATE LOG DIRECTORY
# ==========================
print_status "Creating log directory..."

sudo mkdir -p /var/log/timed_wifi_toggle
sudo chown pi:pi /var/log/timed_wifi_toggle
sudo chmod 755 /var/log/timed_wifi_toggle

print_success "Log directory ready: /var/log/timed_wifi_toggle"

# ==========================
# CREATE SERVICE FILE
# ==========================
print_status "Creating systemd service file..."

sudo tee "${SYSTEMD_DIR}/${SERVICE_NAME}" >/dev/null <<EOF
[Unit]
Description=WiFi Toggle Script
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/${SCRIPT_NAME}
User=pi
Group=pi
PermissionsStartOnly=true

[Install]
WantedBy=multi-user.target
EOF

print_success "Service file created: ${SYSTEMD_DIR}/${SERVICE_NAME}"

# ==========================
# CREATE TIMER FILE
# ==========================
print_status "Creating systemd timer file..."

sudo tee "${SYSTEMD_DIR}/${TIMER_NAME}" >/dev/null <<EOF
[Unit]
Description=WiFi Toggle Timer

[Timer]
OnBootSec=60
OnUnitActiveSec=$((TIMER_MINUTES * 60))
Unit=${SERVICE_NAME}

[Install]
WantedBy=timers.target
EOF

print_success "Timer file created: ${SYSTEMD_DIR}/${TIMER_NAME}"

# ==========================
# ENABLE + START TIMER
# ==========================
print_status "Reloading systemd daemon..."
sudo systemctl daemon-reload

print_status "Enabling timer..."
sudo systemctl enable "${TIMER_NAME}"

print_status "Starting timer..."
sudo systemctl start "${TIMER_NAME}"

print_success "WiFi toggle service + timer installed and running!"

# ==========================
# FINAL STATUS
# ==========================
print_status "Checking timer status..."
sudo systemctl status "${TIMER_NAME}" --no-pager || true

print_success "Installation complete. The WiFi toggle service will run every ${TIMER_MINUTES} minutes."
