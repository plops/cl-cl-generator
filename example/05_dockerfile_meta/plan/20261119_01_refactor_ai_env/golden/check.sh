#!/usr/bin/env bash
# Generate every variant in variants.txt and compare against golden/<name>.Dockerfile.
#   ./check.sh           compare (exit 1 on any difference)
#   ./check.sh --update  rewrite the golden files
# Method: a copy of gen_ai_env.lisp with rewritten defparameter defaults is loaded from a
# temporary directory, so the repository Dockerfile is never touched.
set -euo pipefail
here=$(cd -- "$(dirname -- "$0")" && pwd)
repo=$(cd -- "$here/../../.." && pwd)
gen="$repo/source01/examples/03_ai_env/gen_ai_env.lisp"
update=0; [[ "${1:-}" == --update ]] && update=1
tmp=$(mktemp -d /tmp/ai-env-golden.XXXXXX); trap 'rm -rf "$tmp"' EXIT
status=0
while IFS= read -r line; do
  [[ -z "$line" || "$line" == \#* ]] && continue
  name=${line%%:*}; read -r -a ovs <<<"${line#*:}"
  mkdir -p "$tmp/$name"
  python3 -I "$here/render.py" "$gen" "$tmp/$name/gen_ai_env.lisp" ${ovs[@]+"${ovs[@]}"}
  if ! sbcl --noinform --non-interactive --eval '(require "asdf")' \
       --eval "(push #p\"$repo/source01/\" asdf:*central-registry*)" \
       --load "$tmp/$name/gen_ai_env.lisp" >"$tmp/$name/sbcl.log" 2>&1; then
    echo "FAIL $name: sbcl error"; tail -20 "$tmp/$name/sbcl.log"; status=1; continue
  fi
  if grep -qiE '^(; caught )?(WARNING|STYLE-WARNING)' "$tmp/$name/sbcl.log"; then
    echo "WARN $name: compiler warnings"; grep -iE -A3 'WARNING' "$tmp/$name/sbcl.log" | head -20
  fi
  out="$tmp/$name/Dockerfile"
  if (( update )); then cp "$out" "$here/$name.Dockerfile"; echo "UPDATED $name"
  elif diff -u "$here/$name.Dockerfile" "$out" >"$tmp/$name.diff"; then echo "PASS $name"
  else echo "DIFF $name"; head -60 "$tmp/$name.diff"; status=1; fi
done <"$here/variants.txt"
exit $status
