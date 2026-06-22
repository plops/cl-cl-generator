#!/bin/bash
# run-tests.sh - Run cl-py-generator unit tests using the generated py.lisp

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

sbcl --disable-debugger \
     --eval "(push \"${SCRIPT_DIR}/\" asdf:*central-registry*)" \
     --load "${SCRIPT_DIR}/transpiler-tests.lisp" \
     --eval '(cl-py-generator/tests::run-transpiler-tests)' \
     --quit

