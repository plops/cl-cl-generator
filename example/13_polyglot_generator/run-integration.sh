#!/bin/bash
# run-integration.sh - integration tests (V-INT)
#
#   ./run-integration.sh [program...] [--targets cl,python,cpp,rust,go]
#   ./run-integration.sh --determinism      generate twice and compare
#
# Generates every program of tests/integration/programs into build/<prog>/,
# runs the idiomatic gates (ruff check, g++ -Wall -Wextra -Werror,
# cargo clippy -D warnings, go vet), runs the program and compares stdout
# with expected.txt. Exit code 1 when any combination fails.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${DIR}/../.." && pwd)"
ARGS=""
for a in "$@"; do ARGS="$ARGS \"$a\""; done
exec sbcl --noinform --non-interactive --load "$HOME/quicklisp/setup.lisp" \
  --eval "(progn (push #p\"${REPO}/\" asdf:*central-registry*) (push #p\"${DIR}/\" asdf:*central-registry*))" \
  --eval '(let ((*compile-verbose* nil) (*load-verbose* nil)) (ql:quickload :polyglot-generator :silent t))' \
  --load "${DIR}/tests/integration/run.lisp" \
  --load "${DIR}/tests/integration/toolchains.lisp" \
  --load "${DIR}/tests/integration/main.lisp" \
  --load "${DIR}/tests/integration/determinism.lisp" \
  --eval "(uiop:quit (polyglot.integration:main (list $ARGS)))"
