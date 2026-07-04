#!/bin/bash
# run-gui.sh — Compile the netlist and run the X11 Mass-Spring-Damper GUI.

# Ensure DISPLAY is set
if [ -z "$DISPLAY" ]; then
    echo "Error: DISPLAY environment variable is not set."
    echo "Please run this in an X11-enabled environment or setup X11 forwarding."
    exit 1
fi

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
CL_CL_GEN_DIR=$(cd -- "${SCRIPT_DIR}/../.." &> /dev/null && pwd)
X11_SOURCE_DIR="${CL_CL_GEN_DIR}/example/07_pure_x11/source/"

echo "Starting Multi-Domain Mass-Spring-Damper Simulation GUI..."
sbcl --eval "(push \"${CL_CL_GEN_DIR}/\" asdf:*central-registry*)" \
     --eval "(push \"${X11_SOURCE_DIR}\" asdf:*central-registry*)" \
     --eval '(ql:quickload :cl-cl-generator)' \
     --eval '(ql:quickload :pure-x11-gen)' \
     --load "${SCRIPT_DIR}/oscillator-gui.lisp" \
     --eval '(multi-domain-solver/gui:run-gui-demo)' \
     --eval '(quit)'
