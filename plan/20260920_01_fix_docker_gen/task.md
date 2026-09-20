# task.md — Fix docker-gen (`03_ai_env`): `apt-get update` restore + validate + merge

Derived from [plan.md](./plan.md). Work serially, top to bottom. Each step ends
with its validation before continuing. Defaults from plan approval apply:
laptop toggle profile for the committed `Dockerfile`, no full image build,
`01_gentoo` verified in-branch, no DeepWiki lookups (no new dependency).

Conventions for every Lisp edit (binding): known-good backup first (`cp file
file.bak-<step>`; keep `*.bak-*` out of commits), functions max. 60 lines /
top-level / closing parens on their own lines, afterwards
`parenmedic diagnose --format=simple` + `sbcl --load` as ground truth.

## Step 0 — Branch + triage (this task file)

1. `git checkout -b fix/ai-env-apt-update`
2. Commit the already-staged plan-file moves separately:
   `chore: organize plan files into dated directories`
3. Triage the uncommitted working tree (`git diff --no-ext-diff --stat`):
   - `gen_ai_env.lisp`: keep ONLY the `apt-get update` repair, converted to
     canonical `(and "apt-get update" "apt-get install …")` form; revert the
     toggle flips (`*enable-cuda*`, `*install-docker-cli*`, `sudo`, ARM/`clangd`
     comments) to the committed laptop profile.
   - `setup02_run.sh`: keep uv-cache + new source mounts.
   - `01_gentoo` (`*kver*` 6.18.36→6.18.41 + Dockerfile): keep, verify.
   - `03_ai_env/Dockerfile`: will be regenerated in Step 4, do not hand-edit.
- Validate: `git status -sb` shows branch + expected modified set; `git log
  --oneline -3` shows the chore commit on top.

## Step 1 — Reproduce the failure (authentic red)

1. Show the regression on `origin/main` state: every `(run … (and
   "apt-get install …"))` form without `"apt-get update"` in
   `gen_ai_env.lisp` (builder-python/agy/copilot/kiro/teamcity, tool-belt,
   dependency-loop, azure-cli, docker-cli).
2. Write the red proof to `/tmp/check_apt_update.sh` (scratch, NOT committed):
   after `setup00` regeneration, fail if any `RUN` line contains
   `apt-get install` without `apt-get update` in the same layer.
- Validate: script reports violations on the unfixed generator output.

## Step 2 — Fix `gen_ai_env.lisp` (canonical form)

Restore `(and "apt-get update" "apt-get install -y …")` at all ~8 sites
(see plan Work Plan #2 for the site list). No toggle changes, no DSL changes.
- Validate: backup exists; parenmedic clean (modulo known `#r(…)` false
  positives); `sbcl --load gen_ai_env.lisp` exits 0; `/tmp/check_apt_update.sh`
  passes on the regenerated Dockerfile.

## Step 3 — Durable regression tests (committed)

Extend `example/05_dockerfile_meta/source01/run_tests.lisp` in existing
`assert-df` style with a Test 11: `(run (and "apt-get update" "apt-get install
-y …"))` emits a single `RUN` containing both, and a negative guard that a
bare `(run "apt-get install …")` form does NOT contain `apt-get update`
(documents why the two-element form is mandatory).
- Validate: run suite —
  `sbcl --eval '(push (truename "example/05_dockerfile_meta/source01/")
  asdf:*central-registry*)' --eval '(asdf:load-system
  :cl-dockerfile-generator/tests)' --eval
  '(cl-dockerfile-generator::run-all-tests)'` → 0 failures; plus
  `run-tests.sh` (repo root suite) green.

## Step 4 — Regenerate + scripts + gentoo

1. `setup00_generate_dockerfile.sh` twice → `git diff --exit-code --
   <Dockerfile>` must be empty (determinism).
2. `sh -n` on all `03_ai_env/*.sh`; review `setup02_run.sh` mounts for
   host-specific paths (document, don't necessarily fix).
3. Verify `01_gentoo`: `*kver*` matches the ebuild filename/manifest lines in
   the regenerated Dockerfile.
- Validate: determinism diff empty; `sh -n` clean; kver consistent.

## Step 5 — Commit + merge + push

Commits (Conventional Commits with body + validation trailer, one concern
each): `fix(ai-env): …` (Step 2), `test(dockerfile-dsl): …` (Step 3),
`feat(ai-env): …Dockerfile` (regenerated artifact + setup02 keeps),
`chore(gentoo): …` (Step 4 kver bump). Exclude `*.bak-*`, `*~`, `output/`,
`binpkgs/`. Then fast-forward merge to `main`, push `main` (+ branch if
useful). No force-push, no rebase.
- Validate: `git log --oneline` order, `git status` clean, `git diff
  main...origin/main` empty after push.

## Step 6 — walkthrough.md

Write `plan/20260920_01_fix_docker_gen/walkthrough.md`: what was implemented,
test-driven deviations, learnings (parenmedic `#r(…)` false positives,
`--no-ext-diff`), possible extensions, programs to add to the container
(`sudo`, Docker CLI decision, `parenmedic` mount recommendation).
