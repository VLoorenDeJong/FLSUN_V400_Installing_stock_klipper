#!/bin/bash
set -e

# Configure timezone and Wi-Fi regulatory domain.
# Usage:
#   sudo ./configure_locale_and_wifi_country.sh [TIMEZONE] [COUNTRY_CODE]
# Example:
#   sudo ./configure_locale_and_wifi_country.sh Europe/Amsterdam NL

TIMEZONE="${1:-Europe/Amsterdam}"
COUNTRY_CODE_RAW="${2:-NL}"
COUNTRY_CODE="$(printf '%s' "$COUNTRY_CODE_RAW" | tr '[:lower:]' '[:upper:]')"
FORCE_RUN="${FORCE_RUN_LOCALE_WIFI:-0}"

if [ "$(id -u)" -ne 0 ]; then
    echo -e "\e[31m❌ Please run as root (use sudo).\e[0m"
    exit 1
fi

if ! command -v timedatectl >/dev/null 2>&1; then
    echo -e "\e[31m❌ timedatectl is not available on this system.\e[0m"
    exit 1
fi

if ! command -v iw >/dev/null 2>&1; then
    echo -e "\e[31m❌ iw command is not installed. Install package: iw\e[0m"
    exit 1
fi

IW_BIN="$(command -v iw)"

if ! timedatectl list-timezones | grep -Fxq "$TIMEZONE"; then
    echo -e "\e[31m❌ Invalid timezone: $TIMEZONE\e[0m"
    echo -e "\e[33m💡 Example valid value: Europe/Amsterdam\e[0m"
    exit 1
fi

if ! printf '%s' "$COUNTRY_CODE" | grep -Eq '^[A-Z]{2}$'; then
    echo -e "\e[31m❌ Country code must be 2 letters (ISO-3166-1 alpha-2), got: $COUNTRY_CODE\e[0m"
    exit 1
fi

CURRENT_TIMEZONE="$(timedatectl show -p Timezone --value 2>/dev/null || true)"
CURRENT_COUNTRY_CODE="$($IW_BIN reg get 2>/dev/null | awk '/^country /{code=$2; sub(":", "", code); print toupper(code); exit}')"

if [ "$FORCE_RUN" != "1" ] && [ "$CURRENT_TIMEZONE" = "$TIMEZONE" ] && [ "$CURRENT_COUNTRY_CODE" = "$COUNTRY_CODE" ]; then
    echo -e "\e[33m⚠️ Timezone and Wi-Fi country already configured ($TIMEZONE / $COUNTRY_CODE). Skipping.\e[0m"
    echo -e "\e[33m💡 To force rerun: FORCE_RUN_LOCALE_WIFI=1 sudo bash $0 $TIMEZONE $COUNTRY_CODE\e[0m"
    exit 0
fi

echo -e "\e[34m🔧 Setting timezone to $TIMEZONE\e[0m"
timedatectl set-timezone "$TIMEZONE"

echo -e "\e[34m🔧 Enabling NTP time sync\e[0m"
timedatectl set-ntp true || true

echo -e "\e[34m🔧 Applying Wi-Fi regulatory domain to $COUNTRY_CODE\e[0m"
iw reg set "$COUNTRY_CODE"

echo -e "\e[34m🔧 Persisting Wi-Fi country across reboots\e[0m"

# Prefer /etc/default/crda when present (legacy systems), else set cfg80211 option.
if [ -f /etc/default/crda ]; then
    if grep -q '^REGDOMAIN=' /etc/default/crda; then
        sed -i "s/^REGDOMAIN=.*/REGDOMAIN=${COUNTRY_CODE}/" /etc/default/crda
    else
        echo "REGDOMAIN=${COUNTRY_CODE}" >> /etc/default/crda
    fi
else
    mkdir -p /etc/modprobe.d
    printf 'options cfg80211 ieee80211_regdom=%s\n' "$COUNTRY_CODE" > /etc/modprobe.d/cfg80211-regdom.conf
fi

# Use a systemd one-shot service instead of editing rc.local.
if command -v systemctl >/dev/null 2>&1; then
    cat > /etc/systemd/system/set-wifi-regdom.service <<EOF
[Unit]
Description=Set Wi-Fi regulatory domain
After=network-pre.target
Before=network.target

[Service]
Type=oneshot
ExecStart=${IW_BIN} reg set ${COUNTRY_CODE}
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable set-wifi-regdom.service >/dev/null 2>&1
    systemctl start set-wifi-regdom.service || true
else
    echo -e "\e[33m⚠️ systemctl not available; persistent Wi-Fi country setup service was not created.\e[0m"
fi

echo -e "\e[34m📋 Current time and timezone status:\e[0m"
timedatectl | sed -n '1,8p'

echo -e "\e[34m📋 Current Wi-Fi regulatory domain:\e[0m"
iw reg get | sed -n '1,8p'

echo -e "\e[32m✅ Timezone and Wi-Fi country configuration complete\e[0m"
echo -e "\e[33m💡 If your network stack does not pick this up immediately, reboot once.\e[0m"
