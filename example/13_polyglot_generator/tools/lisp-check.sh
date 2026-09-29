#!/bin/bash
# lisp-check.sh - syntax gate for the polyglot generator
#
#   tools/lisp-check.sh [--indent] [--fix-indent] [--ecl] [--tests] FILE...
#
#   (a) parenmedic diagnose (warning only, SBCL is the ground truth)
#   (b) SBCL reads every FILE form by form with the polyglot readtable
#   (c) asdf:load-system :polyglot-generator :force t (warnings are errors)
#   --tests      also load polyglot-generator/tests in (c)
#   --indent     re-indent a copy of every FILE with Emacs and show the diff
#   --fix-indent re-indent every FILE in place with Emacs
#   --ecl        load the system with ECL as well
# Prints LISP-CHECK OK and exits 0 on success.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$(cd "${DIR}/../.." && pwd)"
PARENMEDIC=/workspace/src/parenmedic/zig-out/bin/parenmedic
INDENT=0; FIX=0; ECL=0; TESTS=0; FILES=()
for arg in "$@"; do
  case "$arg" in
    --indent) INDENT=1 ;;
    --fix-indent) FIX=1 ;;
    --ecl) ECL=1 ;;
    --tests) TESTS=1 ;;
    *) if [ ! -f "$arg" ]; then echo "no such file: $arg" >&2; echo "LISP-CHECK FAILED"; exit 2; fi
       FILES+=("$(realpath "$arg")") ;;
  esac
done
STATUS=0
if [ -x "$PARENMEDIC" ]; then
  for f in "${FILES[@]}"; do
    out="$("$PARENMEDIC" diagnose --format=simple "$f" 2>&1)" || echo "parenmedic warning ($f): $out"
  done
fi
if [ "$FIX" = 1 ]; then
  emacs --batch -Q -l "$DIR/tools/reindent.el" "${FILES[@]}" 2>/dev/null
fi
if [ "$INDENT" = 1 ]; then
  TMP="$(mktemp -d)"
  for f in "${FILES[@]}"; do
    cp "$f" "$TMP/$(basename "$f")"
    emacs --batch -Q -l "$DIR/tools/reindent.el" "$TMP/$(basename "$f")" 2>/dev/null
    if ! diff -u "$f" "$TMP/$(basename "$f")"; then
      echo "INDENT MISMATCH: $f"; STATUS=1
    fi
  done
  rm -rf "$TMP"
fi
SYSTEMS='(list "polyglot-generator")'
[ "$TESTS" = 1 ] && SYSTEMS='(list "polyglot-generator" "polyglot-generator/tests")'
LISPFILES=""
for f in "${FILES[@]}"; do LISPFILES="$LISPFILES \"$f\""; done
PRE="(progn (push #p\"${REPO}/\" asdf:*central-registry*) (push #p\"${DIR}/\" asdf:*central-registry*) (let ((*compile-verbose* nil) (*load-verbose* nil)) (ql:quickload (list :alexandria :cl-ppcre :trivia :named-readtables :fiveam :cl-cl-generator) :silent t) (load \"${DIR}/src/00-package.lisp\") (load \"${DIR}/src/01-syntax.lisp\")))"
sbcl --noinform --non-interactive --load "$HOME/quicklisp/setup.lisp" --eval "$PRE" \
     --load "$DIR/tools/lisp-check.lisp" \
     --eval "(lisp-check:main (list $LISPFILES) :systems $SYSTEMS)" 2>&1 | grep -v '^;' || true
RC=${PIPESTATUS[0]}
[ "$RC" != 0 ] && STATUS=1
if [ "$ECL" = 1 ] && [ "$STATUS" = 0 ]; then
  ecl --norc --load "$HOME/quicklisp/setup.lisp" --eval "$PRE" \
      --eval "(handler-case (progn (let ((*compile-verbose* nil) (*load-verbose* nil)) (dolist (s $SYSTEMS) (asdf:load-system s))) (format t \"~&ECL LOAD OK~%\") (ext:quit 0)) (error (e) (format t \"~&ECL LOAD ERROR: ~a~%\" e) (ext:quit 1)))" 2>&1 | grep -E 'ECL LOAD|rror' | head -20
  [ "${PIPESTATUS[0]}" != 0 ] && STATUS=1
fi
if [ "$STATUS" = 0 ]; then echo "LISP-CHECK OK"; else echo "LISP-CHECK FAILED"; fi
exit $STATUS
