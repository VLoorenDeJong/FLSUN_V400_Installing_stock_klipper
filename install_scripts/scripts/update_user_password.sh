#!/usr/bin/env bash
set -e

# --- User detection ---
if [ -n "$SUDO_USER" ]; then
    ACTUAL_USER="$SUDO_USER"
else
    ACTUAL_USER=$(whoami)
fi

# --- Inline utility functions ---
print_status()  { printf "\033[34m🔧 %s\033[0m\n" "$1"; }
print_success() { printf "\033[32m✅ %s\033[0m\n" "$1"; }
print_warning() { printf "\033[33m⚠️  %s\033[0m\n" "$1"; }
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
        if [[ -z "$char" ]]; then
            # Enter key pressed
            break
        elif [[ "$char" == $'\x7f' || "$char" == $'\b' ]]; then
            # Backspace — remove last character
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
printf "\nWhich user's password do you want to change?\n"
printf "  1) Current user (%s)\n" "$ACTUAL_USER"
printf "  2) A different user\n\n"
read -rp "Enter 1 or 2: " USER_CHOICE
printf "\n"

case "$USER_CHOICE" in
    1)
        TARGET_USER="$ACTUAL_USER"
        ;;
    2)
        read -rp "Enter the username to update: " TARGET_USER
        printf "\n"
        if ! id "$TARGET_USER" &>/dev/null; then
            print_error "User '$TARGET_USER' does not exist on this system."
            exit 1
        fi
        ;;
    *)
        print_error "Invalid choice. Please run the script again and enter 1 or 2."
        exit 1
        ;;
esac

print_status "Changing login password for '$TARGET_USER'. This is the password used to log in to this server (e.g. via SSH or the console)."
printf "\n"

read_password "Enter new login password for '$TARGET_USER': " USER_PASSWORD
read_password "Re-enter the password to confirm: " USER_PASSWORD_CONFIRM

if [ "$USER_PASSWORD" != "$USER_PASSWORD_CONFIRM" ]; then
    unset USER_PASSWORD USER_PASSWORD_CONFIRM
    print_error "Passwords do not match. Please run the script again."
    exit 1
fi

unset USER_PASSWORD_CONFIRM

print_status "Updating login password..."
if printf '%s\n%s\n' "$USER_PASSWORD" "$USER_PASSWORD" | sudo passwd "$TARGET_USER" >/dev/null 2>&1; then
    unset USER_PASSWORD
    print_success "Login password updated successfully for '$TARGET_USER'."
else
    unset USER_PASSWORD
    print_error "Failed to update login password."
    exit 1
fi
