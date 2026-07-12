#!/bin/bash
set -e

# Configure timezone and Wi-Fi regulatory domain.
# Usage:
#   sudo ./configure_locale_and_wifi_country.sh [TIMEZONE] [COUNTRY_CODE]
# Example:
#   sudo ./configure_locale_and_wifi_country.sh Europe/Amsterdam NL
# Omit either argument to be prompted for it interactively instead.

print_status()  { printf "\033[34m🔧 %s\033[0m\n" "$1"; }
print_success() { printf "\033[32m✅ %s\033[0m\n" "$1"; }
print_warning() { printf "\033[33m⚠️  %s\033[0m\n" "$1"; }
print_error()   { printf "\033[31m❌ %s\033[0m\n" "$1"; }

if [ "$(id -u)" -ne 0 ]; then
    print_error "Please run as root (use sudo)."
    exit 1
fi

if ! command -v timedatectl >/dev/null 2>&1; then
    print_error "timedatectl is not available on this system."
    exit 1
fi

# --- Timezone: from CLI arg if given, otherwise DERIVED from the country below ---
# Interactive mode does NOT ask for a timezone separately — the country you pick
# determines it (e.g. NL -> Europe/Amsterdam). See the derivation right after the
# country prompt. CLI arg $1 still lets you force a specific zone.
# NOTE: interactive reads pull from /dev/tty, not stdin (start_install.sh
# redirects child stdin and may have buffered input).
valid_timezone() { timedatectl list-timezones 2>/dev/null | grep -Fxq "$1"; }

# Emit the IANA timezone(s) for an ISO-3166-1 country code, from the tzdata
# country table. Handles both zone1970.tab (codes are comma-joined) and the
# legacy zone.tab (one code per row).
zones_for_country() {
    local cc="$1" tab
    for tab in /usr/share/zoneinfo/zone1970.tab /usr/share/zoneinfo/zone.tab; do
        [ -f "$tab" ] || continue
        awk -F'\t' -v cc="$cc" '
            /^#/ { next }
            { n = split($1, a, ","); for (i=1;i<=n;i++) if (a[i]==cc) { print $3; break } }
        ' "$tab"
        return 0
    done
}

if [ -n "${1:-}" ]; then
    TIMEZONE="$1"
    if ! valid_timezone "$TIMEZONE"; then
        print_error "Invalid timezone: $TIMEZONE"
        print_warning "Example valid value: Europe/Amsterdam"
        exit 1
    fi
else
    TIMEZONE=""   # derived from the chosen country code after the country prompt
fi

