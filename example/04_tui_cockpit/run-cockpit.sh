#!/bin/bash
# run-cockpit.sh - Portable startup script for the TUI Cockpit

# Ensure we are running as root
if [ "$EUID" -ne 0 ]; then
  echo "Error: Please run this script as root (required for socket inspection and cgroups)." >&2
  exit 1
fi

# Detect the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Execute SBCL and register the script's directory with ASDF
exec sbcl --disable-debugger \
     --eval "(push \"${SCRIPT_DIR}/\" asdf:*central-registry*)" \
     --eval "(ql:quickload :cockpit :silent t)" \
     --eval "(cockpit:run-cockpit)"
