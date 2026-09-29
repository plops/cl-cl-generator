#!/bin/bash
# polyglot-gen.sh - generate C++/Python/Rust/Go/Common Lisp from a DSL project
#
#   ./polyglot-gen.sh PROJECT.lisp [--targets cpp,rust,python,go,cl] [--out DIR]
#                     [--mode minimal|full] [--no-format]
#   ./polyglot-gen.sh --help
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${DIR}/../.." && pwd)"
ARGS=""
for a in "$@"; do ARGS="$ARGS \"$a\""; done
exec sbcl --noinform --non-interactive --load "$HOME/quicklisp/setup.lisp" \
  --eval "(progn (push #p\"${REPO}/\" asdf:*central-registry*) (push #p\"${DIR}/\" asdf:*central-registry*))" \
  --eval '(let ((*compile-verbose* nil) (*load-verbose* nil)) (ql:quickload :polyglot-generator :silent t))' \
  --eval "(uiop:quit (polyglot:run-cli (list $ARGS)))"