# --- ISO-3166-1 alpha-2 country/territory table: "CODE:Name" ---
COUNTRY_TABLE="
AF:Afghanistan
AX:Aland Islands
AL:Albania
DZ:Algeria
AS:American Samoa
AD:Andorra
AO:Angola
AI:Anguilla
AQ:Antarctica
AG:Antigua and Barbuda
AR:Argentina
AM:Armenia
AW:Aruba
AU:Australia
AT:Austria
AZ:Azerbaijan
BS:Bahamas
BH:Bahrain
BD:Bangladesh
BB:Barbados
BY:Belarus
BE:Belgium
BZ:Belize
BJ:Benin
BM:Bermuda
BT:Bhutan
BO:Bolivia
BQ:Bonaire, Sint Eustatius and Saba
BA:Bosnia and Herzegovina
BW:Botswana
BV:Bouvet Island
BR:Brazil
IO:British Indian Ocean Territory
BN:Brunei Darussalam
BG:Bulgaria
BF:Burkina Faso
BI:Burundi
CV:Cabo Verde
KH:Cambodia
CM:Cameroon
CA:Canada
KY:Cayman Islands
CF:Central African Republic
TD:Chad
CL:Chile
CN:China
CX:Christmas Island
CC:Cocos (Keeling) Islands
CO:Colombia
KM:Comoros
CG:Congo
CD:Congo, Democratic Republic of the
CK:Cook Islands
CR:Costa Rica
CI:Cote d'Ivoire
HR:Croatia
CU:Cuba
CW:Curacao
CY:Cyprus
CZ:Czechia
DK:Denmark
DJ:Djibouti
DM:Dominica
DO:Dominican Republic
EC:Ecuador
EG:Egypt
SV:El Salvador
GQ:Equatorial Guinea
ER:Eritrea
EE:Estonia
SZ:Eswatini
ET:Ethiopia
FK:Falkland Islands
FO:Faroe Islands
FJ:Fiji
FI:Finland
FR:France
GF:French Guiana
PF:French Polynesia
TF:French Southern Territories
GA:Gabon
GM:Gambia
GE:Georgia
DE:Germany
GH:Ghana
GI:Gibraltar
GR:Greece
GL:Greenland
GD:Grenada
GP:Guadeloupe
GU:Guam
GT:Guatemala
GG:Guernsey
GN:Guinea
GW:Guinea-Bissau
GY:Guyana
HT:Haiti
HM:Heard Island and McDonald Islands
VA:Holy See
HN:Honduras
HK:Hong Kong
HU:Hungary
IS:Iceland
IN:India
ID:Indonesia
IR:Iran
IQ:Iraq
IE:Ireland
IM:Isle of Man
IL:Israel
IT:Italy
JM:Jamaica
JP:Japan
JE:Jersey
JO:Jordan
KZ:Kazakhstan
KE:Kenya
KI:Kiribati
KP:Korea, North
KR:Korea, South
KW:Kuwait
KG:Kyrgyzstan
LA:Laos
LV:Latvia
LB:Lebanon
LS:Lesotho
LR:Liberia
LY:Libya
LI:Liechtenstein
LT:Lithuania
LU:Luxembourg
MO:Macao
MG:Madagascar
MW:Malawi
MY:Malaysia
MV:Maldives
ML:Mali
MT:Malta
MH:Marshall Islands
MQ:Martinique
MR:Mauritania
MU:Mauritius
YT:Mayotte
MX:Mexico
FM:Micronesia
MD:Moldova
MC:Monaco
MN:Mongolia
ME:Montenegro
MS:Montserrat
MA:Morocco
MZ:Mozambique
MM:Myanmar
NA:Namibia
NR:Nauru
NP:Nepal
NL:Netherlands
NC:New Caledonia
NZ:New Zealand
NI:Nicaragua
NE:Niger
NG:Nigeria
NU:Niue
NF:Norfolk Island
MK:North Macedonia
MP:Northern Mariana Islands
NO:Norway
OM:Oman
PK:Pakistan
PW:Palau
PS:Palestine
PA:Panama
PG:Papua New Guinea
PY:Paraguay
PE:Peru
PH:Philippines
PN:Pitcairn
PL:Poland
PT:Portugal
PR:Puerto Rico
QA:Qatar
RE:Reunion
RO:Romania
RU:Russian Federation
RW:Rwanda
BL:Saint Barthelemy
SH:Saint Helena, Ascension and Tristan da Cunha
KN:Saint Kitts and Nevis
LC:Saint Lucia
MF:Saint Martin
PM:Saint Pierre and Miquelon
VC:Saint Vincent and the Grenadines
WS:Samoa
SM:San Marino
ST:Sao Tome and Principe
SA:Saudi Arabia
SN:Senegal
RS:Serbia
SC:Seychelles
SL:Sierra Leone
SG:Singapore
SX:Sint Maarten
SK:Slovakia
SI:Slovenia
SB:Solomon Islands
SO:Somalia
ZA:South Africa
GS:South Georgia and the South Sandwich Islands
SS:South Sudan
ES:Spain
LK:Sri Lanka
SD:Sudan
SR:Suriname
SJ:Svalbard and Jan Mayen
SE:Sweden
CH:Switzerland
SY:Syrian Arab Republic
TW:Taiwan
TJ:Tajikistan
TZ:Tanzania
TH:Thailand
TL:Timor-Leste
TG:Togo
TK:Tokelau
TO:Tonga
TT:Trinidad and Tobago
TN:Tunisia
TR:Turkey
TM:Turkmenistan
TC:Turks and Caicos Islands
TV:Tuvalu
UG:Uganda
UA:Ukraine
AE:United Arab Emirates
GB:United Kingdom
US:United States of America
UM:United States Minor Outlying Islands
UY:Uruguay
UZ:Uzbekistan
VU:Vanuatu
VE:Venezuela
VN:Viet Nam
VG:Virgin Islands (British)
VI:Virgin Islands (U.S.)
WF:Wallis and Futuna
EH:Western Sahara
YE:Yemen
ZM:Zambia
ZW:Zimbabwe
"

