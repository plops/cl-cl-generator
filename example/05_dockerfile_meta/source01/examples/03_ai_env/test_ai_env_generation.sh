#!/usr/bin/env bash
# Generator-level tests for gen_ai_env.lisp (no docker build needed):
#   1. golden variant matrix (byte-identical output)
#   2. switches changed with SETF after loading still affect derived values
#   3. the default image contains the daily-use agent CLIs (muse, claude, kiro-cli, copilot)
#   4. loading with AI_ENV_NO_AUTOGEN does not touch ./Dockerfile
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
meta_dir=$(cd -- "$script_dir/../../.." && pwd)
tmp=$(mktemp -d /tmp/ai-env-gen-test.XXXXXX); trap 'rm -rf "$tmp"' EXIT

"$meta_dir/plan/20261119_01_refactor_ai_env/golden/check.sh"

before=$(stat -c %Y "$script_dir/Dockerfile")
AI_ENV_NO_AUTOGEN=1 sbcl --noinform --non-interactive --eval '(require "asdf")' \
  --load "$script_dir/gen_ai_env.lisp" \
  --eval '(in-package :cl-dockerfile-generator)' \
  --eval "(generate-ai-env #p\"$tmp/default.Dockerfile\")" \
  --eval '(setf *enable-cuda* nil *install-gcc* nil)' \
  --eval "(generate-ai-env #p\"$tmp/setf.Dockerfile\")" >/dev/null
[[ $(stat -c %Y "$script_dir/Dockerfile") == "$before" ]] || { echo "FAIL: Dockerfile touched"; exit 1; }
echo "PASS: AI_ENV_NO_AUTOGEN leaves ./Dockerfile alone"

check() { # file description grep-args...
  local file=$1 desc=$2; shift 2
  if grep -q "$@" "$file"; then echo "PASS: $desc"; else echo "FAIL: $desc"; exit 1; fi
}
check_not() {
  local file=$1 desc=$2; shift 2
  if grep -q "$@" "$file"; then echo "FAIL: $desc"; exit 1; else echo "PASS: $desc"; fi
}
d=$tmp/default.Dockerfile s=$tmp/setf.Dockerfile
check     "$d" "default uses CUDA base"            -F 'FROM nvidia/cuda:'
check     "$s" "setf *enable-cuda* nil -> ubuntu"  -F 'FROM ubuntu:26.04 AS runner'
check_not "$s" "setf *enable-cuda* nil -> no CUDA" -F 'nvidia/cuda'
check_not "$s" "no CUDA python extras"             -F 'polars'
check_not "$s" "setf *install-gcc* nil -> no gdb"  -w 'gdb'
for tool in muse claude kiro-cli copilot; do
  check "$d" "$tool wrapper installed" -F "COPY --chmod=755 <<'EOF' /usr/local/bin/$tool"
  check "$d" "$tool wrapper calls .real binary" -F "exec /usr/local/bin/$tool.real"
done
check "$d" "muse runs with --yolo"                  -F 'muse.real --yolo "$@"'
check "$d" "claude skips permissions"               -F 'claude.real --dangerously-skip-permissions "$@"'
check "$d" "claude config dir is bind-mountable"    -F 'CLAUDE_CONFIG_DIR=/root/.claude'
check "$d" "copilot allows all"                     -F 'copilot.real --allow-all "$@"'
check "$d" "kiro-cli init is forced"                -F 'init) exec /usr/local/bin/kiro-cli.real init --force'
check "$d" "container starts bash"                  -F 'CMD ["/bin/bash"]'
# 5. README defaults match the scalar defaults in the generator (t, nil, :keyword, "string").
python3 -I - "$script_dir/gen_ai_env.lisp" "$script_dir/README.md" <<'PY'
import re, sys
code, readme = (open(p).read() for p in sys.argv[1:3])
defaults = dict(re.findall(r'^\(defparameter (\*[a-z0-9-]+\*)\s+(t|nil|:[a-z0-9-]+|"[^"]*")(?=[\s)])', code, re.M))
rows = dict(re.findall(r'^\| `(\*[a-z0-9-]+\*)` \| `([^`]*)` \|', readme, re.M))
bad = [f"{k}: code {v}, README {rows.get(k, 'missing')}" for k, v in defaults.items()
       if k.startswith(("*install-", "*enable-", "*cuda-", "*jlink-version*", "*arm-none-eabi-version*",
                        "*kirocrew-version*", "*archify-chrome-build*", "*base-image*",
                        "*builder-base-image*", "*ubuntu-image*")) and rows.get(k) != v]
for b in bad: print("FAIL: README default", b)
if bad: sys.exit(1)
print(f"PASS: README defaults match the generator ({len(defaults)} scalar parameters checked)")
PY
echo "All generator tests passed."
