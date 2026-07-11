#!/usr/bin/env bash
set -e

# ───────────────────────────────────────────────
#   PRINT HELPERS (your exact style)
# ───────────────────────────────────────────────
print_status()   { printf "\033[34m🔧 %s\033[0m\n" "$1"; }
print_success()  { printf "\033[32m✅ %s\033[0m\n" "$1"; }
print_warning()  { printf "\033[33m⚠️ %s\033[0m\n" "$1"; }
print_error()    { printf "\033[31m❌ %s\033[0m\n" "$1"; }

# ───────────────────────────────────────────────
#   BUSY INDICATOR (same as updates_install_and_clean.sh)
# ───────────────────────────────────────────────
show_progress() {
    while kill -0 "$1" 2>/dev/null; do
        printf "."
        sleep 3
    done
}

# ───────────────────────────────────────────────
#   PYTHON DETECTION (Speeder Pad safe)
# ───────────────────────────────────────────────
print_status "Detecting existing Python installation"

PYTHON_BIN="$(command -v python3 || true)"
PYTHON_TARGET="/usr/bin/python3.10"
PYTHON_SYMLINK="/usr/bin/python3"

if [[ -z "${PYTHON_BIN}" ]]; then
    print_error "python3 is missing — Speeder Pad images should ship with Python 3.10.12."
    exit 1
fi

print_status "Checking python3 version"
CURRENT_VERSION="$(${PYTHON_BIN} --version 2>&1 || true)"
printf "   → Detected: %s\n" "${CURRENT_VERSION}"

print_status "Inspecting /usr/bin/python3* layout"
ls -lh /usr/bin/python3* || true

# ───────────────────────────────────────────────
#   VERIFY VENDOR PYTHON EXISTS
# ───────────────────────────────────────────────
if [[ ! -x "${PYTHON_TARGET}" ]]; then
    print_error "Vendor Python 3.10.12 not found at ${PYTHON_TARGET}"
    print_error "This Speeder Pad image may be corrupted or modified."
    exit 1
fi

# ───────────────────────────────────────────────
#   FIX SYMLINK IF NEEDED
# ───────────────────────────────────────────────
if [[ "${PYTHON_BIN}" != "${PYTHON_TARGET}" ]]; then
    print_warning "python3 does not point to python3.10"
    print_status "Updating python3 symlink"

    sudo ln -sf "${PYTHON_TARGET}" "${PYTHON_SYMLINK}"
    print_success "python3 symlink updated to python3.10"

    PYTHON_BIN="${PYTHON_TARGET}"
else
    print_success "python3 already points to python3.10"
fi

# ───────────────────────────────────────────────
#   VERIFY STANDARD LIBRARY
# ───────────────────────────────────────────────
print_status "Verifying Python standard library"

PYTHON_CHECK_SCRIPT=$(
cat <<'EOF'
import sys
import encodings
print("OK")
EOF
)

if ! "${PYTHON_TARGET}" - <<EOF >/tmp/python_check.log 2>&1
${PYTHON_CHECK_SCRIPT}
EOF
then
    print_error "Python 3.10.12 is present but its standard library is broken."
    sed -n '1,40p' /tmp/python_check.log || true
    exit 1
fi

print_success "Vendor Python 3.10.12 is healthy"

# ───────────────────────────────────────────────
#   FINAL SUMMARY
# ───────────────────────────────────────────────
print_status "Skipping apt-based Python installation (Speeder Pad uses vendor Python)"

print_status "Final Python configuration"
printf "   → python3 binary: %s\n" "${PYTHON_BIN}"
printf "   → python3 target: %s\n" "${PYTHON_TARGET}"
"${PYTHON_TARGET}" --version || true

print_success "Python environment ready for Klipper/Moonraker"