# --- Determine Wi-Fi country code: CLI arg if given, otherwise search-and-pick prompt ---
if [ -n "${2:-}" ]; then
    COUNTRY_CODE_RAW="$2"
else
    while true; do
        read -rp "Enter your country name or 2-letter code (e.g. 'germany', 'DE') [default: NL]: " CC_QUERY </dev/tty
        CC_QUERY="${CC_QUERY:-NL}"
        CC_QUERY_UPPER="$(printf '%s' "$CC_QUERY" | tr '[:lower:]' '[:upper:]')"

        # Fast path: exact 2-letter code that exists in the table
        if printf '%s' "$CC_QUERY_UPPER" | grep -Eq '^[A-Z]{2}$' && \
           printf '%s\n' "$COUNTRY_TABLE" | grep -qi "^${CC_QUERY_UPPER}:"; then
            COUNTRY_CODE_RAW="$CC_QUERY_UPPER"
            break
        fi

        # Otherwise, search by (partial) country name
        mapfile -t MATCHES < <(printf '%s\n' "$COUNTRY_TABLE" | grep -i "$CC_QUERY" | grep -v '^$')

        if [ "${#MATCHES[@]}" -eq 0 ]; then
            print_warning "No country matched '$CC_QUERY'. Try part of the name (e.g. 'united') or a 2-letter code."
            continue
        fi

        if [ "${#MATCHES[@]}" -eq 1 ]; then
            COUNTRY_CODE_RAW="${MATCHES[0]%%:*}"
            print_status "Matched: ${MATCHES[0]#*:} (${COUNTRY_CODE_RAW})"
            break
        fi

        echo "Multiple matches for '$CC_QUERY':"
        for i in "${!MATCHES[@]}"; do
            printf "  %2d) %s (%s)\n" "$((i+1))" "${MATCHES[$i]#*:}" "${MATCHES[$i]%%:*}"
        done
        read -rp "Pick a number (or press Enter to search again): " PICK </dev/tty
        if [[ "$PICK" =~ ^[0-9]+$ ]] && [ "$PICK" -ge 1 ] && [ "$PICK" -le "${#MATCHES[@]}" ]; then
            COUNTRY_CODE_RAW="${MATCHES[$((PICK-1))]%%:*}"
            break
        fi
        print_warning "No selection made — search again."
    done
fi
COUNTRY_CODE="$(printf '%s' "$COUNTRY_CODE_RAW" | tr '[:lower:]' '[:upper:]')"
FORCE_RUN="${FORCE_RUN_LOCALE_WIFI:-0}"

if ! command -v iw >/dev/null 2>&1; then
    print_warning "iw not found. Installing..."
    apt-get update -qq >/dev/null 2>&1
    apt-get install -y -qq iw >/dev/null 2>&1
    if ! command -v iw >/dev/null 2>&1; then
        print_error "Failed to install iw. Cannot configure Wi-Fi country."
        exit 1
    fi
    print_success "iw installed"
fi

IW_BIN="$(command -v iw)"

