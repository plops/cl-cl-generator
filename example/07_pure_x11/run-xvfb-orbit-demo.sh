#!/bin/bash
# run-xvfb-orbit-demo.sh — Start Xvfb, run the orbit demo, wait for animation, take a screenshot.

# Start Xvfb on display :99 in the background
Xvfb :99 -screen 0 640x480x24 &
XVFB_PID=$!
export DISPLAY=:99

sleep 1 # Wait for Xvfb to start

# Run the X11 orbit demo client in the background
./run-orbit-demo.sh &
CLIENT_PID=$!

sleep 4 # Wait 4 seconds for the client to connect, map, render, and animate some frames

# Capture a screenshot of display :99 using ImageMagick import
import -window root orbit_screenshot.png

# Copy to artifacts directory
cp orbit_screenshot.png /root/.gemini/antigravity-cli/brain/072d4d39-ee6c-4fc5-9860-ad79ed181ec8/orbit_screenshot.png

# Kill background processes
kill -9 $CLIENT_PID
kill -9 $XVFB_PID
echo "Orbit screenshot captured and saved to artifacts."
