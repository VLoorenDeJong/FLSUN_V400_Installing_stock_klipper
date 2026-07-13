#!/usr/bin/env bash
set -e

# =============================================================================
# Detect which Klipper-stack services are actually present on this host and,
# if any are found, write /etc/update-motd.d/services.list so the generic
# 60-guiderails-extras MOTD script (installed by configure_motd_services.sh)
# shows a status line for each one at login.
#
# This is intentionally a separate script from configure_motd_services.sh:
# that script only restores/extends the standard Ubuntu MOTD in a project-
# neutral way, while this script supplies this specific project's Klipper
# service list. If none of the candidate services are found (e.g. run before
# KIAUH has installed anything, or on some other host entirely), it does
# nothing and leaves the MOTD's services section absent rather than showing
# an empty/misleading block.
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

STATE_DIR="/var/lib/linuxsetups"
STATE_FILE="${STATE_DIR}/configure_klipper_motd_services.done"
FORCE_RUN="${FORCE_RUN_KLIPPER_MOTD_SERVICES:-0}"

if [ -f "$STATE_FILE" ] && [ "$FORCE_RUN" != "1" ]; then
    print_warning "MOTD services list already configured previously. Skipping."
    print_warning "To force rerun: sudo env FORCE_RUN_KLIPPER_MOTD_SERVICES=1 bash $0"
    exit 0
fi

print_header "Configure MOTD Service Status (auto-detect)"

MOTD_DIR="/etc/update-motd.d"
SERVICES_LIST="$MOTD_DIR/services.list"

if [ ! -d "$MOTD_DIR" ]; then
    print_warning "$MOTD_DIR not found — run configure_motd_services.sh first. Skipping."
    exit 0
fi

# Candidate service unit names for this project's Klipper stack. Checked with
# `systemctl list-unit-files`, which reports on a unit whether it's currently
# active or not — this only tells us the unit is known to systemd at all.
CANDIDATES=(klipper moonraker KlipperScreen)
DETECTED=()

for svc in "${CANDIDATES[@]}"; do
    if systemctl list-unit-files "${svc}.service" --no-legend 2>/dev/null | grep -q .; then
        DETECTED+=("$svc")
        print_status "Detected service: $svc"
    fi
done

if [ ${#DETECTED[@]} -eq 0 ]; then
    print_warning "No Klipper-stack services detected on this host — nothing to configure yet."
    print_warning "This is expected if Phase 2 (KIAUH install) hasn't run yet."
    # Deliberately do NOT write the state file here — only mark this done once
    # services are actually detected and configured, so a later run (e.g. at
    # the end of Phase 2, once Klipper/Moonraker/KlipperScreen exist) still
    # gets a real chance instead of skipping via a stale "already ran" marker.
    exit 0
fi

printf '%s\n' "${DETECTED[@]}" > "$SERVICES_LIST"
print_success "Wrote $SERVICES_LIST with: ${DETECTED[*]}"

mkdir -p "$STATE_DIR"
date -u +"%Y-%m-%dT%H:%M:%SZ" > "$STATE_FILE"

print_success "MOTD service status configured. Reconnect via SSH to see it."
