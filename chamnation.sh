#!/bin/bash

# ==========================================
# CHAMNATION TV CLIENT v1.0
# ==========================================

DB="https://chaminadetv-86055-default-rtdb.firebaseio.com"
CHANNEL="UCP4CuIbDHok4YsEsIUz5utw"

HOST=$(hostname)
USER=$(whoami)

YOUTUBE="http://youtube.com/channel/UCP4CuIbDHok4YsEsIUz5utw/live"

update_client () {
    REPO="https://raw.githubusercontent.com/ChamTech616/ChamTV/main"
    TEMP="/tmp/chamnation.sh"
    DEST="/home/$HOST/chamnation.sh"

    echo "Downloading latest version..."

    curl -L "$REPO/chamnation.sh" -o "$TEMP"

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

    sudo reboot
}

LAST_PREVIEW=0

take_screenshot () {

    FILE="/tmp/$HOST.jpg"

    # Compress image so it fits Firebase
    scrot -q 35 "$FILE"

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
        \"version\":\"V1.3\"
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
            \"version\":\"V1.3\"
        }" >/dev/null
        reboot now
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
            \"version\":\"V1.2\"
        }" >/dev/null
        shutdown now
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
    NOW=$(date +%s)
    if (( NOW - LAST_PREVIEW >= 300 )); then
        LAST_PREVIEW=$NOW
        take_screenshot
    fi
    check_commands
    sleep 30
done