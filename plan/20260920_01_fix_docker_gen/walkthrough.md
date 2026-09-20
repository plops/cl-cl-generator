# Walkthrough — Fix docker-gen (`03_ai_env`), Branch `fix/ai-env-apt-update`

## Korrektur zum Plan: das eigentliche `origin/main`

Der Plan analysierte die Commits `0f1dc22`/`726b7dc` — aber die lokale
`origin/main`-Ref war stale. Das echte `origin/main` ist `44bf7d3` („ai
broke the code, i started fixing but its not working again") mit 8 weiteren
Commits (`26c72bb`, `0610ef0`, `a3353ef`, `403c9ea`, `21d895d`, `3515bd3`,
`21cb08d`, `44bf7d3`). Der Branch wurde deshalb auf `44bf7d3` rebased; alle
Fixes wurden auf dem neuen Stand neu angewendet und validiert. Lesson:
vor Arbeitsbeginn immer `git fetch origin` ausführen.

## Was implementiert wurde

- `gen_ai_env.lisp` (Stand `44bf7d3`): kanonische
  `(and "apt-get update" "apt-get install …")`-Form an allen neun Stellen
  (builder-python/agy/copilot/kiro/teamcity, Agent-Tool-Belt,
  Dependency-Loop, azure-cli, docker-cli). Der Scratch-Check
  `/tmp/check_apt_update.sh` meldete 8 verletzte RUN-Layer im committeten
  Dockerfile (Diagnose only, nicht committet); nach dem Fix 0.
- `dock.lisp`: Ein-Zeichen-Klassen-Fix in `emit-df`. Der Keyword-Rewrite auf
  `origin/main` hatte eine schließende Klammer von Zeile 204 nach Zeile 203
  verschoben; dadurch wurde die äußere `(t (emit-val code))`-cond-Klausel zu
  einem separaten defun-Body-Form (Aufruf der undefinierten Funktion `t`,
  deren Argumentauswertung unendlich in `emit-df` rekursiert,
  Control-Stack-Exhaustion bei der ersten `(comment …)`-Form). Kein
  Dockerfile war mehr generierbar. Fix: Klammer zurückverschieben
  (203: 9→8, 204: 3→4 schließende Klammern). Gefunden per Reader-Struktur-
  Walk (cond hatte nur 2 statt 3 Klauseln) und Tree-Diff gegen `726b7dc`.
- `setup02_run.sh`: Das voll ausgestattete Skript (gpu, usb, kmsg,
  source-isolation, docker-sock, uv-Cache, zusätzliche Source-Mounts)
  wiederhergestellt. Der Minimal-Rewrite auf `origin/main` (31 Zeilen)
  kann den dokumentierten Start aus `prompt.txt`
  (`setup02_run.sh --gpu --host-kmsg --usb --source-isolation --docker-sock`)
  nicht ausführen; er wurde daher ersetzt. `sh -n` sauber.
- Runner-Stage reaktiviert: In der `toplevel`-Assembly waren alle Stages
  außer `builder-python` auskommentiert (Debug-Überrest der
  `emit-df`-Reparatur), sodass `setup00` nur einen 16-Zeilen-Dockerfile ohne
  Runner-Stage erzeugte. Splices wieder aktiviert; deaktivierte Komponenten
  bleiben über ihre `*install-*`-Toggle aus. Regen liefert 37 Direktiven,
  deterministisch, ohne Zeilenverlust gegenüber dem alten Artefakt.
- `01_gentoo`: Kver-Bump 6.18.36→6.18.41 + Snapshots 20260824 als
  `chore`-Commit übernommen, Konsistenz verifiziert (kein Fix nötig).
- Toggle-Profil: Laptop-Profil von `origin/main` beibehalten (keine
  Workstation-Flips committet).
- Tests: `Test 11` in `source01/run_tests.lisp` (DSL-Regressionstest im
  bestehenden `assert-df`-Stil). DSL-Suite 0 Failures (45 PASS), Root-Suite
  `run-tests.sh` 7/7 grün. Determinismus: zwei `setup00`-Läufe → identisches
  sha256. `sh -n` auf allen `03_ai_env`-Skripten sauber.
- Commits: 8 Conventional Commits mit Body + Validierungsangabe
  (`chore` Plan-Moves, `fix` Generator, `test` Regressionstest, `feat`
  regenerierter Dockerfile + Run-Skript-Restore, `fix` DSL-Nesting,
  `chore` Gentoo, 2× `docs` Plan/Walkthrough), Fast-Forward-Merge nach
  `main`, Push ohne Force.

## Testbedingte Abweichungen vom Plan

- Neun statt „ca. acht" `apt-get`-Stellen (azure-/docker-cli mitgezählt).
- Zusätzlicher `dock.lisp`-Fix (auf echtem `origin/main` war die Generierung
  komplett kaputt, nicht nur die Layer).
- `setup02_run.sh` wurde restauriert statt nur übernommen (Minimal-Rewrite
  hätte den dokumentierten Startbefehl gebrochen).
- Determinismus-Check per sha256 statt `git diff --exit-code` (letzterer
  zeigt gegen HEAD natürlich den Fix selbst).

## Learnings

- Immer `git fetch origin` vor der Analyse; stale Refs führen zu Arbeit auf
  falscher Basis.
- `git diff` braucht hier `--no-ext-diff` NACH `diff`
  (`diff.external=difft` zerbricht externe Diffs an Lisp-Dateien).
- `parenmedic diagnose` meldet in `gen_ai_env.lisp` ab `*smoke-tests*`
  False Positives (`#r(…)`/`#r|…|`-Raw-Strings mit Shell/JS-Klammern) und in
  `dock.lisp` an den `#\(`-Char-Literalen; Ground Truth ist `sbcl --load`.
- Diagnose-Rezept für „unhandled condition … quitting" mit
  Control-Stack-Exhaustion: Compile-Warnings lesen („The function t is
  undefined" zeigte hier direkt auf die falsch verschachtelte Klausel),
  dann Reader-Struktur-Walk statt Klammern von Hand zu zählen.
- Generierter `Dockerfile` ist eingecheckt: nach jeder Generator-Änderung
  `setup00` laufen lassen und das Artefakt mitcommitten.

## Mögliche Erweiterungen

- `setup02_run.sh`: `/home/kiel/stage/…`-Pfade per Env-Variable
  parametrisieren (bricht auf anderen Hosts).
- Generierungs-Determinismus als CI-Check (setup00 + `git diff --exit-code`).
- `*smoke-tests*` (npm-/Netzwerk-abhängig) offline-fähig machen.
- Voller `docker build` des AI-Env-Images steht aus (bewusst nicht gemacht:
  Dauer/Netzwerk/GPU); Folgeaufgabe.

## Voller Docker-Build (nachgereicht)

- `setup01_build.sh` läuft durch: alle 26 Runner-Steps grün, Image
  `my-ai-env:latest` (4.4 GB) gebaut und benannt.
- Build fand noch einen Generator-Fehler: Die `#r(…)`→`#r|…|`-Konvertierung
  hatte das schließende `'` der letzten `--eval`-Form im
  Quicklisp-Prefetch-RUN verschluckt (Step 18/26: „Unterminated quoted
  string"). Ein-Zeichen-Fix + Dockerfile-Regenerierung
  (`fix(ai-env): restore dropped quote in quicklisp prefetch RUN`).
- Smoke-Test im frischen Container: sbcl, python3, rustc, uv, devin,
  difft, muse, arm-none-eabi-gcc 15.3.1 funktionieren; `docker` und `node`
  fehlen per Design (Laptop-Toggle `*install-docker-cli*`/`codex` aus).
- Kernbeweis des `apt-get-update`-Fixes: `apt-get install -s curl` löst im
  finalen Image fehlerfrei auf (gültige Paketlisten in jedem Layer).

## Programme für den Docker-Container

- Aus dieser Arbeit zwingend: keine. Die Fixes ändern Layer-Inhalte und
  einen Paren-Fehler, keine Paketliste.
- Kandidaten (nicht entschieden, je nach Profil): `sudo`, `docker-ce-cli` +
  `docker-buildx-plugin` (nur im Workstation-Profil mit
  `*install-docker-cli* t` enthalten).
- `parenmedic` NICHT ins Image backen — als Host-Tool über den bestehenden
  Source-Isolation-Mount (`/workspace/src/parenmedic` in `setup02_run.sh`)
  verfügbar halten.
