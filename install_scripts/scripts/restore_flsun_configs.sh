#!/usr/bin/env bash
set -e

export DEBIAN_FRONTEND=noninteractive

###############################################
#  COLOR + STATUS FUNCTIONS (same as your style)
###############################################
print_status()   { printf "\033[34m🔧 %s\033[0m\n" "$1"; }
print_success()  { printf "\033[32m✅ %s\033[0m\n" "$1"; }
print_warning()  { printf "\033[33m⚠️ %s\033[0m\n" "$1"; }
print_error()    { printf "\033[31m❌ %s\033[0m\n" "$1"; }

show_progress() {
    local message="$1"
    local command="$2"
    local interval="${3:-2}"
    local timeout="${4:-600}"

    print_status "$message"
    eval "$command" &

    local cmd_pid=$!
    local start_time=$(date +%s)

    while kill -0 $cmd_pid 2>/dev/null; do
        printf "."
        sleep $interval

        local now=$(date +%s)
        if (( now - start_time > timeout )); then
            printf "\n"
            print_error "Command timed out after ${timeout}s"
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

###############################################
#  DETECT SCRIPT LOCATION + REPO ROOT
###############################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

###############################################
#  PATHS
###############################################
TMP_ZIP="/tmp/guilouz_config.zip"
TMP_UNPACK="/tmp/guilouz_config"

PRIMARY_URL="https://github.com/Guilouz/Klipper-Flsun-Speeder-Pad/archive/refs/heads/main.zip"

FALLBACK_CONFIG_DIR="$REPO_ROOT/backup_config/Klipper-Flsun-Speeder-Pad-main/Configurations"

TARGET_CONFIG_DIR="/home/pi/printer_data/config"

###############################################
#  DOWNLOAD ZIP (PRIMARY SOURCE)
###############################################
download_primary_zip() {
    print_status "Downloading Guilouz configuration pack..."
    rm -rf "$TMP_ZIP" "$TMP_UNPACK"
    mkdir -p "$TMP_UNPACK"

    if show_progress "Fetching ZIP from GitHub" \
        "curl -L -o \"$TMP_ZIP\" \"$PRIMARY_URL\" >/dev/null 2>&1"; then

        print_success "ZIP downloaded successfully"
        return 0
    else
        print_warning "Failed to download ZIP"
        return 1
    fi
}

###############################################
#  UNPACK ZIP
###############################################
unpack_primary_zip() {
    print_status "Unpacking ZIP..."
    if show_progress "Extracting ZIP" \
        "unzip -o \"$TMP_ZIP\" -d \"$TMP_UNPACK\" >/dev/null 2>&1"; then

        print_success "ZIP unpacked"
        return 0
    else
        print_warning "Failed to unpack ZIP"
        return 1
    fi
}

###############################################
#  LOCATE CONFIGURATIONS FOLDER
###############################################
find_primary_config_folder() {
    local path
    path=$(find "$TMP_UNPACK" -type d -name "Configurations" | head -n 1 || true)

    if [ -n "$path" ]; then
        PRIMARY_CONFIG_DIR="$path"
        return 0
    else
        return 1
    fi
}

###############################################
#  SELECT SOURCE (PRIMARY OR FALLBACK)
###############################################
select_source_folder() {
    print_status "Checking primary source..."

    if download_primary_zip && unpack_primary_zip && find_primary_config_folder; then
        print_success "Using primary source: Guilouz ZIP"
        CONFIG_SOURCE="$PRIMARY_CONFIG_DIR"
    else
        print_warning "Primary source unavailable — using fallback"
        CONFIG_SOURCE="$FALLBACK_CONFIG_DIR"
    fi

    if [ ! -d "$CONFIG_SOURCE" ]; then
        print_error "No valid configuration source found!"
        exit 1
    fi
}

###############################################
#  BUILD MENU OF CONFIG FOLDERS
###############################################
show_menu_and_select() {
    print_status "Scanning configuration sets..."

    mapfile -t CONFIG_FOLDERS < <(find "$CONFIG_SOURCE" -maxdepth 1 -mindepth 1 -type d | sort)

    if [ ${#CONFIG_FOLDERS[@]} -eq 0 ]; then
        print_error "No configuration folders found!"
        exit 1
    fi

    echo "----------------------------------------"
    echo "   Select FLSUN configuration to install"
    echo "----------------------------------------"

    local i=1
    for folder in "${CONFIG_FOLDERS[@]}"; do
        echo "$i) $(basename "$folder")"
        ((i++))
    done

    echo "----------------------------------------"
    read -rp "Enter your choice: " CHOICE

    if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt ${#CONFIG_FOLDERS[@]} ]; then
        print_error "Invalid choice"
        exit 1
    fi

    SELECTED_FOLDER="${CONFIG_FOLDERS[$((CHOICE-1))]}"
    print_success "Selected: $(basename "$SELECTED_FOLDER")"
}

###############################################
#  COPY CONFIG FILES
###############################################
copy_configs() {
    print_status "Copying configuration files..."

    mkdir -p "$TARGET_CONFIG_DIR"
    mkdir -p "$TARGET_CONFIG_DIR/macros"

    cp -v "$SELECTED_FOLDER"/*.cfg "$TARGET_CONFIG_DIR/" 2>/dev/null || true

    if [ -f "$SELECTED_FOLDER/macros.cfg" ]; then
        cp -v "$SELECTED_FOLDER/macros.cfg" "$TARGET_CONFIG_DIR/macros/" || true
    fi

    if [ -d "$SELECTED_FOLDER/macros" ]; then
        cp -rv "$SELECTED_FOLDER/macros/"* "$TARGET_CONFIG_DIR/macros/" || true
    fi

    print_success "Configuration files copied"
}

###############################################
#  FIX PERMISSIONS
###############################################
fix_permissions() {
    print_status "Fixing permissions..."
    sudo chown -R pi:pi "$TARGET_CONFIG_DIR"
    sudo chmod -R 775 "$TARGET_CONFIG_DIR"
    print_success "Permissions fixed"
}

###############################################
#  RESTART SERVICES
###############################################
restart_services() {
    print_status "Restarting Klipper services..."
    sudo systemctl restart klipper || true
    sudo systemctl restart moonraker || true
    sudo systemctl restart KlipperScreen || true
    print_success "Services restarted"
}

###############################################
#  MAIN EXECUTION
###############################################
print_status "Starting FLSUN configuration restore..."

select_source_folder
show_menu_and_select
copy_configs
fix_permissions
restart_services

print_success "FLSUN configuration restore completed successfully!"
