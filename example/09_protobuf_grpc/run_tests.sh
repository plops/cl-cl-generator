#!/bin/bash
# run_tests.sh — Run unit tests and integration tests for protobuf-grpc-example

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================"
echo "  protobuf-grpc-example Test Suite"
echo "========================================"
echo ""

# Regenerate sources first if source/ doesn't exist
if [ ! -f "${SCRIPT_DIR}/source/protobuf-grpc-example.asd" ]; then
    echo "Source files not found — running generator first..."
    sbcl --noinform --non-interactive --load "${SCRIPT_DIR}/gen.lisp"
    echo ""
fi

echo "Running test suite (unit + integration)..."
echo ""
sbcl --noinform --non-interactive --load "${SCRIPT_DIR}/tests_runner.lisp"
