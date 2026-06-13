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
print_header "Update User Credentials"
printf "\nCurrent user: \033[33m%s\033[0m\n\n" "$ACTUAL_USER"
printf "What would you like to do?\n"
printf "  1) Change password only  (keep username '%s')\n" "$ACTUAL_USER"
printf "  2) Rename user + set password  (replaces default username)\n"
printf "  3) Skip\n\n"
read -rp "Enter 1, 2 or 3: " USER_CHOICE </dev/tty
printf "\n"

case "$USER_CHOICE" in
    1)
        TARGET_USER="$ACTUAL_USER"
        NEW_USERNAME=""
        ;;
    2)
        while true; do
            read -rp "Enter new username (to replace '$ACTUAL_USER'): " NEW_USERNAME </dev/tty
            printf "\n"
            if [[ -z "$NEW_USERNAME" ]]; then
                print_error "Username cannot be empty."
                continue
            fi
            if [[ ! "$NEW_USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
                print_error "Invalid username. Use lowercase letters, digits, hyphens, underscores; must start with a letter or underscore."
                continue
            fi
            if id "$NEW_USERNAME" &>/dev/null; then
                print_error "Username '$NEW_USERNAME' already exists. Choose a different name."
                continue
            fi
            break
        done
        TARGET_USER="$ACTUAL_USER"
        ;;
    3)
        print_status "Skipping user credentials update."
        exit 0
        ;;
    *)
        print_error "Invalid choice. Please run the script again and enter 1, 2 or 3."
        exit 1
        ;;
esac

# --- Collect new password ---
print_status "Setting login password for '${NEW_USERNAME:-$TARGET_USER}'."
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

# --- Rename user if requested ---
if [[ -n "$NEW_USERNAME" ]]; then
    print_status "Renaming user '$ACTUAL_USER' → '$NEW_USERNAME'..."
    print_warning "The user is currently logged in. Renaming will take effect on next login."

    # Rename the login name
    usermod -l "$NEW_USERNAME" "$ACTUAL_USER"

    # Rename primary group if it matches the old username
    if getent group "$ACTUAL_USER" &>/dev/null; then
        groupmod -n "$NEW_USERNAME" "$ACTUAL_USER"
    fi

    # Move home directory
    if [[ -d "/home/$ACTUAL_USER" ]]; then
        usermod -d "/home/$NEW_USERNAME" -m "$NEW_USERNAME"
        print_success "Home directory moved to /home/$NEW_USERNAME"
    fi

    TARGET_USER="$NEW_USERNAME"
    print_success "User renamed to '$NEW_USERNAME'."
    printf "\n"
fi

# --- Set password ---
print_status "Updating login password for '$TARGET_USER'..."
if printf '%s\n%s\n' "$USER_PASSWORD" "$USER_PASSWORD" | passwd "$TARGET_USER" >/dev/null 2>&1; then
    unset USER_PASSWORD
    print_success "Login password updated successfully for '$TARGET_USER'."
else
    unset USER_PASSWORD
    print_error "Failed to update login password."
    exit 1
fi
