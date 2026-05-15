#!/usr/bin/env bash
set -e

# =============================================================================
# Fix outdated pip — patch ensurepip + upgrade existing venvs
# =============================================================================
# Raspbian/Debian Python 3.9 ships with an old pip that uses toml-0.10.0 to
# parse pyproject.toml files. That library has a parser bug (IndexError in
# array handling) that causes Moonraker/Klipper requirements to fail.
#
# Root cause: Python's `ensurepip` module seeds new venvs with its bundled pip
# wheel. Even if you upgrade pip in a venv, KIAUH recreates the venv on retry
# and the old pip is seeded again.
#
# Fix: replace the bundled pip wheel inside ensurepip with a newer one BEFORE
# KIAUH runs, so every new venv gets a working pip from the start.
# =============================================================================

print_status()  { printf "\033[34m🔧 %s\033[0m\n" "$1"; }
print_success() { printf "\033[32m✅ %s\033[0m\n" "$1"; }
print_warning() { printf "\033[33m⚠️  %s\033[0m\n" "$1"; }
print_error()   { printf "\033[31m❌ %s\033[0m\n" "$1"; }
print_header()  { printf "\n\033[36m=== %s ===\033[0m\n" "$1"; }

had_issues=false

if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must run with sudo/root privileges."
    exit 1
fi

# Resolve actual user home (works under sudo)
TARGET_USER="${SUDO_USER:-}"
if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = "root" ]; then
    id pi >/dev/null 2>&1 && TARGET_USER="pi" || TARGET_USER="$(whoami)"
fi
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

print_header "Fix pip — Patch ensurepip Bundled Wheel"
print_warning "Old pip uses toml-0.10.0 which has a TOML array parser bug."
print_warning "Patching ensurepip so all new venvs get a working pip."

# --- Step 1: find ensurepip bundled wheel directory ---
BUNDLED_DIR=$(python3 -c "import ensurepip, os; print(os.path.join(ensurepip.__path__[0], '_bundled'))" 2>/dev/null || true)

# Fallback for distros where ensurepip path cannot be resolved via Python.
if [ -z "$BUNDLED_DIR" ] || [ ! -d "$BUNDLED_DIR" ]; then
    BUNDLED_DIR=$(find /usr/lib /usr/local/lib -type d -path "*/python*/ensurepip/_bundled" 2>/dev/null | sort -V | head -1 || true)
fi

if [ -z "$BUNDLED_DIR" ] || [ ! -d "$BUNDLED_DIR" ]; then
    print_warning "Could not locate ensurepip bundled directory — skipping ensurepip patch."
    print_warning "Some distro Python builds omit ensurepip wheels; venv-level pip upgrades are still applied below."
    had_issues=true
else
    OLD_PIP_WHEEL=$(find "$BUNDLED_DIR" -name "pip-*.whl" | sort -V | tail -1)
    if [ -n "$OLD_PIP_WHEEL" ]; then
        OLD_VER=$(basename "$OLD_PIP_WHEEL" | sed 's/pip-\([^-]*\)-.*/\1/')
        print_status "Current bundled pip version: $OLD_VER"
    fi

    # Download newer pip wheel into a temp dir
    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT

    print_status "Downloading newer pip wheel..."
    if python3 -m pip download pip --no-deps --dest "$TMP_DIR" --quiet 2>/dev/null; then
        NEW_PIP_WHEEL=$(find "$TMP_DIR" -name "pip-*.whl" | sort -V | tail -1)
        if [ -n "$NEW_PIP_WHEEL" ]; then
            NEW_VER=$(basename "$NEW_PIP_WHEEL" | sed 's/pip-\([^-]*\)-.*/\1/')
            # Back up old wheel and replace
            [ -n "$OLD_PIP_WHEEL" ] && cp "$OLD_PIP_WHEEL" "${OLD_PIP_WHEEL}.bak"
            cp "$NEW_PIP_WHEEL" "$BUNDLED_DIR/"
            # Remove old wheel if different filename
            if [ -n "$OLD_PIP_WHEEL" ] && [ "$(basename "$OLD_PIP_WHEEL")" != "$(basename "$NEW_PIP_WHEEL")" ]; then
                rm -f "$OLD_PIP_WHEEL"
            fi
            print_success "ensurepip pip upgraded: $OLD_VER → $NEW_VER"
            print_warning "Backup saved as: ${OLD_PIP_WHEEL}.bak"
        else
            print_warning "Downloaded wheel not found — ensurepip patch skipped."
            had_issues=true
        fi
    else
        print_warning "pip download failed (no internet?) — ensurepip patch skipped."
        had_issues=true
    fi
fi

# --- Step 2: upgrade pip in any already-existing venvs ---
print_header "Upgrade pip in Existing Virtual Environments"

VENV_DIRS=(
    "${TARGET_HOME}/moonraker-env"
    "${TARGET_HOME}/klipper-env"
    "${TARGET_HOME}/klippy-env"
    "${TARGET_HOME}/mainsail-env"
    "${TARGET_HOME}/KlipperScreen-env"
    "${TARGET_HOME}/crowsnest-env"
    "${TARGET_HOME}/moonraker-telegram-bot-env"
)

