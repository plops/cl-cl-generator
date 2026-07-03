#!/bin/bash
# run-example.sh — Simple script to compile and run the generated Pure X11 example.

# Ensure DISPLAY is set
if [ -z "$DISPLAY" ]; then
    echo "Error: DISPLAY environment variable is not set."
    echo "Please ensure you are running this in an X11 environment or have configured X11 forwarding."
    exit 1
fi

# Resolve absolute path to the directory containing this script
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
SOURCE_DIR="${SCRIPT_DIR}/source/"

echo "Starting Pure X11 Example Client via SBCL..."
sbcl --eval "(push \"${SOURCE_DIR}\" asdf:*central-registry*)" \
     --eval '(ql:quickload :pure-x11-gen)' \
     --load "${SOURCE_DIR}/example.lisp" \
     --eval '(pure-x11-gen/example:run-x11-example)' \
     --eval '(quit)'
