#!/bin/bash
# run-xvfb-test.sh — Start Xvfb, run the client, focus input, type text, take a screenshot.

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
TMP_DIR="${SCRIPT_DIR}/tmp"
mkdir -p "$TMP_DIR"

# Start Xvfb on display :99 in the background
Xvfb :99 -screen 0 640x480x24 &
XVFB_PID=$!
export DISPLAY=:99

trap 'kill $CLIENT_PID $XVFB_PID 2>/dev/null || true' EXIT INT TERM

sleep 1 # Wait for Xvfb to start

# Run the X11 example client in the background
"${SCRIPT_DIR}/run-example.sh" &
CLIENT_PID=$!

sleep 3 # Wait 3 seconds for the client to connect, map, and render

# Focus the text input field by clicking on it (x=200, y=95)
xdotool mousemove 200 95 click 1
sleep 0.5

# Type " Hello" into the text-input field
xdotool type " Hello"
sleep 1

# Capture a screenshot of display :99 using ImageMagick import
import -window root "${SCRIPT_DIR}/screenshot.png"

if [ -n "$ARTIFACT_DIR" ]; then
    cp "${SCRIPT_DIR}/screenshot.png" "${ARTIFACT_DIR}/screenshot.png" 2>/dev/null || true
else
    cp "${SCRIPT_DIR}/screenshot.png" "${TMP_DIR}/screenshot.png" 2>/dev/null || true
fi

echo "Screenshot captured and saved."
