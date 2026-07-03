#!/bin/bash
# run-spacecraft.sh - Runner for HPIPM Spacecraft Docking Demo

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Try to automatically find the bundled CasADi HPIPM/BLASFEO libraries if not installed globally
if [ -z "$LD_LIBRARY_PATH" ]; then
    # Search in the sibling cl-py-generator casadi venv relative to this example
    CASADI_VENV_DIR="$SCRIPT_DIR/../../../cl-py-generator/example/171_casadi/.venv"
    if [ -d "$CASADI_VENV_DIR" ]; then
        FOUND_DIR=$(find "$CASADI_VENV_DIR" -name "libhpipm.so" -exec dirname {} \; 2>/dev/null | head -n 1)
        if [ -n "$FOUND_DIR" ]; then
            export LD_LIBRARY_PATH="$FOUND_DIR:$LD_LIBRARY_PATH"
            echo "Auto-detected HPIPM libraries at: $FOUND_DIR"
        fi
    fi
fi

# Run the spacecraft demo
sbcl --noinform --non-interactive \
     --eval "(push \"$SCRIPT_DIR/source01/\" asdf:*central-registry*)" \
     --eval "(ql:quickload :hpipm)" \
     --eval "(hpipm-spacecraft-demo:run-spacecraft-demo)"
