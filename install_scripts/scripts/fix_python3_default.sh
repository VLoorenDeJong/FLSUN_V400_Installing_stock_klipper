#!/usr/bin/env bash
set -e

# =============================================================================
# Restore /usr/bin/python3 to the distro default (3.10 on Ubuntu 22.04).
# Guilouz's sp_installer2.sh points python3 at python3.9 (deadsnakes).
# That breaks every apt tool written in Python: apt_pkg is built for 3.10
# only, so package postinst scripts fail ("No module named 'apt_pkg'") and
# apt-get exits 1 until repaired. Klipper is not affected — its venvs carry
# their own interpreter path. Runs at the end of Phase 2, after everything
# that expects the 3.9 default.
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
