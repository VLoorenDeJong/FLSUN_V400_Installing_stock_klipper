#!/usr/bin/env bash
set -e

export DEBIAN_FRONTEND=noninteractive

# Detect actual user
if [ -n "$SUDO_USER" ]; then
    ACTUAL_USER="$SUDO_USER"
    ACTUAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    ACTUAL_USER=$(whoami)
    ACTUAL_HOME="$HOME"
fi

ACTUAL_GROUP=$(id -gn "$ACTUAL_USER")

# Detect script directory and repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Messaging helpers
print_status()   { printf "\033[34m🔧 %s\033[0m\n" "$1"; }
print_success()  { printf "\033[32m✅ %s\033[0m\n" "$1"; }
print_warning()  { printf "\033[33m⚠️ %s\033[0m\n" "$1"; }
print_error()    { printf "\033[31m❌ %s\033[0m\n" "$1"; }

show_progress() {
    local message="$1"
    local command="$2"
    local interval="${3:-2}"
    local timeout="${4:-120}"

    printf "\033[34m%s\033[0m\n" "$message"

    eval "$command" &
    local cmd_pid=$!
    local start_time=$(date +%s)

    while kill -0 $cmd_pid 2>/dev/null; do
        printf "."
        sleep $interval

        local now=$(date +%s)
        if (( now - start_time > timeout )); then
            printf "\n\033[31m❌ Timeout after ${timeout}s\033[0m\n"
            kill -TERM $cmd_pid 2>/dev/null || true
            sleep 1
            kill -KILL $cmd_pid 2>/dev/null || true
            return 1
        fi
    done

    wait $cmd_pid
    printf "\n"
    return $?
}

print_status "Starting webcam auto‑configuration..."

# Detect webcam device
print_status "Detecting webcam device..."
WEBCAM=$(ls /dev/video* 2>/dev/null | head -n 1 || true)

if [[ -z "$WEBCAM" ]]; then
    print_error "No webcam detected (no /dev/video* found)"
    exit 1
fi

print_success "Webcam detected at: $WEBCAM"

# Write Crowsnest config
CROWSNEST_CFG="$ACTUAL_HOME/printer_data/config/crowsnest.conf"

print_status "Writing Crowsnest configuration..."

cat <<EOF > "$CROWSNEST_CFG"
[cam 1]
device: $WEBCAM
resolution: 640x480
fps: 15
quality: 80
auto_brightness: true
EOF

print_success "Crowsnest config written to $CROWSNEST_CFG"

# Apply permissions
print_status "Applying permissions..."
sudo chown "$ACTUAL_USER:$ACTUAL_GROUP" "$CROWSNEST_CFG"
sudo chmod 644 "$CROWSNEST_CFG"
print_success "Permissions applied"

# Restart Crowsnest (non-fatal)
print_status "Restarting Crowsnest service..."
show_progress "🔄 Reloading Crowsnest (partial functionality expected)" \
    "sudo systemctl restart crowsnest.service" || true

print_warning "ℹ️ Crowsnest may appear partially functional until the next reboot"
print_success "🎉 Webcam auto‑configuration completed!"
