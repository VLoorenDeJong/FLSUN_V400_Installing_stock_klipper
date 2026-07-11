#!/bin/bash
set -e

# ============================================
# Future‑Proof Python Installer (Auto‑Detect)
# ============================================

# Function to run commands with appropriate privileges
run_privileged() {
    if [ "$EUID" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

# Status message functions
print_status() {
    printf "\033[34m🔧 %s\033[0m\n" "$1"
}

print_success() {
    printf "\033[32m✅ %s\033[0m\n" "$1"
}

print_warning() {
    printf "\033[33m⚠️ %s\033[0m\n" "$1"
}

print_error() {
    printf "\033[31m❌ %s\033[0m\n" "$1"
}

print_status "--------------------------------------------"
print_status "Detecting available Python versions"
print_status "--------------------------------------------"

# Detect latest Python 3.x available in apt
LATEST_PY=$(apt-cache pkgnames | grep -E '^python3\.[0-9]+$' | sort -V | tail -n 1)

if [ -z "$LATEST_PY" ]; then
    print_error "No Python 3.x versions found in apt repositories"
    exit 1
fi

print_status "Latest Python detected: $LATEST_PY"

# Extract version number (e.g., python3.12 → 3.12)
LATEST_VERSION="${LATEST_PY#python}"

# Detect current python3 version
CURRENT_VERSION=$(python3 --version 2>/dev/null || echo "none")

if [[ "$CURRENT_VERSION" == *"$LATEST_VERSION"* ]]; then
    print_success "Python $LATEST_VERSION already installed — skipping installation"
    exit 0
fi

print_warning "Python is not at latest version (current: $CURRENT_VERSION)"
print_status "Preparing to install Python $LATEST_VERSION"

print_status "--------------------------------------------"
print_status "Removing old Python versions"
print_status "--------------------------------------------"

# Remove older Python versions (safe)
run_privileged apt purge -y python3.[0-9] python3.[0-9]-minimal python3.[0-9]-venv python3.[0-9]-distutils >/dev/null 2>&1 || true

run_privileged rm -rf /usr/lib/python3.[0-9] >/dev/null 2>&1 || true
run_privileged rm -rf /usr/local/lib/python3.[0-9] >/dev/null 2>&1 || true

print_success "Old Python versions removed"

print_status "Repairing dpkg state..."
run_privileged dpkg --remove --force-remove-reinstreq python3.[0-9] >/dev/null 2>&1 || true
run_privileged apt --fix-broken install -y >/dev/null 2>&1 || true
run_privileged dpkg --configure -a >/dev/null 2>&1 || true
print_success "dpkg state repaired"

print_status "Updating package lists..."
run_privileged apt-get update -qq >/dev/null 2>&1
print_success "Package lists updated"

print_status "Installing Python $LATEST_VERSION packages..."

run_privileged apt-get install -y -qq \
    python3 \
    "$LATEST_PY" \
    "$LATEST_PY-venv" \
    "$LATEST_PY-distutils" \
    python3-pip \
    python3-apt \
    python3-distutils \
    >/dev/null 2>&1

print_success "Python $LATEST_VERSION installed"

print_status "Repairing python3 symlink..."
run_privileged update-alternatives --install /usr/bin/python3 python3 "/usr/bin/$LATEST_PY" 1 >/dev/null 2>&1
run_privileged update-alternatives --set python3 "/usr/bin/$LATEST_PY" >/dev/null 2>&1
print_success "python3 symlink updated"

# Verify python3 version
FINAL_VERSION=$(python3 --version 2>/dev/null)
if [[ "$FINAL_VERSION" != *"$LATEST_VERSION"* ]]; then
    print_error "python3 is not pointing to Python $LATEST_VERSION (current: $FINAL_VERSION)"
    exit 1
fi

print_success "python3 now points to Python $LATEST_VERSION ($FINAL_VERSION)"

print_status "Testing virtual environment creation..."
run_privileged rm -rf /tmp/python_test_env >/dev/null 2>&1
python3 -m venv /tmp/python_test_env >/dev/null 2>&1

if [ ! -f "/tmp/python_test_env/bin/activate" ]; then
    print_error "Virtual environment creation failed — Python installation still broken"
    exit 1
fi

print_success "Virtual environment creation works"
run_privileged rm -rf /tmp/python_test_env >/dev/null 2>&1

print_status "--------------------------------------------"
print_success "Python $LATEST_VERSION environment installed and verified"
print_status "--------------------------------------------"

exit 0
