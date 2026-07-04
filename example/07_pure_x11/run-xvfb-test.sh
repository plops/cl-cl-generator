#!/bin/bash
# run-xvfb-test.sh — Start Xvfb, run the client, focus input, type text, take a screenshot.

# Start Xvfb on display :99 in the background
Xvfb :99 -screen 0 640x480x24 &
XVFB_PID=$!
export DISPLAY=:99

sleep 1 # Wait for Xvfb to start

# Run the X11 example client in the background
./run-example.sh &
CLIENT_PID=$!

sleep 3 # Wait 3 seconds for the client to connect, map, and render

# Focus the text input field by clicking on it (x=200, y=95)
xdotool mousemove 200 95 click 1
sleep 0.5

# Type " Hello" into the text-input field
xdotool type " Hello"
sleep 1

# Capture a screenshot of display :99 using ImageMagick import
import -window root screenshot.png

# Copy to artifacts directory
cp screenshot.png /root/.gemini/antigravity-cli/brain/d3593425-01aa-4749-aed0-2057a557ae6b/screenshot.png

# Kill background processes
kill -9 $CLIENT_PID
kill -9 $XVFB_PID
echo "Screenshot captured and saved to artifacts."
