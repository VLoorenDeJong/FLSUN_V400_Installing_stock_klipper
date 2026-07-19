#!/usr/bin/env bash
# One-shot setup for a fresh clone. Fetches every submodule.
#
#   .claude/guiderails  — shared LLM working agreements (private;
#                         skipped gracefully without access)
#   LinuxBasics         — shared basics install scripts (public)
#
# The device does not need this for Phase 1. Phase 2 needs LinuxBasics.

set -e

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

print_header() {
    printf "\n\033[36m=== %s ===\033[0m\n" "$1"
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# SUBMODULE PATHS — change these if the submodules are ever renamed/moved
# =============================================================================
GUIDERAILS_SUBMODULE=".claude/guiderails"
BASICS_SUBMODULE="LinuxBasics"

print_header "Submodule setup"

if [ ! -f "$REPO_ROOT/.gitmodules" ]; then
    print_error "No .gitmodules found — is this a FLSUN_V400 checkout?"
    exit 1
fi

# Guiderails is private — an access failure is expected for outside clones
print_status "Initializing guiderails (private — may be skipped without access)..."
if git -C "$REPO_ROOT" submodule update --init "$GUIDERAILS_SUBMODULE" 2>/dev/null; then
    print_success "guiderails ready"
else
    print_warning "guiderails not available (no access) — expected for outside clones, continuing"
fi

print_status "Initializing basics scripts..."
if git -C "$REPO_ROOT" submodule update --init "$BASICS_SUBMODULE"; then
    print_success "basics ready"
else
    print_error "Failed to fetch the basics submodule — check network/GitHub access"
    exit 1
fi

print_header "Submodule status"
git -C "$REPO_ROOT" submodule status
print_success "Setup complete"
