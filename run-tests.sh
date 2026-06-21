#!/bin/bash
# run-tests.sh - Run tests for cl-cl-generator

sbcl --disable-debugger \
     --eval '(push "/home/kiel/stage/cl-cl-generator/" asdf:*central-registry*)' \
     --eval '(ql:quickload :cl-cl-generator)' \
     --load '/home/kiel/stage/cl-cl-generator/tests.lisp' \
     --eval '(cl-cl-generator/tests:run-tests)'
