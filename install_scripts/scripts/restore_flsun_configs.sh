#!/usr/bin/env bash
set -e

# ------------------------------------------------------------
#  STATUS HELPERS
# ------------------------------------------------------------
print_status()   { printf "\033[34m🔧 %s\033[0m\n" "$1"; }
print_success()  { printf "\033[32m✅ %s\033[0m\n" "$1"; }
print_warning()  { printf "\033[33m⚠️ %s\033[0m\n" "$1"; }
print_error()    { printf "\033[31m❌ %s\033[0m\n" "$1"; }

# ------------------------------------------------------------
#  PATHS
# ------------------------------------------------------------
ACTUAL_HOME="/home/pi"
PRINTER_CFG="$ACTUAL_HOME/printer_data/config/printer.cfg"
CONFIG_ROOT="$ACTUAL_HOME/printer_data/config"
TMP_DIR="/tmp/flsun_config_restore"

PRIMARY_ZIP_URL="https://github.com/Guilouz/Klipper-Flsun-Speeder-Pad/archive/refs/heads/main.zip"
PRIMARY_ZIP="$TMP_DIR/source.zip"
PRIMARY_UNZIP="$TMP_DIR/unpacked"

# ------------------------------------------------------------
#  CLEAN WORK DIR
# ------------------------------------------------------------
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# ------------------------------------------------------------
#  DETECT BOARD FROM KLIPPER (PRIMARY)
# ------------------------------------------------------------
detect_board_from_klipper() {
    if [ -S /tmp/klippy_uds ]; then
        MCU_INFO=$(echo -e '{"id": 123, "method": "info"}' | socat - /tmp/klippy_uds 2>/dev/null || true)
        CHIP=$(echo "$MCU_INFO" | grep -oE "stm32[f,h][0-9]+" | head -n1 || true)

        case "$CHIP" in
            stm32h743) echo "SKR 3.0"; return ;;
            stm32f407) echo "Robin Nano 3.0"; return ;;
            stm32f103) echo "Robin Nano 2.0"; return ;;
        esac
    fi
    echo ""
}

# ------------------------------------------------------------
#  DETECT BOARD FROM SERIAL (FALLBACK)
# ------------------------------------------------------------
detect_board_from_serial() {
    SERIAL=$(grep -i "serial:" "$PRINTER_CFG" | awk '{print $2}' || true)

    [[ "$SERIAL" == *"stm32h743"* ]] && echo "SKR 3.0" && return
    [[ "$SERIAL" == *"stm32f407"* ]] && echo "Robin Nano 3.0" && return
    [[ "$SERIAL" == *"stm32f103"* ]] && echo "Robin Nano 2.0" && return

    echo ""
}

# ------------------------------------------------------------
#  DOWNLOAD + UNPACK PRIMARY SOURCE
# ------------------------------------------------------------
print_status "Downloading Guilouz configuration ZIP..."
curl -L -o "$PRIMARY_ZIP" "$PRIMARY_ZIP_URL"
print_success "Downloaded."

print_status "Unpacking ZIP..."
unzip -q "$PRIMARY_ZIP" -d "$PRIMARY_UNZIP"
print_success "Unpacked."

# ------------------------------------------------------------
#  LOCATE FLSUN V400 FOLDER
# ------------------------------------------------------------
PRINTER_DIR=$(find "$PRIMARY_UNZIP" -type d -name "FLSUN V400" | head -n1)

if [ -z "$PRINTER_DIR" ]; then
    print_error "FLSUN V400 folder not found in source."
    exit 1
fi

# ------------------------------------------------------------
#  BUILD MANUFACTURER → BOARD → VARIANT MAP
# ------------------------------------------------------------
declare -A MANUFACTURERS
declare -A BOARDS_BY_MANUF
declare -A VARIANTS_BY_BOARD

while IFS= read -r folder; do
    base=$(basename "$folder")

    # Skip PNGs or files
    [ -d "$folder" ] || continue

    # Split: "BigTreeTech SKR 3.0 - Stock"
    MANUF=$(echo "$base" | awk '{print $1}')
    BOARD=$(echo "$base" | cut -d'-' -f1 | sed "s/$MANUF //;s/ *$//")
    VARIANT=$(echo "$base" | cut -d'-' -f2- | sed 's/^ //')

    MANUFACTURERS["$MANUF"]=1

    # Deduplicate boards
    if [[ ! "${BOARDS_BY_MANUF[$MANUF]}" =~ "$BOARD|" ]]; then
        BOARDS_BY_MANUF["$MANUF"]+="$BOARD|"
    fi

    VARIANTS_BY_BOARD["$BOARD"]+="$VARIANT|"

