#!/bin/bash
# run-tests.sh - unit and spec tests of the polyglot generator (FiveAM)
#
#   ./run-tests.sh               unit + spec tests with SBCL
#   ./run-tests.sh --ecl         the same tests with ECL
#   ./run-tests.sh --docs        regenerate SUPPORTED_FORMS.md from the spec table
#   ./run-tests.sh --docs-check  fail when SUPPORTED_FORMS.md is outdated
#   ./run-tests.sh --paren       randomized precedence tests (compiles programs)
#   ./run-tests.sh --all         SBCL, ECL and the docs check one after another
#
# ECL (24.5.10) loads the system and runs the complete unit and spec suite;
# only the external formatters and compilers are the same processes.
set -u
if [ "${1:-}" = "--all" ]; then
  "$0" && "$0" --ecl && "$0" --docs-check
  exit $?
fi
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${DIR}/../.." && pwd)"
LISP=sbcl
ACTION='(uiop:quit (if (fiveam:run! :polyglot) 0 1))'
for arg in "$@"; do
  case "$arg" in
    --ecl) LISP=ecl ;;
    --docs) ACTION='(progn (polyglot.tests::write-supported-forms) (uiop:quit 0))' ;;
    --docs-check) ACTION='(uiop:quit (if (polyglot.tests::supported-forms-current-p) 0 1))' ;;
    --paren) ACTION='(uiop:quit (if (polyglot.tests::run-paren-tests) 0 1))' ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done
PRE="(progn (push #p\"${REPO}/\" asdf:*central-registry*) (push #p\"${DIR}/\" asdf:*central-registry*))"
LOAD='(let ((*compile-verbose* nil) (*load-verbose* nil)) (ql:quickload :polyglot-generator/tests :silent t))'
if [ "$LISP" = ecl ]; then
  exec ecl --norc --load "$HOME/quicklisp/setup.lisp" --eval "$PRE" --eval "$LOAD" --eval "$ACTION"
else
  exec sbcl --noinform --non-interactive --load "$HOME/quicklisp/setup.lisp" \
       --eval "$PRE" --eval "$LOAD" --eval "$ACTION"
fi
