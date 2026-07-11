#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive

# =============================================================================
# Install latest supported Python 3.x + venv + distutils
# Automatically detects the highest python3.X version available in apt.
# Matches the exact style of updates_install_and_clean.sh
# =============================================================================

# --- Inline show_progress (copied exactly) ---
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

# --- DPKG lock fixer (copied exactly) ---
check_and_fix_dpkg_lock() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local fix_script="$script_dir/fix_dpkg_lock.sh"
    
    if [ -f "$fix_script" ]; then
        echo -e "\e[34m🔧 Checking and fixing DPKG locks...\e[0m"
        if bash "$fix_script"; then
            echo -e "\e[32m✅ DPKG lock check/fix completed\e[0m"
            return 0
        else
            echo -e "\e[31m❌ DPKG lock fix failed, continuing anyway...\e[0m"
            return 1
        fi
    else
        echo -e "\e[33m⚠️  fix_dpkg_lock.sh not found, proceeding without DPKG lock check\e[0m"
        return 1
    fi
}

# --- State tracking ---
STATE_DIR="/var/lib/linuxsetups"
STATE_FILE="${STATE_DIR}/install_python_latest.done"
FORCE_RUN="${FORCE_RUN_PYTHON:-0}"

if [ "$(id -u)" -ne 0 ]; then
    echo -e "\e[31m❌ This script must run with sudo/root privileges.\e[0m"
    exit 1
fi

if [ -f "$STATE_FILE" ] && [ "$FORCE_RUN" != "1" ]; then
    echo -e "\e[33m⚠️  Python already installed previously. Skipping.\e[0m"
    echo -e "\e[33m⚠️  To force rerun: FORCE_RUN_PYTHON=1 sudo bash $0\e[0m"
    exit 0
fi

echo -e "\n\e[36m=== Install latest supported Python 3.x + venv + distutils ===\e[0m"

# --- Detect latest supported python3.X version ---
echo -e "\e[34m🔧 Detecting latest supported python3.X version...\e[0m"

LATEST=$(apt-cache pkgnames python3. | grep -E '^python3\.[0-9]+$' | sort -V | tail -n 1)

if [ -z "$LATEST" ]; then
    echo -e "\e[31m❌ No supported python3.X version found in apt repositories.\e[0m"
    exit 1
fi

echo -e "\e[32m✅ Detected Python package: $LATEST\e[0m"

# --- Install python3.X + venv + distutils ---
show_progress "🔧 Installing $LATEST ${LATEST}-venv ${LATEST}-distutils" \
"sudo apt-get install -y $LATEST ${LATEST}-venv ${LATEST}-distutils -qq >/dev/null 2>&1"

# --- Verify installation ---
PYBIN=$(command -v "${LATEST}")
INSTALLED_VER=$($PYBIN --version 2>&1 || true)
echo -e "\e[32m✅ Installed: $INSTALLED_VER\e[0m"

mkdir -p "$STATE_DIR"
date -u +"%Y-%m-%dT%H:%M:%SZ" > "$STATE_FILE"

# --- Ensure pip exists ---
if ! $PYBIN -m pip --version >/dev/null 2>&1; then
    show_progress "🔧 Installing pip for $LATEST" \
    "curl -sSLo get-pip.py https://bootstrap.pypa.io/pip/${LATEST#python3.}/get-pip.py && $PYBIN get-pip.py && rm -f get-pip.py"
fi

# --- Upgrade pip, setuptools, wheel, virtualenv ---
show_progress "🔧 Upgrading pip, setuptools, wheel, virtualenv for $LATEST" \
"$PYBIN -m pip install --upgrade pip setuptools wheel virtualenv"

# --- Fix permissions ---
SITEPKG=$($PYBIN -c "import site; print(site.getsitepackages()[0])")
if [ -d "$SITEPKG" ]; then
    echo -e "\e[34m🔧 Fixing permissions in $SITEPKG (if needed)...\e[0m"
    chown -R root:root "$SITEPKG"
    chmod -R go-w "$SITEPKG"
fi

echo -e "\e[32m✅ Python environment ready.\e[0m"
