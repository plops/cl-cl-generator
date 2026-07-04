#!/bin/bash
# run_gen.sh — (Re)generate the protobuf-grpc-example source files from gen.lisp

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================"
echo "  protobuf-grpc-example Code Generator"
echo "========================================"
echo ""
echo "Generating source files from schema DSL..."
sbcl --noinform --non-interactive --load "${SCRIPT_DIR}/gen.lisp"
echo ""
echo "Generated files:"
ls -lh "${SCRIPT_DIR}/source/"
echo ""
echo "Done."
