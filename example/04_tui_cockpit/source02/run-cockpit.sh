#!/bin/bash
# run-cockpit.sh - Startup script for Tuition Interactive TUI Cockpit

if [ "$EUID" -ne 0 ]; then
  echo "Error: Please run this script as root (required for socket inspection and cgroups)." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Find sbcl core
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
  export SBCL_HOME="$(dirname "$SBCL_CORE")"
fi

if [ -n "$SUDO_USER" ]; then
  INVOKING_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
else
  INVOKING_HOME="$HOME"
fi

QL_SETUP=""
for path in \
    "$HOME/quicklisp/setup.lisp" \
    "$INVOKING_HOME/quicklisp/setup.lisp"; do
  if [ -f "$path" ]; then
    QL_SETUP="$path"
    break
  fi
done

QL_ARG=""
if [ -n "$QL_SETUP" ]; then
  QL_ARG="--load $QL_SETUP"
fi

exec sbcl $CORE_ARG --disable-debugger $QL_ARG \
     --eval "(push \"${SCRIPT_DIR}/\" asdf:*central-registry*)" \
     --eval "(ql:quickload :cockpit-tui :silent t)" \
     --eval "(cockpit-tui:run-cockpit)"
