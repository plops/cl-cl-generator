#!/bin/bash
# run.sh - Portable runner for HPIPM MPC and Pendulum demos

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Try to automatically find the bundled CasADi HPIPM/BLASFEO libraries if not installed globally
if [ -z "$LD_LIBRARY_PATH" ]; then
    # Search in the sibling cl-py-generator casadi venv
    CASADI_VENV_DIR="$SCRIPT_DIR/../../../../cl-py-generator/example/171_casadi/.venv"
    if [ -d "$CASADI_VENV_DIR" ]; then
        FOUND_DIR=$(find "$CASADI_VENV_DIR" -name "libhpipm.so" -exec dirname {} \; 2>/dev/null | head -n 1)
        if [ -n "$FOUND_DIR" ]; then
            export LD_LIBRARY_PATH="$FOUND_DIR:$LD_LIBRARY_PATH"
            echo "Auto-detected HPIPM libraries at: $FOUND_DIR"
        fi
    fi
fi

# Print help if invalid argument
show_help() {
    echo "Usage: $0 [mpc | pendulum | all | help]"
    echo "  mpc      : Run the Coupled Mass-Spring-Damper MPC stabilization demo"
    echo "  pendulum : Run the Inverted Pendulum on a Cart MPC stabilization demo"
    echo "  all      : Run both demos (default)"
    echo "  help     : Show this help message"
}

# Run the selected demo
run_demo() {
    local demo_type=$1
    echo "Running HPIPM $demo_type demo..."
    
    case "$demo_type" in
        "mpc")
            sbcl --noinform --non-interactive \
                 --eval "(push \"$SCRIPT_DIR/\" asdf:*central-registry*)" \
                 --eval "(ql:quickload :hpipm)" \
                 --load "$SCRIPT_DIR/mpc-demo.lisp" \
                 --eval "(hpipm-demo:run-mpc-demo)"
            ;;
        "pendulum")
            sbcl --noinform --non-interactive \
                 --eval "(push \"$SCRIPT_DIR/\" asdf:*central-registry*)" \
                 --eval "(ql:quickload :hpipm)" \
                 --load "$SCRIPT_DIR/pendulum-demo.lisp" \
                 --eval "(hpipm-pendulum-demo:run-pendulum-demo)"
            ;;
    esac
}

# Parse command line arguments
case "$1" in
    "mpc")
        run_demo "mpc"
        ;;
    "pendulum")
        run_demo "pendulum"
        ;;
    "all"|"")
        run_demo "mpc"
        echo ""
        run_demo "pendulum"
        ;;
    "help"|"-h"|"--help")
        show_help
        ;;
    *)
        echo "Unknown option: $1"
        show_help
        exit 1
        ;;
esac
