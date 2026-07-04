#!/bin/bash
# run.sh — Run script for Expanse Orbital Space Combat

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Search for CasADi HPIPM/BLASFEO shared libraries if not installed globally
if [ -z "$LD_LIBRARY_PATH" ]; then
    CASADI_VENV_DIR="$SCRIPT_DIR/../../../cl-py-generator/example/171_casadi/.venv"
    if [ -d "$CASADI_VENV_DIR" ]; then
        FOUND_DIR=$(find "$CASADI_VENV_DIR" -name "libhpipm.so" -exec dirname {} \; 2>/dev/null | head -n 1)
        if [ -n "$FOUND_DIR" ]; then
            export LD_LIBRARY_PATH="$FOUND_DIR:$LD_LIBRARY_PATH"
            echo "Auto-detected HPIPM libraries at: $FOUND_DIR"
        fi
    fi
fi

# Ensure DISPLAY is set
if [ -z "$DISPLAY" ]; then
    echo "Warning: DISPLAY environment variable is not set. Running inside virtual framebuffer."
    if command -v xvfb-run &> /dev/null; then
        RUN_PREFIX="xvfb-run -s '-screen 0 800x600x24'"
    fi
fi

# 1. Run the generator script to create the game source files
echo "Regenerating source files..."
sbcl --noinform --non-interactive --load "${SCRIPT_DIR}/gen.lisp"

# 2. Run the game via SBCL
echo "Starting Expanse space combat simulator..."
$RUN_PREFIX sbcl \
     --eval "(push \"${SCRIPT_DIR}/../06_hpipm_cffi/source01/\" asdf:*central-registry*)" \
     --eval "(push \"${SCRIPT_DIR}/../07_pure_x11/source/\" asdf:*central-registry*)" \
     --eval "(push \"${SCRIPT_DIR}/source/\" asdf:*central-registry*)" \
     --eval "(ql:quickload :expanse-combat)" \
     --eval "(expanse-combat/game:run-game)" \
     --eval "(quit)"