done < <(find "$PRINTER_DIR" -mindepth 1 -maxdepth 1 -type d)

# ------------------------------------------------------------
#  DETECT BOARD
# ------------------------------------------------------------
DETECTED_BOARD=$(detect_board_from_klipper)
[ -z "$DETECTED_BOARD" ] && DETECTED_BOARD=$(detect_board_from_serial)

# ------------------------------------------------------------
#  MAIN MENU LOOP (REBUILD ON BACK)
# ------------------------------------------------------------
while true; do

clear
print_status "Building configuration selection menu..."

echo "----------------------------------------"
if [ -n "$DETECTED_BOARD" ]; then
    DETECTED_VARIANT=$(grep -i "$DETECTED_BOARD" -R "$PRINTER_DIR" | grep -oE " - .*" | head -n1 | sed 's/ - //')
    echo "   Select configuration  (detected: $DETECTED_BOARD → $DETECTED_VARIANT)"
else
    echo "   Select configuration"
fi
echo "----------------------------------------"

INDEX=1
declare -A INDEX_TO_BOARD
declare -A INDEX_TO_VARIANT

for MANUF in "${!MANUFACTURERS[@]}"; do
    echo ""
    printf "\033[36m%s\033[0m\n" "$MANUF"

    IFS='|' read -ra BOARDS <<< "${BOARDS_BY_MANUF[$MANUF]}"
    for BOARD in "${BOARDS[@]}"; do
        [ -z "$BOARD" ] && continue

        echo "    $BOARD"

        IFS='|' read -ra VARS <<< "${VARIANTS_BY_BOARD[$BOARD]}"
        for VAR in "${VARS[@]}"; do
            [ -z "$VAR" ] && continue

            if [[ "$BOARD" == "$DETECTED_BOARD" && "$VAR" == "$DETECTED_VARIANT" ]]; then
                printf "        %d) %s     \033[32m<--- detected\033[0m\n" "$INDEX" "$VAR"
            else
                printf "        %d) %s\n" "$INDEX" "$VAR"
            fi

            INDEX_TO_BOARD[$INDEX]="$BOARD"
            INDEX_TO_VARIANT[$INDEX]="$VAR"
            ((INDEX++))
        done

        echo ""
    done
done

echo "----------------------------------------"
read -p "Enter your choice: " CHOICE

# Validate
if ! [[ "$CHOICE" =~ ^[0-9]+$ ]]; then
    print_error "Invalid selection."
    sleep 1
    continue
fi

SELECTED_BOARD="${INDEX_TO_BOARD[$CHOICE]}"
SELECTED_VARIANT="${INDEX_TO_VARIANT[$CHOICE]}"

if [ -z "$SELECTED_BOARD" ]; then
    print_error "Invalid selection."
    sleep 1
    continue
fi

# ------------------------------------------------------------
#  CONFIRMATION
# ------------------------------------------------------------
echo ""
echo "You selected: $SELECTED_BOARD → $SELECTED_VARIANT"
read -p "Are you sure? (Y/n/b): " CONFIRM

case "$CONFIRM" in
    ""|"Y"|"y")
        break
        ;;
    "n"|"N")
        continue
        ;;
    "b"|"B")
        continue
        ;;
    *)
        continue
        ;;
esac

done

# ------------------------------------------------------------
#  COPY CONFIG FILES
# ------------------------------------------------------------
SOURCE_FOLDER="$PRINTER_DIR/$SELECTED_BOARD - $SELECTED_VARIANT"

print_status "Copying configuration files..."
cp -r "$SOURCE_FOLDER/"* "$CONFIG_ROOT/"
print_success "Configuration files copied."

# ------------------------------------------------------------
#  FIX PERMISSIONS + RESTART
# ------------------------------------------------------------
print_status "Fixing permissions..."
sudo chown -R pi:pi "$CONFIG_ROOT"
sudo chmod -R 775 "$CONFIG_ROOT"
print_success "Permissions fixed."

print_status "Restarting Klipper services..."
sudo systemctl restart klipper
sudo systemctl restart moonraker
print_success "Services restarted."

print_success "FLSUN configuration restore completed successfully!"
echo ""
read -p "Press Enter to continue..."
