#!/bin/bash
# run-xvfb-test.sh — Start Xvfb, run the client, take a screenshot, and save it.

# Start Xvfb on display :99 in the background
Xvfb :99 -screen 0 640x480x24 &
XVFB_PID=$!
export DISPLAY=:99

sleep 1 # Wait for Xvfb to start

# Run the X11 example client in the background
./run-example.sh &
CLIENT_PID=$!

sleep 3 # Wait 3 seconds for the client to connect, map, and render

# Capture a screenshot of display :99 using ImageMagick import
import -window root screenshot.png

# Copy to artifacts directory
cp screenshot.png /root/.gemini/antigravity-cli/brain/19e83a78-84ed-490b-9e5e-840eb2b263f2/screenshot.png

# Kill background processes
kill -9 $CLIENT_PID
kill -9 $XVFB_PID
echo "Screenshot captured and saved to artifacts."
