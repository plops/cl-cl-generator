"""Copy gen_ai_env.lisp with rewritten defparameter defaults (test harness only)."""
import re, sys
src, dst, overrides = sys.argv[1], sys.argv[2], sys.argv[3:]
text = open(src).read()
for ov in overrides:
    name, value = ov.split("=", 1)
    pat = re.compile(r'(\(defparameter ' + re.escape(name) + r'\s+)(t|nil|:[a-z0-9-]+|"[^"]*")(?=[\s)])')
    text, n = pat.subn(lambda m: m.group(1) + value, text)
    if n != 1:
        sys.exit(f"override {name}: expected exactly one defparameter, found {n}")
open(dst, "w").write(text)
