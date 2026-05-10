#!/usr/bin/env bash
set -e

export DEBIAN_FRONTEND=noninteractive

# --- Inline utility functions ---
show_progress() {
    local message="$1"
    local command="$2"
    local interval="${3:-5}"
    local timeout="${4:-600}"
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
readonly INSTALLER_URL="https://raw.githubusercontent.com/Guilouz/Klipper-Flsun-Speeder-Pad/main/Downloads/sp_installer2.sh"
readonly TARGET_DIR="/home/pi"
readonly TARGET_SCRIPT="${TARGET_DIR}/sp_installer2.sh"
readonly STATE_DIR="/var/lib/linuxsetups"
readonly STATE_FILE="${STATE_DIR}/flsun_speeder_pad_installer2.done"
FORCE_RUN="${FORCE_RUN_FL_SP_INSTALLER2:-0}"

# --- Validation ---
if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must run with sudo/root privileges."
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    show_progress "📦 Installing curl" "apt-get install -y -qq curl >/dev/null 2>&1"
fi

if [ ! -d "$TARGET_DIR" ]; then
    print_error "Target directory does not exist: $TARGET_DIR"
    print_warning "This script expects the Speeder Pad / pi user environment."
    exit 1
fi

if [ -f "$STATE_FILE" ] && [ "$FORCE_RUN" != "1" ]; then
    print_warning "Speeder Pad installer 2 already executed. Skipping."
    print_warning "To force rerun: FORCE_RUN_FL_SP_INSTALLER2=1 sudo bash $0"
    exit 0
fi

# --- Main ---
print_header "Flsun Speeder Pad — sp_installer2"

show_progress "📥 Downloading sp_installer2.sh" \
    "curl -fsSL '$INSTALLER_URL' -o '$TARGET_SCRIPT'"
chmod +x "$TARGET_SCRIPT"
print_success "Downloaded to $TARGET_SCRIPT"

print_status "Running sp_installer2.sh..."
bash "$TARGET_SCRIPT"

mkdir -p "$STATE_DIR"
date -u +"%Y-%m-%dT%H:%M:%SZ" > "$STATE_FILE"

print_success "sp_installer2 completed successfully."
