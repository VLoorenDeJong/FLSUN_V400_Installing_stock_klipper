#!/usr/bin/env bash
set -e

# =============================================================================
# Restore /usr/bin/python3 to the distro default (3.10 on Ubuntu 22.04).
# Guilouz's sp_installer2.sh points python3 at python3.9 (deadsnakes).
# That breaks every apt tool written in Python: apt_pkg is built for 3.10
# only, so package postinst scripts fail ("No module named 'apt_pkg'") and
# apt-get exits 1 until repaired.
#
# WARNING learned the hard way: KIAUH-built venvs are NOT immune. Their
# bin/python symlinks to the movable /usr/bin/python3 link. Flipping the
# default to 3.10 hollows out every 3.9 venv (packages live in
# lib/python3.9). So this script FIRST pins each venv's bin/python to the
# versioned binary it was built with, THEN repoints the default.
# Runs at the end of Phase 2, after all venvs exist.
# =============================================================================

print_status()  { printf "\033[34m🔧 %s\033[0m\n" "$1"; }
print_success() { printf "\033[32m✅ %s\033[0m\n" "$1"; }
print_warning() { printf "\033[33m⚠️  %s\033[0m\n" "$1"; }
print_error()   { printf "\033[31m❌ %s\033[0m\n" "$1"; }
print_header()  { printf "\n\033[36m=== %s ===\033[0m\n" "$1"; }

if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must run with sudo/root privileges."
    exit 1
fi

print_header "Restore python3 → distro default (3.10)"

DISTRO_PY="/usr/bin/python3.10"

if [ ! -x "$DISTRO_PY" ]; then
    print_warning "python3.10 not found — not on Ubuntu 22.04 yet. Skipping."
    exit 0
fi

CURRENT="$(readlink -f /usr/bin/python3 || true)"
if [ "$CURRENT" = "$DISTRO_PY" ] && python3 -c "import apt_pkg" >/dev/null 2>&1; then
    print_success "python3 already points to 3.10 and apt_pkg imports. Nothing to do."
    exit 0
fi

print_status "python3 currently: ${CURRENT:-unknown} — repointing to $DISTRO_PY"

# --- Pin venv interpreters BEFORE moving the default ---
# Each venv's bin/python must point at the versioned binary it was built
# with, not at the movable /usr/bin/python3 link.
TARGET_USER="${SUDO_USER:-}"
if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = "root" ]; then
    id pi >/dev/null 2>&1 && TARGET_USER="pi" || TARGET_USER="$(whoami)"
fi
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

VENV_DIRS=(
    "${TARGET_HOME}/klippy-env"
    "${TARGET_HOME}/klipper-env"
    "${TARGET_HOME}/moonraker-env"
    "${TARGET_HOME}/.KlipperScreen-env"
    "${TARGET_HOME}/KlipperScreen-env"
    "${TARGET_HOME}/crowsnest-env"
    "${TARGET_HOME}/moonraker-telegram-bot-env"
)

for venv in "${VENV_DIRS[@]}"; do
    pybin="${venv}/bin/python"
    [ -L "$pybin" ] || continue
    # The lib/python3.X dir names the version this venv was built with.
    ver=$(basename "$(find "${venv}/lib" -maxdepth 1 -name "python3*" 2>/dev/null | head -1)")
    [ -n "$ver" ] || continue
    versioned="/usr/bin/${ver}"
    if [ ! -x "$versioned" ]; then
        print_warning "$versioned not found — cannot pin $(basename "$venv")."
        continue
    fi
    if [ "$(readlink "$pybin")" != "$versioned" ]; then
        ln -sfn "$versioned" "$pybin"
        print_success "Pinned $(basename "$venv")/bin/python → $versioned"
    fi
done

# Register 3.10 with a higher priority than sp_installer2's 3.9 entry (1),
# then select it explicitly.
update-alternatives --install /usr/bin/python3 python3 "$DISTRO_PY" 2
update-alternatives --set python3 "$DISTRO_PY"

# Verify: version and the apt python bindings.
if python3 -c "import apt_pkg" >/dev/null 2>&1; then
    print_success "python3 → $(python3 --version 2>&1); apt_pkg imports OK"
else
    print_error "apt_pkg still fails to import — apt tooling is still broken."
    print_error "Check by hand: python3 -c 'import apt_pkg'"
    exit 1
fi

# python3.9 stays installed for the Klipper stack; only the default changed.
print_success "python3.9 remains available at /usr/bin/python3.9"
exit 0
