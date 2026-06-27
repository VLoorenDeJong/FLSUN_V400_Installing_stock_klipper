#!/usr/bin/env bash
set -e

# ==========================
# CONFIGURATION (shared)
# ==========================
SERVICE_NAME="wifi-toggle.service"
TIMER_NAME="wifi-toggle.timer"
SCRIPT_NAME="wifi-toggle.sh"

# Where your toggle script lives
INSTALL_SCRIPT_PATH="/usr/local/bin/${SCRIPT_NAME}"

# Where systemd stores services
SYSTEMD_DIR="/etc/systemd/system"

# Timer interval (in minutes)
TIMER_MINUTES=5

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
if [ ! -f "$SCRIPT_NAME" ]; then
    print_error "Cannot find $SCRIPT_NAME in current directory"
    print_warning "Place $SCRIPT_NAME next to this installer script"
    exit 1
fi

# ==========================
# INSTALL MAIN SCRIPT
# ==========================
print_status "Installing WiFi toggle script to /usr/local/bin..."

sudo cp "$SCRIPT_NAME" "$INSTALL_SCRIPT_PATH"
sudo chmod +x "$INSTALL_SCRIPT_PATH"

print_success "Installed: $INSTALL_SCRIPT_PATH"

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
ExecStart=${INSTALL_SCRIPT_PATH}
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

print_success "Installation complete — no prompts, no pauses."
