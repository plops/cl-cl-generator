#!/bin/bash
# run-tests.sh - Run tests for cl-cl-generator

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

sbcl --disable-debugger \
     --eval "(push \"${SCRIPT_DIR}/\" asdf:*central-registry*)" \
     --eval '(ql:quickload :cl-cl-generator)' \
     --load "${SCRIPT_DIR}/tests.lisp" \
     --eval '(cl-cl-generator/tests:run-tests)'
