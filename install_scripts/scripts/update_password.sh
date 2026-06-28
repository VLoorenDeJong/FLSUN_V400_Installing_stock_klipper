#!/usr/bin/env bash
set -euo pipefail

# Determine the actual interactive user (prefer SUDO_USER when present)
if [ -n "${SUDO_USER:-}" ]; then
    ACTUAL_USER="$SUDO_USER"
else
    ACTUAL_USER="$(whoami)"
fi

# --- Inline utility functions ---
print_status()  { printf "\033[34m🔧 %s\033[0m\n" "$1"; }
print_success() { printf "\033[32m✅ %s\033[0m\n" "$1"; }
print_error()   { printf "\033[31m❌ %s\033[0m\n" "$1"; }
print_header()  { printf "\n\033[36m=== %s ===\033[0m\n" "$1"; }

# Reads a password showing * for each character typed. Handles backspace.
# Usage: read_password "Prompt text" result_var
read_password() {
    local prompt="$1"
    local -n _result_ref=$2
    local char password=""
    printf "%s" "$prompt"
    while IFS= read -r -s -n1 char; do
        # Enter (empty char) ends input
        if [[ -z "$char" ]]; then
            break
        elif [[ "$char" == $'\x7f' || "$char" == $'\b' ]]; then
            if [ ${#password} -gt 0 ]; then
                password="${password%?}"
                printf "\b \b"
            fi
        else
            password+="$char"
            printf "*"
        fi
    done
    printf "\n"
    _result_ref="$password"
}

# --- Main ---
print_header "Update Login Password"
printf "\nCurrent user: \033[33m%s\033[0m\n\n" "$ACTUAL_USER"

# Collect new password
print_status "Setting login password for '$ACTUAL_USER'."
printf "\n"

while true; do
    read_password "Enter new login password: " USER_PASSWORD
    read_password "Re-enter the password to confirm: " USER_PASSWORD_CONFIRM

    if [ "$USER_PASSWORD" = "$USER_PASSWORD_CONFIRM" ]; then
        unset USER_PASSWORD_CONFIRM
        break
    fi

    unset USER_PASSWORD USER_PASSWORD_CONFIRM
    print_error "Passwords do not match. Please try again."
    printf "\n"
done

# Update password
print_status "Updating login password for '$ACTUAL_USER'..."
if printf '%s\n%s\n' "$USER_PASSWORD" "$USER_PASSWORD" | passwd "$ACTUAL_USER" >/dev/null 2>&1; then
    unset USER_PASSWORD
    print_success "Login password updated successfully for '$ACTUAL_USER'."
else
    unset USER_PASSWORD
    print_error "Failed to update login password for '$ACTUAL_USER'."
    exit 1
fi
