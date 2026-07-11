#!/bin/bash
set -e

# ============================================
# Future‑Proof Python Installer (Auto‑Detect)
# ============================================

run_privileged() {
    if [ "$EUID" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

print_status() { printf "\033[34m🔧 %s\033[0m\n" "$1"; }
print_success() { printf "\033[32m✅ %s\033[0m\n" "$1"; }
print_warning() { printf "\033[33m⚠️ %s\033[0m\n" "$1"; }
print_error() { printf "\033[31m❌ %s\033[0m\n" "$1"; }

# Busy indicator (same style as updates_install_and_clean.sh)
show_progress() {
    while kill -0 "$1" 2>/dev/null; do
        printf "."
        sleep 3
    done
}

print_status "Detecting available Python versions"

# FIX: must NOT run detection inside a subshell
LATEST_PY=""
AVAILABLE_PYTHON_VERSIONS=()

detect_versions() {
    print_status "Checking installability of Python versions"

    for pkg in $(apt-cache pkgnames | grep -E '^python3\.[0-9]+$' | sort -V); do
        printf "   → Testing %-12s " "$pkg"

        # Step 1: apt simulation
        if apt-get install -s "$pkg" >/dev/null 2>&1; then

            # Step 2: download the .deb and check if it contains a real python binary
            DEB=$(apt-get download -qq "$pkg" 2>/dev/null)

            if [ -n "$DEB" ] && dpkg-deb --contents "$DEB" | grep -q "/usr/bin/python3"; then
                printf "✔ installable (binary present)\n"
                AVAILABLE_PYTHON_VERSIONS+=("$pkg")
            else
                printf "❌ metadata only (no binary)\n"
            fi

        else
            printf "❌ not installable\n"
        fi
    done
}


detect_versions 
printf "\n"

if [ ${#AVAILABLE_PYTHON_VERSIONS[@]} -eq 0 ]; then
    print_error "No installable Python 3.x versions found"
    exit 1
fi

LATEST_PY="${AVAILABLE_PYTHON_VERSIONS[-1]}"
LATEST_VERSION="${LATEST_PY#python}"

print_success "Latest installable Python detected: $LATEST_VERSION"

CURRENT_VERSION=$(python3 --version 2>/dev/null || echo "none")

if [[ "$CURRENT_VERSION" == *"$LATEST_VERSION"* ]]; then
    print_success "Python $LATEST_VERSION already installed — skipping installation"
    exit 0
fi

print_warning "Python is not at latest version (current: $CURRENT_VERSION)"
print_status "Preparing to install Python $LATEST_VERSION"

print_status "Removing old Python versions"
(
    for ver in "${AVAILABLE_PYTHON_VERSIONS[@]}"; do
        # Purge main version package if installed
        if dpkg -s "$ver" >/dev/null 2>&1; then
            run_privileged apt purge -y "$ver" >/dev/null 2>&1 || true
        fi

        # Purge venv package if installed
        if dpkg -s "$ver-venv" >/dev/null 2>&1; then
            run_privileged apt purge -y "$ver-venv" >/dev/null 2>&1 || true
        fi

        # Purge distutils package if installed
        if dpkg -s "$ver-distutils" >/dev/null 2>&1; then
            run_privileged apt purge -y "$ver-distutils" >/dev/null 2>&1 || true
        fi
    done

    # Remove leftover directories
    run_privileged rm -rf /usr/lib/python3.* >/dev/null 2>&1 || true
    run_privileged rm -rf /usr/local/lib/python3.* >/dev/null 2>&1 || true
) &
show_progress $!
printf "\n"
print_success "Old Python versions removed"


print_status "Repairing dpkg state"
(
    run_privileged dpkg --remove --force-remove-reinstreq python3.[0-9] >/dev/null 2>&1 || true
    run_privileged apt --fix-broken install -y >/dev/null 2>&1 || true
    run_privileged dpkg --configure -a >/dev/null 2>&1 || true
) &
show_progress $!
printf "\n"
print_success "dpkg state repaired"

print_status "Updating package lists"
(run_privileged apt-get update -qq >/dev/null 2>&1) &
show_progress $!
printf "\n"
print_success "Package lists updated"

print_status "Installing Python $LATEST_VERSION packages"
(
    run_privileged apt-get install -y -qq \
        python3 \
        "$LATEST_PY" \
        "$LATEST_PY-venv" \
        "$LATEST_PY-distutils" \
        python3-pip \
        python3-apt \
        python3-distutils \
        >/dev/null 2>&1
) &
show_progress $!
printf "\n"
print_success "Python $LATEST_VERSION installed"

# ============================================================
# FIXED SYMLINK SECTION (minimal changes, correct behavior)
# ============================================================

print_status "Repairing python3 symlink"
(
    PYBIN="/usr/bin/$LATEST_PY"

    if [[ ! -x "$PYBIN" ]]; then
        print_error "Python binary not found at $PYBIN"
        exit 1
    fi

    # Register Python version
    run_privileged update-alternatives --install /usr/bin/python3 python3 "$PYBIN" 2 >/dev/null 2>&1

    # Force python3 → latest version
    run_privileged update-alternatives --set python3 "$PYBIN" >/dev/null 2>&1
) &
show_progress $!
printf "\n"
print_success "python3 symlink updated"

FINAL_VERSION=$(python3 --version 2>/dev/null)
if [[ "$FINAL_VERSION" != *"$LATEST_VERSION"* ]]; then
    print_error "python3 is not pointing to Python $LATEST_VERSION (current: $FINAL_VERSION)"
    exit 1
fi

print_success "python3 now points to Python $LATEST_VERSION ($FINAL_VERSION)"

print_status "Testing virtual environment creation"
(
    run_privileged rm -rf /tmp/python_test_env >/dev/null 2>&1
    python3 -m venv /tmp/python_test_env >/dev/null 2>&1
) &
show_progress $!
printf "\n"

if [ ! -f "/tmp/python_test_env/bin/activate" ]; then
    print_error "Virtual environment creation failed — Python installation still broken"
    exit 1
fi

print_success "Virtual environment creation works"
run_privileged rm -rf /tmp/python_test_env >/dev/null 2>&1

print_success "Python $LATEST_VERSION environment installed and verified"

exit 0