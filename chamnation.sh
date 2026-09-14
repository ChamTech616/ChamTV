#!/bin/bash

# ==========================================
# CHAMNATION TV CLIENT v1.0
# ==========================================

LOG="/home/$HOST/chamnation.log"

exec >> "$LOG" 2>&1

echo "========== START $(date) =========="

DB="https://chaminadetv-86055-default-rtdb.firebaseio.com"
CHANNEL="UCP4CuIbDHok4YsEsIUz5utw"

HOST=$(hostname)
USER=$(whoami)

LAST_PREVIEW=0

YOUTUBE="http://youtube.com/channel/UCP4CuIbDHok4YsEsIUz5utw/live"

upload_log () {

    LOGFILE="/home/$USER/chamnation.log"

    [ ! -f "$LOGFILE" ] && return

    LOG_B64=$(base64 -w 0 "$LOGFILE")
    TIME=$(date +%s)

    curl -s -X PATCH \
      "$DB/displays/$HOST.json" \
      -H "Content-Type: application/json" \
      -d "{
        \"log\":\"$LOG_B64\",
        \"logTime\":$TIME
      }" >/dev/null
}

update_client () {
    REPO="https://raw.githubusercontent.com/ChamTech616/ChamTV/main/chamnation.sh"
    TEMP="/tmp/chamnation.sh"
    DEST="/home/$USER/chamnation.sh"

    echo "Downloading latest version..."

    curl -L "$REPO" -o "$TEMP"

    # Make sure download succeeded
    if [ ! -s "$TEMP" ]; then
        echo "Update failed."
        return
    fi

    echo "Installing..."

    mv "$TEMP" "$DEST"

    chmod +x "$DEST"

    echo "Rebooting..."
    sleep 3

    sudo /usr/sbin/reboot
}

take_screenshot () {

    export DISPLAY=:0
    export XAUTHORITY="/home/$USER/.Xauthority"

    FILE="/tmp/$USER.jpg"

    # Remove the previous image
    rm -f "$FILE"

    # Take a new screenshot
    scrot -q 35 "$FILE"
    RESULT=$?

    if [ $RESULT -ne 0 ]; then
        echo "SCROT FAILED ($RESULT)"
        return
    fi

    # Verify the file was actually created
    if [ ! -f "$FILE" ]; then
        echo "Screenshot file missing"
        return
    fi

    echo "Created: $(stat -c %y "$FILE")"

    IMAGE=$(base64 -w 0 "$FILE")
    TIME=$(date +%s)

    curl -s -X PATCH \
      "$DB/displays/$HOST.json" \
      -H "Content-Type: application/json" \
      -d "{
        \"screenshot\":\"$IMAGE\",
        \"screenshotTime\":$TIME
      }" >/dev/null
}

launch_stream () {
    pkill chromium 2>/dev/null
    sleep 2
    chromium-browser \
        --kiosk \
        --start-fullscreen \
        --autoplay-policy=no-user-gesture-required \
        "$YOUTUBE" &
}

heartbeat () {
    IP=$(hostname -I | awk '{print $1}')
    LAST=$(date +%s)
    UPTIME=$(cut -d. -f1 /proc/uptime)
    curl -s -X PATCH \
    "$DB/displays/$HOST.json" \
    -d "{
        \"hostname\":\"$HOST\",
        \"username\":\"$USER\",
        \"ip\":\"$IP\",
        \"status\":\"online\",
        \"uptime\":$UPTIME,
        \"lastSeen\":$LAST,
        \"version\":\"v1.4.1\"
    }" >/dev/null
}

check_commands () {
    CMD=$(curl -s "$DB/commands/$HOST.json")
    RESTART=$(echo "$CMD" | jq -r '.restart // false')
    REBOOT=$(echo "$CMD" | jq -r '.reboot // false')
    SHUTDOWN=$(echo "$CMD" | jq -r '.shutdown // false')
    UPDATE=$(echo "$CMD" | jq -r '.update // false')
    if [ "$RESTART" = "true" ]; then
        echo "Restart command received."
        curl -s -X PATCH \
        "$DB/commands/$HOST.json" \
        -d '{"restart":false}' >/dev/null
        launch_stream
    fi

    if [ "$REBOOT" = "true" ]; then
        echo "Reboot command received."
        curl -s -X PATCH \
        "$DB/commands/$HOST.json" \
        -d '{"reboot":false}' >/dev/null
        curl -s -X PATCH \
        "$DB/displays/$HOST.json" \
        -d "{
            \"hostname\":\"$HOST\",
            \"username\":\"$USER\",
            \"ip\":\"$IP\",
            \"status\":\"rebooting\",
            \"uptime\":$UPTIME,
            \"lastSeen\":$LAST,
            \"version\":\"v1.4.1\"
        }" >/dev/null
        sudo /usr/sbin/reboot
    fi

    if [ "$SHUTDOWN" = "true" ]; then
        echo "Shutdown command received."
        curl -s -X PATCH \
        "$DB/commands/$HOST.json" \
        -d '{"shutdown":false}' >/dev/null
        curl -s -X PATCH \
        "$DB/displays/$HOST.json" \
        -d "{
            \"hostname\":\"$HOST\",
            \"username\":\"$USER\",
            \"ip\":\"$IP\",
            \"status\":\"shutting_down/offline\",
            \"uptime\":$UPTIME,
            \"lastSeen\":$LAST,
            \"version\":\"v1.4.1\"
        }" >/dev/null
        sudo /usr/sbin/shutdown -h now
    fi

    if [ "$UPDATE" = "true" ]; then
        echo "Update command received."

        curl -s -X PATCH \
        "$DB/commands/$HOST.json" \
        -d '{"update":false}' >/dev/null

        curl -s -X PATCH \
        "$DB/displays/$HOST.json" \
        -d '{"status":"updating"}' >/dev/null
        update_client
    fi
}

sleep 8
launch_stream
while true
do
    heartbeat
    take_screenshot
    check_commands
    upload_log
    sleep 30
done