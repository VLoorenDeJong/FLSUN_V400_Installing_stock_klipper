#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive

# =============================================================================
# Install latest supported Python 3.x + venv + distutils
# Automatically detects the highest python3.X version available in apt.
# Matches the exact style of updates_install_and_clean.sh
# =============================================================================

print_status()  { printf "\033[34m🔧 %s\033[0m\n" "$1"; }
print_success() { printf "\033[32m✅ %s\033[0m\n" "$1"; }
print_warning() { printf "\033[33m⚠️  %s\033[0m\n" "$1"; }
print_error()   { printf "\033[31m❌ %s\033[0m\n" "$1"; }
print_header()  { printf "\n\033[36m=== %s ===\033[0m\n" "$1"; }

# --- Inline show_progress (copied exactly) ---
show_progress() {
    local message="$1"
    local command="$2"
    local interval="${3:-5}"
    local timeout="${4:-600}"
    local log_file
    log_file=$(mktemp /tmp/progress.XXXXXX.log)
    printf "\033[34m%s\033[0m\n" "$message"

    # Debug mode: stream output live. No dots, no kill timer.
    if [ "${FLSUN_DEBUG:-0}" = "1" ]; then
        eval "$command" 2>&1 | tee "$log_file"
        local exit_code=${PIPESTATUS[0]}
        if [ "$exit_code" -eq 0 ]; then
            rm -f "$log_file"
        else
            printf "\033[31m❌ Command failed (exit %s). Full log: %s\033[0m\n" "$exit_code" "$log_file"
        fi
        return "$exit_code"
    fi

    # Normal mode: capture output to the log. Show dots.
    eval "$command" >"$log_file" 2>&1 &
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
            printf "\033[31mLast output before timeout:\033[0m\n"
            tail -n 20 "$log_file"
            printf "\033[33mFull log: %s\033[0m\n" "$log_file"
            return 1
        fi
    done
    wait $cmd_pid 2>/dev/null
    local exit_code=$?
    printf "\n"
    if [ "$exit_code" -ne 0 ]; then
        printf "\033[31m❌ Command failed (exit %s). Last output:\033[0m\n" "$exit_code"
        tail -n 20 "$log_file"
        printf "\033[33mFull log: %s\033[0m\n" "$log_file"
    else
        rm -f "$log_file"
    fi
    return "$exit_code"
}

# --- DPKG lock fixer (copied exactly) ---
check_and_fix_dpkg_lock() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local fix_script="$script_dir/fix_dpkg_lock.sh"

    if [ -f "$fix_script" ]; then
        print_status "Checking and fixing DPKG locks..."
        if bash "$fix_script"; then
            print_success "DPKG lock check/fix completed"
            return 0
        else
            print_error "DPKG lock fix failed, continuing anyway..."
            return 1
        fi
    else
        print_warning "fix_dpkg_lock.sh not found, proceeding without DPKG lock check"
        return 1
    fi
}

# --- State tracking ---
STATE_DIR="/var/lib/linuxsetups"
STATE_FILE="${STATE_DIR}/install_python_latest.done"
FORCE_RUN="${FORCE_RUN_PYTHON:-0}"

if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must run with sudo/root privileges."
    exit 1
fi

if [ -f "$STATE_FILE" ] && [ "$FORCE_RUN" != "1" ]; then
    print_warning "Python already installed previously. Skipping."
    print_warning "To force rerun: sudo env FORCE_RUN_PYTHON=1 bash $0"
    exit 0
fi

print_header "Install latest supported Python 3.x + venv + distutils"

# --- Use the distribution's DEFAULT python3, not the newest available ---
# Grabbing "newest python3.X in apt" is wrong: a deadsnakes-style PPA or a newer
# base image can expose e.g. python3.15, and Python 3.12+ dropped distutils
# entirely — so `apt-get install python3.15-distutils` fails and aborts the whole
# install. The distro default (the unversioned python3 metapackage) is the
# version this OS ships and the Klipper stack supports (3.10 on Ubuntu 22.04),
# needs no hardcoded version to maintain, and a PPA cannot hijack it.
print_status "Ensuring the distribution default python3 + venv + dev tooling..."

show_progress "🔧 Installing python3 + venv + dev" \
"sudo apt-get install -y python3 python3-venv python3-dev -qq"

# distutils only where it still exists (removed from Python 3.12+); guard it so a
# missing package can never abort the install.
if apt-cache show python3-distutils >/dev/null 2>&1; then
    show_progress "🔧 Installing python3-distutils" \
    "sudo apt-get install -y python3-distutils -qq"
else
    print_warning "python3-distutils not available on this release (Python 3.12+) — skipping."
fi

# --- Verify installation ---
PYBIN="$(command -v python3)"
if [ -z "$PYBIN" ]; then
    print_error "python3 not found after install."
    exit 1
fi
INSTALLED_VER=$($PYBIN --version 2>&1 || true)
print_success "Using distribution default: $INSTALLED_VER"

mkdir -p "$STATE_DIR"
date -u +"%Y-%m-%dT%H:%M:%SZ" > "$STATE_FILE"

# --- Ensure pip exists ---
# pypa's default get-pip.py requires Python >= 3.10. Older Pythons
# (3.8 on Ubuntu 20.04) must use the versioned URL instead.
GETPIP_URL="https://bootstrap.pypa.io/get-pip.py"
PYMINOR=$($PYBIN -c 'import sys; print(sys.version_info[1])' 2>/dev/null || echo 10)
if [ "$PYMINOR" -lt 10 ]; then
    GETPIP_URL="https://bootstrap.pypa.io/pip/3.${PYMINOR}/get-pip.py"
    print_warning "Old Python 3.${PYMINOR} — using versioned get-pip URL."
fi
if ! $PYBIN -m pip --version >/dev/null 2>&1; then
    show_progress "🔧 Installing pip for $INSTALLED_VER" \
    "curl -sSLo get-pip.py '$GETPIP_URL' && $PYBIN get-pip.py && rm -f get-pip.py"
fi

# --- Upgrade pip, setuptools, wheel, virtualenv ---
show_progress "🔧 Upgrading pip, setuptools, wheel, virtualenv" \
"$PYBIN -m pip install --upgrade pip setuptools wheel virtualenv"

# --- Fix permissions ---
SITEPKG=$($PYBIN -c "import site; print(site.getsitepackages()[0])")
if [ -d "$SITEPKG" ]; then
    print_status "Fixing permissions in $SITEPKG (if needed)..."
    chown -R root:root "$SITEPKG"
    chmod -R go-w "$SITEPKG"
fi

print_success "Python environment ready."
