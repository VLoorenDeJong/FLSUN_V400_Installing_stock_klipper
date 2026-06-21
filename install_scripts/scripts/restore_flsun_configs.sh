#!/usr/bin/env bash
set -e

# ------------------------------------------------------------
#  STATUS HELPERS
# ------------------------------------------------------------
print_status()   { printf "\033[34m🔧 %s\033[0m\n" "$1"; }
print_success()  { printf "\033[32m✅ %s\033[0m\n" "$1"; }
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
declare -A FULL_FOLDER_NAME

while IFS= read -r folder; do
  base=$(basename "$folder")

  # Skip PNGs or files
  [ -d "$folder" ] || continue

  # Split on FIRST " - "
  MANUF=$(echo "$base" | awk '{print $1}')
  REST=$(echo "$base" | sed "s/^$MANUF //")

  BOARD=$(echo "$REST" | cut -d'-' -f1 | sed 's/ *$//')
  VARIANT=$(echo "$REST" | cut -d'-' -f2- | sed 's/^ //')

  MANUFACTURERS["$MANUF"]=1

  # Deduplicate boards
  if [[ ! "${BOARDS_BY_MANUF[$MANUF]}" =~ "$BOARD|" ]]; then
    BOARDS_BY_MANUF["$MANUF"]+="$BOARD|"
  fi

  VARIANTS_BY_BOARD["$BOARD"]+="$VARIANT|"

  # Store full folder name for copying
  FULL_FOLDER_NAME["$MANUF|$BOARD|$VARIANT"]="$base"

done < <(find "$PRINTER_DIR" -mindepth 1 -maxdepth 1 -type d)

# ------------------------------------------------------------
#  MAIN MENU LOOP (REBUILD ON BACK)
# ------------------------------------------------------------
while true; do

clear
print_status "Building configuration selection menu..."

echo "----------------------------------------"
echo "  Select configuration"
echo "----------------------------------------"

INDEX=1
declare -A INDEX_TO_MANUF
declare -A INDEX_TO_BOARD
declare -A INDEX_TO_VARIANT

for MANUF in "${!MANUFACTURERS[@]}"; do
  echo ""
  printf "\033[36m%s\033[0m\n" "$MANUF"

  IFS='|' read -ra BOARDS <<< "${BOARDS_BY_MANUF[$MANUF]}"
  for BOARD in "${BOARDS[@]}"; do
    [ -z "$BOARD" ] && continue

    echo "  $BOARD"

    IFS='|' read -ra VARS <<< "${VARIANTS_BY_BOARD[$BOARD]}"
    for VAR in "${VARS[@]}"; do
      [ -z "$VAR" ] && continue

      printf "    %d) %s\n" "$INDEX" "$VAR"

      INDEX_TO_MANUF[$INDEX]="$MANUF"
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

SELECTED_MANUF="${INDEX_TO_MANUF[$CHOICE]}"
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
echo "You selected: $SELECTED_MANUF $SELECTED_BOARD → $SELECTED_VARIANT"
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
FOLDER_NAME="${FULL_FOLDER_NAME["$SELECTED_MANUF|$SELECTED_BOARD|$SELECTED_VARIANT"]}"
SOURCE_FOLDER="$PRINTER_DIR/$FOLDER_NAME"

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
