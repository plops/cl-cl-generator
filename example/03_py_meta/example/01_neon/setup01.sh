#!/bin/bash
set -e

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
# Determine virtualenv location dynamically
if [ -d "$WORKSPACE_DIR/.venv/bin" ]; then
    VENV_BIN="$WORKSPACE_DIR/.venv/bin"
elif [ -d "/workspace/.venv/bin" ]; then
    VENV_BIN="/workspace/.venv/bin"
else
    echo "Error: Virtual environment not found."
    exit 1
fi


# Parse arguments
PLATFORM=${1:-cpu}
ACTION=${2:-all}

# Validate platform
if [[ "$PLATFORM" != "cpu" && "$PLATFORM" != "gpu" && "$PLATFORM" != "tpu" ]]; then
    echo "Error: Invalid platform '$PLATFORM'. Must be 'cpu', 'gpu', or 'tpu'."
    echo "Usage: $0 [cpu|gpu|tpu] [all|run|test]"
    exit 1
fi

# Set JAX platform environment variable
export JAX_PLATFORM_NAME="$PLATFORM"
export JAX_PLATFORMS="$PLATFORM"

echo "Using JAX backend: $PLATFORM"

# Run tests
if [[ "$ACTION" == "all" || "$ACTION" == "test" ]]; then
    echo "Running verification tests..."
    "$VENV_BIN/pytest" "$SCRIPT_DIR/source01/test_solver.py"
fi

# Run solver and generate plots
if [[ "$ACTION" == "all" || "$ACTION" == "run" ]]; then
    echo "Running solver and generating plots..."
    "$VENV_BIN/python" "$SCRIPT_DIR/source01/plot.py"
    echo "Output saved to: $SCRIPT_DIR/source01/neon_transition_plots.png"
fi

echo "Execution finished successfully!"
