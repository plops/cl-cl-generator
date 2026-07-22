#!/bin/bash
# run-xvfb-orbit-demo.sh — Start Xvfb, run the orbit demo, wait for animation, take a screenshot.

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
TMP_DIR="${SCRIPT_DIR}/tmp"
mkdir -p "$TMP_DIR"

# Start Xvfb on display :99 in the background
Xvfb :99 -screen 0 640x480x24 &
XVFB_PID=$!
export DISPLAY=:99

trap 'kill $CLIENT_PID $XVFB_PID 2>/dev/null || true' EXIT INT TERM

sleep 1 # Wait for Xvfb to start

# Run the X11 orbit demo client in the background
"${SCRIPT_DIR}/run-orbit-demo.sh" &
CLIENT_PID=$!

sleep 4 # Wait 4 seconds for the client to connect, map, render, and animate some frames

# Capture a screenshot of display :99 using ImageMagick import
import -window root "${SCRIPT_DIR}/orbit_screenshot.png"

if [ -n "$ARTIFACT_DIR" ]; then
    cp "${SCRIPT_DIR}/orbit_screenshot.png" "${ARTIFACT_DIR}/orbit_screenshot.png" 2>/dev/null || true
else
    cp "${SCRIPT_DIR}/orbit_screenshot.png" "${TMP_DIR}/orbit_screenshot.png" 2>/dev/null || true
fi

echo "Orbit screenshot captured and saved."
