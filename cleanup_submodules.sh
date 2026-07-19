#!/usr/bin/env bash
# De-initializes ALL submodules. The repo then looks like a fresh clone.
# Counterpart of setup_submodules.sh. Nothing is lost: everything stays
# on GitHub and setup fetches it back.
#
# Refuses to run if any submodule has uncommitted or unpushed work.

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
SUBMODULES=(
    ".claude/guiderails"
    "LinuxBasics"
)

print_header "Submodule cleanup"

# Refuse to throw away unpublished work. Uncommitted or unpushed
# commits would be unrecoverable after cleanup.
check_clean() {
    local path="$1"
    [ -e "$REPO_ROOT/$path/.git" ] || return 0
    if [ -n "$(git -C "$REPO_ROOT/$path" status --porcelain 2>/dev/null)" ]; then
        print_error "$path has uncommitted changes — not cleaning up"
        print_warning "Commit and push them first (or discard them), then re-run"
        return 1
    fi
    local unpushed
    unpushed=$(git -C "$REPO_ROOT/$path" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)
    if [ "${unpushed:-0}" -gt 0 ] 2>/dev/null; then
        print_error "$path has $unpushed unpushed commit(s) — not cleaning up"
        print_warning "Push them first, then re-run"
        return 1
    fi
    return 0
}

any_initialized=0
for sub in "${SUBMODULES[@]}"; do
    [ -e "$REPO_ROOT/$sub/.git" ] && any_initialized=1
done
if [ "$any_initialized" -eq 0 ]; then
    print_status "No submodules are initialized — nothing to clean up"
    exit 0
fi

for sub in "${SUBMODULES[@]}"; do
    check_clean "$sub" || exit 1
done

# Confirm from the terminal directly. Without a terminal, do nothing.
if [ -e /dev/tty ]; then
    printf "Remove ALL local submodule checkouts (fresh-clone state)? [y/N]: "
    read -r answer < /dev/tty || answer="n"
    case "$answer" in
        [Yy]*) ;;
        *)
            print_status "Cleanup cancelled"
            exit 0
            ;;
    esac
else
    print_warning "No terminal to confirm on — not cleaning up"
    exit 1
fi

for sub in "${SUBMODULES[@]}"; do
    if [ -e "$REPO_ROOT/$sub/.git" ]; then
        print_status "De-initializing $sub..."
        git -C "$REPO_ROOT" submodule deinit -f "$sub"
    fi
    # deinit leaves the pack in .git/modules — remove it to free the space
    MODULE_DIR="$REPO_ROOT/.git/modules/$sub"
    if [ -d "$MODULE_DIR" ]; then
        rm -rf "$MODULE_DIR"
    fi
done

print_success "All submodules cleaned up — repo is back to fresh-clone state"
print_status "Restore everything with: bash setup_submodules.sh"