any_upgraded=false
for venv in "${VENV_DIRS[@]}"; do
    py_bin="${venv}/bin/python"
    pip_bin="${venv}/bin/pip"

    if [ -x "$py_bin" ]; then
        py_major=$(sudo -u "$TARGET_USER" "$py_bin" -c 'import sys; print(sys.version_info[0])' 2>/dev/null || echo "0")
        if [ "$py_major" -lt 3 ]; then
            print_warning "$(basename "$venv") uses Python $py_major — skipping pip upgrade. Recreate this venv with Python 3 via KIAUH."
            had_issues=true
            continue
        fi

        print_status "Upgrading pip in: $(basename "$venv")..."

        # Recover venvs where pip entrypoint exists but pip module is missing.
        if ! sudo -u "$TARGET_USER" "$py_bin" -m pip --version >/dev/null 2>&1; then
            print_warning "pip module missing in $(basename "$venv") — attempting ensurepip bootstrap"
            sudo -u "$TARGET_USER" "$py_bin" -m ensurepip --upgrade --default-pip >/dev/null 2>&1 || true
        fi

        if sudo -u "$TARGET_USER" "$py_bin" -m pip install --upgrade pip --quiet; then
            new_ver=$(sudo -u "$TARGET_USER" "$py_bin" -m pip --version 2>/dev/null | awk '{print $2}')
            print_success "pip → $new_ver in $(basename "$venv")"
            any_upgraded=true
        else
            print_warning "pip upgrade failed in $venv — continuing anyway"
            had_issues=true
        fi
    elif [ -x "$pip_bin" ]; then
        print_status "Upgrading pip in: $(basename "$venv")..."
        if sudo -u "$TARGET_USER" "$pip_bin" install --upgrade pip --quiet; then
            new_ver=$(sudo -u "$TARGET_USER" "$pip_bin" --version 2>/dev/null | awk '{print $2}')
            print_success "pip → $new_ver in $(basename "$venv")"
            any_upgraded=true
        else
            print_warning "pip upgrade failed in $venv — continuing anyway"
            had_issues=true
        fi
    fi
done

if [ "$any_upgraded" = false ]; then
    print_warning "No existing venvs found — ensurepip patch above covers new venvs."
fi

# --- Step 3: fix setuptools for Klipper venv creation (step 510-514) ---
# KIAUH's Klipper installer fails with "Creation of Klipper virtualenv failed"
# if setuptools is too new. Pin to 59.6.0 and set SETUPTOOLS_USE_DISTUTILS=stdlib
# in /etc/environment so KIAUH inherits it.
print_header "Fix setuptools for Klipper venv (step 510)"
print_warning "Pinning system setuptools to 59.6.0 to prevent Klipper venv creation failure."

# Ensure python3 has a working pip module first.
if ! python3 -m pip --version >/dev/null 2>&1; then
    python3 -m ensurepip --upgrade >/dev/null 2>&1 || true
fi

# Some images have python3.9 installed while /usr/bin/python3 lacks pip.
if command -v python3.9 >/dev/null 2>&1 && ! python3.9 -m pip --version >/dev/null 2>&1; then
    python3.9 -m ensurepip --upgrade >/dev/null 2>&1 || true
fi

SETUPTOOLS_LOG=$(mktemp)
setuptools_pinned=false

if python3 -m pip install --quiet --break-system-packages setuptools==59.6.0 > /dev/null 2>>"$SETUPTOOLS_LOG"; then
    setuptools_pinned=true
elif python3 -m pip install --quiet setuptools==59.6.0 > /dev/null 2>>"$SETUPTOOLS_LOG"; then
    setuptools_pinned=true
elif command -v python3.9 >/dev/null 2>&1 && python3.9 -m pip install --quiet --break-system-packages setuptools==59.6.0 > /dev/null 2>>"$SETUPTOOLS_LOG"; then
    setuptools_pinned=true
elif command -v python3.9 >/dev/null 2>&1 && python3.9 -m pip install --quiet setuptools==59.6.0 > /dev/null 2>>"$SETUPTOOLS_LOG"; then
    setuptools_pinned=true
elif command -v pip3 >/dev/null 2>&1 && pip3 install --quiet setuptools==59.6.0 > /dev/null 2>>"$SETUPTOOLS_LOG"; then
    setuptools_pinned=true
elif command -v pip >/dev/null 2>&1 && pip install --quiet setuptools==59.6.0 > /dev/null 2>>"$SETUPTOOLS_LOG"; then
    setuptools_pinned=true
fi

if [ "$setuptools_pinned" = true ]; then
    print_success "setuptools pinned to 59.6.0"
else
    print_warning "setuptools pin failed — continuing anyway (may cause Klipper venv issues)"
    if [ -s "$SETUPTOOLS_LOG" ]; then
        print_warning "setuptools pin error (last lines):"
        tail -n 20 "$SETUPTOOLS_LOG"
    fi
    had_issues=true
fi

rm -f "$SETUPTOOLS_LOG"

# Set SETUPTOOLS_USE_DISTUTILS=stdlib persistently so KIAUH's virtualenv call picks it up
ENV_FILE="/etc/environment"
if grep -q "SETUPTOOLS_USE_DISTUTILS" "$ENV_FILE" 2>/dev/null; then
    print_warning "SETUPTOOLS_USE_DISTUTILS already set in $ENV_FILE — skipping."
else
    echo 'SETUPTOOLS_USE_DISTUTILS=stdlib' >> "$ENV_FILE"
    print_success "Set SETUPTOOLS_USE_DISTUTILS=stdlib in $ENV_FILE"
fi

# Also export for the current shell session so it takes effect immediately
export SETUPTOOLS_USE_DISTUTILS=stdlib

print_success "pip + setuptools fix complete."

if [ "$had_issues" = true ]; then
    print_warning "Completed with warnings. Re-run this script after internet and Python/pip packages are healthy."
fi
