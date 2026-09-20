# Walkthrough — Fix docker-gen (`03_ai_env`), Branch `fix/ai-env-apt-update`

## Was implementiert wurde

- Root Cause auf `origin/main` gefunden und behoben: Die Commits `0f1dc22`
  („configure for laptop") und `726b7dc` („more") hatten in
  `gen_ai_env.lisp` an neun Stellen das `"apt-get update"`-Element aus
  `(and "apt-get update" "apt-get install …")`-Formen entfernt. Ohne Update
  im selben RUN-Layer schlägt jeder `apt-get install` auf leeren
  Paketlisten fehl. Der Scratch-Check `/tmp/check_apt_update.sh` meldete 8
  verletzte RUN-Layer im committeten Dockerfile (nicht committet, Diagnose
  only); nach dem Fix 0.
- Kanonische Zwei-Element-Form wiederhergestellt (keine Inline-`&&`-Strings
  aus dem Working Tree übernommen): `builder-python/agy/copilot/kiro/
  teamcity`, Agent-Tool-Belt, Dependency-Loop, `azure-cli`, `docker-cli`.
- Toggle-Profil: committetes Laptop-Profil von `origin/main` behalten (CUDA,
  Emacs, Docker-CLI, Agy, TeamCity, Habit-Hooks aus). Die Workstation-Flips
  aus dem uncommitteten Working Tree (`*enable-cuda* t`,
  `*install-docker-cli* t`, `sudo`, ARM-/`clangd`-Auskommentierungen) wurden
  bewusst NICHT übernommen; eine Kopie liegt zur Referenz unter
  `/tmp/gen_ai_env.workstation-variant.lisp` (Container-lokal, nicht im Repo).
  Workstation-Rebuild: in `gen_ai_env.lisp` `*enable-cuda*` und
  `*install-docker-cli*` auf `t` setzen, `setup00` laufen lassen.
- `setup02_run.sh`-Verbesserungen behalten (uv-Cache-Mount/Verzeichnis,
  zusätzliche Source-Isolation-Mounts).
- `01_gentoo`: Kver-Bump 6.18.36→6.18.41 + Snapshots 20260824 als
  `chore`-Commit übernommen, Konsistenz verifiziert.
- Tests: `Test 11` in `source01/run_tests.lisp` (DSL-Regressionstest im
  bestehenden `assert-df`-Stil). DSL-Suite 0 Failures, Root-Suite
  `run-tests.sh` 7/7 grün. Determinismus: zwei `setup00`-Läufe → identisches
  sha256. `sh -n` auf allen `03_ai_env`-Skripten sauber.
- Commits: 6 Conventional Commits mit Body + Validierungsangabe
  (`chore` Plan-Moves, `fix` Generator, `test` Regressionstest, `feat`
  regenerierter Dockerfile + Run-Skript, `chore` Gentoo, `docs` Plan/Tasks),
  Fast-Forward-Merge nach `main`, Push ohne Force.

## Testbedingte Abweichungen vom Plan

- Keine inhaltlichen Abweichungen. Hinweis: Der Plan sprach von „ca. 8
  Stellen" — es sind 9 (5 Builder + Tool-Belt + Dependency-Loop + Azure +
  Docker); alle gefixt.
- Der `git diff --exit-code`-Determinismus-Check aus dem Plan war unpräzise
  formuliert (Diff gegen HEAD zeigt natürlich den Fix); korrekt validiert
  per sha256-Vergleich zweier aufeinanderfolgender `setup00`-Läufe.

## Learnings

- `git diff` in diesem Repo braucht `--no-ext-diff` NACH `diff`
  (`diff.external=difft` + Lisp-Diff-Driver zerbrechen externe Diffs).
- `parenmedic diagnose` meldet in `gen_ai_env.lisp` ab `*smoke-tests*`
  False Positives: `#r(…)`-Raw-Strings enthalten Shell/JS mit unbalancierten
  Klammern. Ground Truth ist `sbcl --load`, nicht parenmedic allein.
- Generierter `Dockerfile` ist eingecheckt: nach jeder Generator-Änderung
  `setup00` laufen lassen und das Artefakt mitcommitten, sonst driften
  Quelle und Artefakt auseinander (genau das war hier passiert).

## Mögliche Erweiterungen

- `setup02_run.sh`: `/home/kiel/stage/…`-Pfade per Env-Variable
  parametrisieren (bricht auf anderen Hosts).
- Generierungs-Determinismus als CI-Check (setup00 + `git diff --exit-code`).
- `*smoke-tests*` (npm-/Netzwerk-abhängig) offline-fähig machen.
- Voller `docker build` des AI-Env-Images steht aus (bewusst nicht gemacht:
  Dauer/Netzwerk/GPU); Folgeaufgabe.

## Programme für den Docker-Container

- Aus dieser Arbeit zwingend: keine. Der Fix ändert nur Layer-Inhalte,
  keine Paketliste.
- Kandidaten (nicht entschieden, je nach Profil): `sudo` (stand im Working
  Tree, nicht übernommen), `docker-ce-cli` + `docker-buildx-plugin` (nur im
  Workstation-Profil mit `*install-docker-cli* t` enthalten).
- `parenmedic` NICHT ins Image backen — als Host-Tool über den bestehenden
  Source-Isolation-Mount (`/workspace/src/parenmedic`, bereits in
  `setup02_run.sh`) verfügbar halten.