if ! printf '%s' "$COUNTRY_CODE" | grep -Eq '^[A-Z]{2}$'; then
    print_error "Country code must be 2 letters (ISO-3166-1 alpha-2), got: $COUNTRY_CODE"
    exit 1
fi

# --- Derive the timezone from the chosen country (interactive mode) ---
# TIMEZONE is empty unless a CLI arg forced it. Look up the country's zone(s):
# one zone -> use it silently; several -> let the user pick; none -> ask manually.
if [ -z "$TIMEZONE" ]; then
    mapfile -t TZ_ZONES < <(zones_for_country "$COUNTRY_CODE" | awk 'NF')
    if [ "${#TZ_ZONES[@]}" -eq 1 ]; then
        TIMEZONE="${TZ_ZONES[0]}"
        print_success "Timezone for $COUNTRY_CODE: $TIMEZONE"
    elif [ "${#TZ_ZONES[@]}" -gt 1 ]; then
        echo "$COUNTRY_CODE spans multiple timezones — pick yours:"
        for i in "${!TZ_ZONES[@]}"; do
            printf "  %2d) %s\n" "$((i+1))" "${TZ_ZONES[$i]}"
        done
        read -rp "Timezone number [default 1]: " TZ_PICK </dev/tty
        TZ_PICK="${TZ_PICK:-1}"
        if [[ "$TZ_PICK" =~ ^[0-9]+$ ]] && [ "$TZ_PICK" -ge 1 ] && [ "$TZ_PICK" -le "${#TZ_ZONES[@]}" ]; then
            TIMEZONE="${TZ_ZONES[$((TZ_PICK-1))]}"
        else
            TIMEZONE="${TZ_ZONES[0]}"
        fi
        print_success "Timezone: $TIMEZONE"
    else
        print_warning "No timezone mapping found for $COUNTRY_CODE — enter it manually."
        while true; do
            read -rp "Enter your timezone (e.g. Europe/Amsterdam) [default: Europe/Amsterdam]: " TZ_INPUT </dev/tty
            TIMEZONE="${TZ_INPUT:-Europe/Amsterdam}"
            valid_timezone "$TIMEZONE" && break
            print_warning "'$TIMEZONE' is not a valid timezone — try e.g. Europe/Amsterdam."
        done
    fi
fi

CURRENT_TIMEZONE="$(timedatectl show -p Timezone --value 2>/dev/null || true)"
CURRENT_COUNTRY_CODE="$($IW_BIN reg get 2>/dev/null | awk '/^country /{code=$2; sub(":", "", code); print toupper(code); exit}')"

if [ "$FORCE_RUN" != "1" ] && [ "$CURRENT_TIMEZONE" = "$TIMEZONE" ] && [ "$CURRENT_COUNTRY_CODE" = "$COUNTRY_CODE" ]; then
    print_warning "Timezone and Wi-Fi country already configured ($TIMEZONE / $COUNTRY_CODE). Skipping."
    print_warning "To force rerun: FORCE_RUN_LOCALE_WIFI=1 sudo bash $0 $TIMEZONE $COUNTRY_CODE"
    exit 0
fi

print_status "Setting timezone to $TIMEZONE"
timedatectl set-timezone "$TIMEZONE"

print_status "Enabling NTP time sync"
timedatectl set-ntp true || true

print_status "Applying Wi-Fi regulatory domain to $COUNTRY_CODE"
iw reg set "$COUNTRY_CODE"

print_status "Persisting Wi-Fi country across reboots"

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
    print_warning "systemctl not available; persistent Wi-Fi country setup service was not created."
fi

print_status "Current time and timezone status:"
timedatectl | sed -n '1,8p'

print_status "Current Wi-Fi regulatory domain:"
iw reg get | sed -n '1,8p'

print_success "Timezone and Wi-Fi country configuration complete"
print_warning "If your network stack does not pick this up immediately, reboot once."
