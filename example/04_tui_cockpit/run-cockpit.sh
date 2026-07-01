#!/bin/bash
# run-cockpit.sh - Portable startup script for the TUI Cockpit

# Ensure we are running as root
if [ "$EUID" -ne 0 ]; then
  echo "Error: Please run this script as root (required for socket inspection and cgroups)." >&2
  exit 1
fi

# Detect the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Search for sbcl.core in standard Linux paths to handle sudo sanitization
SBCL_CORE=""
for path in \
    "/usr/lib64/sbcl/sbcl.core" \
    "/usr/lib/sbcl/sbcl.core" \
    "/usr/local/lib/sbcl/sbcl.core"; do
  if [ -f "$path" ]; then
    SBCL_CORE="$path"
    break
  fi
done

CORE_ARG=""
if [ -n "$SBCL_CORE" ]; then
  CORE_ARG="--core $SBCL_CORE"
fi

# Execute SBCL and register the script's directory with ASDF
exec sbcl $CORE_ARG --disable-debugger \
     --eval "(push \"${SCRIPT_DIR}/\" asdf:*central-registry*)" \
     --eval "(ql:quickload :cockpit :silent t)" \
     --eval "(cockpit:run-cockpit)"
