#!/bin/bash
set -e

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

echo "Running cl-py-generator transpiler for Neon Transition Solver..."
cd "$WORKSPACE_DIR"
sbcl --disable-debugger --load "$SCRIPT_DIR/gen01.lisp" --quit
echo "Transpilation complete!"
