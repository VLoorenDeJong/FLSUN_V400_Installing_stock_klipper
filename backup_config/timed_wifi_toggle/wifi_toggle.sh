#!/bin/bash
set -e

# Detect actual user and home (sudo-safe)
if [ -n "${SUDO_USER:-}" ]; then
    ACTUAL_USER="$SUDO_USER"
else
    ACTUAL_USER="$(whoami)"
fi

# ==========================
# CONFIGURATION
# ==========================
SLEEP_TIME=0.250                     # Sleep time in seconds (supports milliseconds)
MAX_LINES=1000
BASE_NAME="wifi-toggle"

# Timestamp formats (modifiable)
TS_FORMAT="%Y_%m_%d_%H-%M"           # Example: 2026_06_27_16-15
DAILY_FORMAT="%Y_%m_%d"              # Example: 2026_06_27

# ==========================
# LOG DIRECTORY (system-wide)
# ==========================
LOG_DIR="/var/log/timed_wifi_toggle"

# Auto-create log folder if missing
if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR"
    chown "$ACTUAL_USER:$ACTUAL_USER" "$LOG_DIR"
fi

# ==========================
# CURRENT DAILY LOG FILE
# ==========================
TODAY=$(date +"$DAILY_FORMAT")
LOGFILE="$LOG_DIR/${TODAY}_${BASE_NAME}.log"

# Ensure log file exists
if [ ! -f "$LOGFILE" ]; then
    touch "$LOGFILE"
fi

# ==========================
# ROLLOVER CHECK
# ==========================
LINE_COUNT=$(wc -l < "$LOGFILE")
if [ "$LINE_COUNT" -ge "$MAX_LINES" ]; then
    TS=$(date +"$TS_FORMAT")
    mv "$LOGFILE" "$LOG_DIR/${TS}_${BASE_NAME}.log"
    touch "$LOGFILE"
fi

# ==========================
# LOG START
# ==========================
echo "[$(date)] WiFi toggle script started" >> "$LOGFILE"

# ==========================
# DISABLE WIFI
# ==========================
echo "[$(date)] Disabling WiFi..." >> "$LOGFILE"
nmcli radio wifi off || echo "[$(date)] WARNING: 'nmcli radio wifi off' failed" >> "$LOGFILE"

# ==========================
# WAIT
# ==========================
echo "[$(date)] Sleeping for $SLEEP_TIME seconds..." >> "$LOGFILE"
sleep "$SLEEP_TIME"

# ==========================
# ENABLE WIFI
# ==========================
echo "[$(date)] Enabling WiFi..." >> "$LOGFILE"
nmcli radio wifi on || echo "[$(date)] WARNING: 'nmcli radio wifi on' failed" >> "$LOGFILE"

# ==========================
# VERIFY RECONNECTION
# ==========================
# Poll for up to 15s instead of assuming "radio on" means "back online" -
# reassociation + DHCP takes longer than the 250ms gap above, especially
# on the flaky connections this toggle exists to work around.
RECONNECT_TIMEOUT=15
STATE="unknown"
RECONNECTED=0
echo "[$(date)] Verifying reconnection (up to ${RECONNECT_TIMEOUT}s)..." >> "$LOGFILE"
for _ in $(seq 1 "$RECONNECT_TIMEOUT"); do
    STATE=$(nmcli -t -f STATE general status 2>/dev/null || echo "unknown")
    if [ "$STATE" = "connected" ]; then
        RECONNECTED=1
        break
    fi
    sleep 1
done

# ==========================
# LOG END
# ==========================
if [ "$RECONNECTED" -eq 1 ]; then
    echo "[$(date)] WiFi toggle script finished — reconnected (state: connected)" >> "$LOGFILE"
    exit 0
else
    echo "[$(date)] ALERT: WiFi toggle script finished but did NOT reconnect within ${RECONNECT_TIMEOUT}s (last state: $STATE)" >> "$LOGFILE"
    exit 1
fi
