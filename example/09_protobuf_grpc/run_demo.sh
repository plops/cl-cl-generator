#!/bin/bash
# run_demo.sh — Live demonstration of protobuf-grpc-example
#
# Starts a gRPC-like TCP server in-process, connects a client,
# performs AddPerson and GetPeople RPC calls with printed output,
# demonstrates remote error propagation, then shuts down cleanly.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================"
echo "  protobuf-grpc-example Live Demo"
echo "========================================"
echo ""

# Regenerate sources first if needed
if [ ! -f "${SCRIPT_DIR}/source/protobuf-grpc-example.asd" ]; then
    echo "Source files not found — running generator first..."
    sbcl --noinform --non-interactive --load "${SCRIPT_DIR}/gen.lisp"
    echo ""
fi

sbcl --noinform --non-interactive --load "${SCRIPT_DIR}/demo_runner.lisp"
