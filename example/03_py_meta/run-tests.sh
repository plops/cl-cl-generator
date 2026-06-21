#!/bin/bash
# run-tests.sh - Run cl-py-generator unit tests using the generated py.lisp

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CL_PY_DIR="$(cd "${SCRIPT_DIR}/../../../cl-py-generator" && pwd)"

sbcl --disable-debugger \
     --eval "(push \"${CL_PY_DIR}/\" asdf:*central-registry*)" \
     --eval '(ql:quickload :cl-py-generator)' \
     --load "${SCRIPT_DIR}/py.lisp" \
     --load "${CL_PY_DIR}/transpiler-tests.lisp" \
     --eval '(cl-py-generator/tests::run-transpiler-tests)' \
     --quit
