## Goal

Die Änderungen auf `origin/main` (Commits `0f1dc22` „configure for laptop" und `726b7dc` „more", beide im Bereich `example/05_dockerfile_meta`, v. a. Generator `03_ai_env`) verstehen, die beabsichtigten Verbesserungen übernehmen, die darin enthaltenen Fehler beheben, per Tests validieren und sauber committen — am Ende soll ein funktionierender Stand auf `main` liegen und nach `origin` gehen.

## Success Criteria

- Der in `gen_ai_env.lisp` definierte Dockerfile-Transpiler erzeugt per `setup00_generate_dockerfile.sh` deterministisch einen Dockerfile, der ohne manuelle Nacharbeit baut.
- Alle `apt-get install`-RUN-Schritte im generierten Dockerfile enthalten ein `apt-get update` im selben Layer (der auf `origin/main` eingeführte Fehler ist behoben).
- DSL-Unit-Tests (`source01/run_tests.lisp`) und Repo-Tests (`tests.lisp`) laufen grün; neue Regressionstests für den `apt-get update`-Fehler existieren und laufen grün.
- Shell-Skripte (`setup*.sh`, `build.sh`) bestehen Syntaxchecks.
- Die Arbeit liegt auf einem Feature-Branch, ist in Conventional Commits mit ausführlicher Beschreibung committet und per Fast-Forward-Merge nach `main` gebracht (kein Force-Push, keine History-Rewrites).
- `plan/20260920_01_fix_docker_gen/task.md` (serielle Arbeitsliste) und nach Abschluss `plan/20260920_01_fix_docker_gen/walkthrough.md` existieren.

## Context And Current Facts

- Lokales `main` == `origin/main` (`726b7dc`). Zusätzlich gibt es uncommittete Änderungen im Working Tree (5 Dateien) und bereits gestagte Verschiebungen von Plan-Dateien nach `plan/20260717_01_improvements/`.
- Kernbefund (per `git diff --no-ext-diff 51de4bd..726b7dc` belegt): Die Commits auf `origin/main` haben in `gen_ai_env.lisp` an ca. 8 Stellen das Element `"apt-get update"` aus `(and "apt-get update" "apt-get install …")`-Formen entfernt. Ohne `apt-get update` im selben RUN-Layer schlägt `apt-get install` im Docker-Build fehl (leere/stale Paketlisten) — das ist der Fehler „funktioniert nicht richtig".
- Der uncommittete Working Tree enthält bereits einen Teil-Fix: `apt-get update &&` wurde als Inline-Präfix in die Install-Strings eingefügt, außerdem wurden `*enable-cuda*` (nil→t), `*install-docker-cli*` (nil→t), `"sudo"` und Auskommentierungen bei ARM-Toolchain-Paketen/`clangd` geändert sowie `setup02_run.sh` um uv-Cache-Mount und neue Source-Mounts (`rs_disk_treemap`, `pge_treemap`, `transpiled_treemap`, `parenmedic`) erweitert. Dieser Stand ist ungeprüft und uncommittet.
- Beabsichtigte Verbesserungen auf `origin/main`, die erhalten bleiben sollen: Laptop-Profil (schwere Optionen per Toggle abgeschaltet: `*enable-cuda*`, `*install-emacs*`, `*install-docker-cli*`, `*install-archify*`, `*install-agy*`, `*install-teamcity-cli*`, `*install-habit-hooks*`/`deptry`/`jscpd`), zusätzliche Ubuntu-Pakete im `03_ai_env`-Paketsatz, `BUILDKIT_LOCAL_SKIP_SET_FLAGS=1` in `setup01_build.sh`, Host-User-Identität statt `--user`-Flag plus `~/.local/share/muse`-Mount in `setup02_run.sh`.
- `01_gentoo`-Diff ist unkritisch: nur Versions-Bump `*kver*` 6.18.36→6.18.41 plus regenerierter Dockerfile, keine Logikänderung.
- Architektur: `source01/dock.lisp` (233 Zeilen) implementiert die DSL (`emit-df`, `run`/`and`/`seq`, `:mount`, `:heredoc`, `copy`, `#r`-Raw-Strings). `examples/03_ai_env/gen_ai_env.lisp` (760 Zeilen) definiert Toggle-Parameter, Builder-Stages und `runner-stage`; beim Laden schreibt es via `write-df` den `Dockerfile` im selben Verzeichnis (generiertes Artefakt, eingecheckt). `setup00_generate_dockerfile.sh` (sbcl lädt die Lisp-Datei), `setup01_build.sh` (docker build), `setup02_run.sh` (267 Zeilen, docker run mit Mounts/Isolation) bilden die Pipeline.
- Werkzeugbefund: `parenmedic diagnose` meldet in `gen_ai_env.lisp` ab Zeile 217 viele Paren-Fehler — das sind False Positives: die `#r(…)`-Raw-Strings in `*smoke-tests*` enthalten Shell/JS-Snippets mit unbalancierten Klammern (`require(…)`, `case…esac`), die parenmedic mitzählt. Ground Truth für Klammern ist `sbcl --load`, nicht parenmedic allein.
- Repo-Historie nutzt gemischte Commit-Stile (`feat(ai-env): …`, `docs(ai-env): …`, aber auch `more`, `add plan`). Externe Referenzen stehen in `examples/03_ai_env/deps.md` (DeepWiki-Lookup-Tabelle).

## Constraints And Non-goals

- Klammer-Disziplin (verbindlich vom Auftraggeber): vor jeder Lisp-Änderung ein Known-good-Backup (die existierenden `*.lisp~`-Dateien zeigen das Muster); parenmedic nach jeder Änderung laufen lassen, Ergebnis per SBCL-Load verifizieren; geänderte/neue Funktionen max. 60 Zeilen, Top-Level, schließende Klammern auf eigenen Zeilen.
- Kein Force-Push, kein Rebase/Amend fremder Commits, kein `reset --hard`. Der Zielstand geht per Merge (Fast-Forward) nach `main`.
- Keine neuen Abhängigkeiten ohne Eintrag in `deps.md` (Tabelle: Dependency → GitHub-Org/Projekt oder offizielle URL).
- Non-goals: kein Redesign der DSL in `dock.lisp` ohne Bedarf; kein Full-Rebuild-Nachweis des schweren `01_gentoo`-Images; keine Änderung an `reference/`-Dateien (Referenz-Dockerfiles, nicht generiert).

## Key Decisions

1. **Root Cause: fehlendes `apt-get update` (Fix-Priorität 1).** Alternative „Inline-`&&` wie im Working Tree" wird verworfen: Stattdessen kanonische Zwei-Element-Form `(and "apt-get update" "apt-get install -y …")` wiederherstellen — das entspricht dem Stand vor der Regression (`51de4bd`), nutzt die DSL wie vorgesehen (Emission `RUN … \<newline> && …`, vgl. `run_tests.lisp` Test 3) und bleibt klammerprüferfreundlich.
2. **Toggle-Profil klären, nicht raten.** `origin/main` schaltet bewusst auf Laptop-Profil (CUDA/Emacs/Docker-CLI/Agy/TeamCity/Habit-Hooks aus); der Working Tree schaltet CUDA + Docker-CLI wieder an. Entscheidung im Plan: Der committete `Dockerfile` muss byte-identisch das Produkt von `setup00` mit den committeten Default-Toggles sein; falls beide Profile gebraucht werden, als dokumentierte Profile (z. B. `laptop` vs. `workstation`), nicht als Mischzustand. Siehe offene Frage 1.
3. **Branch-Strategie: neuer Feature-Branch** (z. B. `fix/ai-env-apt-update`), uncommittete Änderungen dorthin übernehmen und aufteilen, validieren, dann Fast-Forward-Merge nach `main` und Push. „`main` auf origin ersetzen" wird als normaler Push des gemergten `main` interpretiert — kein Force-Push (verworfen: Risiko für andere Checkouts, keine Notwendigkeit).
4. **DeepWiki/Rust-Tooling nur bei Bedarf.** Die Recherche-Auflage aus dem Prompt (DeepWiki zu `plops/cl-cl-generator2`, neueste Rust-Tool-Versionen, Usage-Examples) greift nur, falls bei der Reparatur tatsächlich eine neue Abhängigkeit eingeführt wird. Aktuell ist keine nötig; DeepWiki-Abfragen und `deps.md`-Einträge sind daher konditionale Schritte, kein Pflichtblock.
5. **Validierungs-Tiefe nach Aufwand staffeln.** Generierung (Determinismus: zweimal generieren → `git diff` leer), DSL-Unit-Tests, Skript-Syntaxchecks und ggf. `docker build --check`/Hadolint sind billig und Pflicht. Ein vollständiger `docker build` des AI-Env-Images (Netzwerk-, GPU- und Zeit-abhängig) ist optional und nur mit explizitem OK auszuführen.

## Recommended Approach

1. Bestandsaufnahme auf Feature-Branch sichern (Stash/Staged-Plan-Moves als separater `chore`-Commit, Working-Tree-Änderungen sichten).
2. Minimaler Root-Cause-Fix in `gen_ai_env.lisp`: alle `apt-get install`-RUNs auf kanonische `(and "apt-get update" …)`-Form zurückführen; Toggle-Entscheidung (Frage 1) umsetzen.
3. Regressionstest einführen (DSL-Ebene + Generierungs-Ebene), bestehende Tests grün machen.
4. `Dockerfile` via `setup00` regenerieren und als generiertes Artefakt mitcommitten; Skripte (`setup02_run.sh`-Mounts, `setup01_build.sh`) prüfen und per `sh -n`/ShellCheck validieren.
5. Aufräumen: gestagte Plan-Moves, `~`-Backups und `output/`/`binpkgs/`-Artefakte nicht mitcommitten; Conventional Commits mit ausführlichem Body; Merge nach `main`, Push.
6. `task.md` zu Beginn schreiben (serielle Schritte mit Validierung je Schritt), `walkthrough.md` am Ende (inkl. Learnings, Container-Programmempfehlungen, Erweiterungen).

## Work Plan

Phasen mit Datei-Kontext (jede Datei: warum der Agent sie lesen muss):

| # | Schritt | Dateien (Kontext) |
| - | ------- | ----------------- |
| 0 | `task.md` in `plan/20260920_01_fix_docker_gen/` anlegen: serielle Schritte aus diesem Plan ableiten, jeder Schritt mit Validierungsbefehl | `plan/20260920_01_fix_docker_gen/prompt.txt` (Auftrag), dieser Plan |
| 1 | Branch `fix/ai-env-apt-update` erstellen; gestagte Plan-Moves als `chore: …`-Commit sichern; Working-Tree-Diff sichten (`git diff --no-ext-diff`, da `diff.external=difft` + Lisp-Driver externe Diffs zerbrechen) | `.gitattributes` (Lisp-Diff-Driver), `git log --format=%s` (Commit-Stile) |
| 2 | Fix in `gen_ai_env.lisp`: kanonische `(and "apt-get update" "apt-get install …")`-Form an allen ca. 8 Stellen (builder-python/agy/copilot/kiro/teamcity, tool-belt, dependency-loop, azure-cli, docker-cli); Toggle-Profil gemäß Antwort auf Frage 1 setzen | `example/05_dockerfile_meta/source01/examples/03_ai_env/gen_ai_env.lisp` (760 Zeilen, Ziel), `example/05_dockerfile_meta/source01/dock.lisp` (DSL-Semantik `and`/`run`/`:mount`), `example/05_dockerfile_meta/source01/run_tests.lisp` (Erwartungsformat Test 3) |
| 3 | Regressionstests: a) DSL-Test „jeder `apt-get install`-RUN enthält `apt-get update`" in `run_tests.lisp`-Stil; b) Generierungstest: `setup00` zweimal laufen lassen, `git diff --exit-code Dockerfile` muss leer sein | `example/05_dockerfile_meta/source01/run_tests.lisp` (112 Zeilen, Assert-Stil), `example/05_dockerfile_meta/source01/examples/03_ai_env/setup00_generate_dockerfile.sh` (Generierung), `tests.lisp` + `run-tests.sh` (Repo-Tests) |
| 4 | Skripte prüfen: `setup02_run.sh`-Änderungen (uv-Cache, neue Mounts) auf Pfadexistenz/host-Portabilität (`/home/kiel/stage/…` ist host-spezifisch!) prüfen, `sh -n` + ggf. ShellCheck; `setup01_build.sh`-Flag begründen | `example/05_dockerfile_meta/source01/examples/03_ai_env/setup02_run.sh`, `setup01_build.sh`, `setup03_save.sh`, `setup04_cleanup.sh`, `build.sh` |
| 5 | `Dockerfile` regenerieren, Diff gegen `reference/02_agy_env/Dockerfile` und committed `Dockerfile` prüfen; `01_gentoo`-Bump nur verifizieren (kein Fix nötig) | `example/05_dockerfile_meta/source01/examples/03_ai_env/Dockerfile` (Artefakt), `example/05_dockerfile_meta/reference/02_agy_env/Dockerfile` (Referenz), `example/05_dockerfile_meta/source01/examples/01_gentoo/gen_gentoo.lisp` + `Dockerfile` |
| 6 | Konditional: nur bei neuer Abhängigkeit DeepWiki-Abfrage (Repo `plops/cl-cl-generator2` bzw. neue Dep), Usage-Example in Plan übernehmen, `deps.md` ergänzen | `example/05_dockerfile_meta/source01/examples/03_ai_env/deps.md` (Tabelle), `example/05_dockerfile_meta/source01/examples/03_ai_env/skills_configuration_guide.md` |
| 7 | Commits nach Convention (siehe unten), `~`-Backups/`output/`/`binpkgs/` ausschließen (`.gitignore` prüfen); Merge nach `main`, Push; `walkthrough.md` schreiben | `.gitignore`, `plan/20260920_01_fix_docker_gen/` (Ziel für `task.md`, `walkthrough.md`) |

Commit-Message-Convention (Conventional Commits + ausführlicher Body, für den Agenten verbindlich):

```text
<type>(<scope>): <kurze imperative Zusammenfassung, max. ~72 Zeichen>

<Body: was war kaputt / was wurde geändert / warum so, 1–3 Absätze.>
<Validierung: welche Tests/Befehle liefen, mit Ergebnis.>
```

Typen: `fix` (Fehlerbehebung), `feat` (neue Fähigkeit/Toggle), `chore` (Ablage, Plan-Moves), `docs` (Pläne, Walkthrough), `test` (neue Tests). Scope z. B. `ai-env`, `gentoo`, `dockerfile-dsl`. Beispiel: `fix(ai-env): restore apt-get update in generated RUN layers`. Die bereits gestagten Plan-Datei-Verschiebungen werden ein separater `chore: organize plan files into dated directories`-Commit; Fix, Tests und regenerierter Dockerfile je eigene Commits in logischer Reihenfolge.

## Validation Plan

- `git diff --no-ext-diff --stat` (Pflicht: `diff.external=difft` zerbricht externe Diffs an Lisp-Dateien; immer `--no-ext-diff` nach `diff` stellen).
- `/workspace/src/parenmedic/zig-out/bin/parenmedic diagnose --format=simple <geänderte .lisp-Datei>` nach jeder Lisp-Änderung; False Positives durch `#r(…)`-Raw-Strings einkalkulieren.
- Ground Truth: `sbcl --load example/05_dockerfile_meta/source01/examples/03_ai_env/gen_ai_env.lisp` (muss fehlerfrei laden; der Load-Aufruf regeneriert den Dockerfile — vorher Backup) sowie `sbcl`-Load von `dock.lisp`/`run_tests.lisp`.
- Generierungs-Determinismus: `setup00_generate_dockerfile.sh` zweimal ausführen, danach `git diff --exit-code -- <Dockerfile>` — erwartet: leer.
- Unit-Tests: Repo-Tests via `run-tests.sh`; DSL-Tests in `source01/` nach deren Aufrufkonvention; neuer Regressionstest muss auf dem Stand `51de4bd` (ohne Fix) fehlschlagen und mit Fix bestehen (am besten per temporärem Checkout verifizieren, ohne den Branch zu beschmutzen).
- Skripte: `sh -n` auf alle `*.sh`; wenn verfügbar ShellCheck; `docker --version` (Host: 29.8.1 vorhanden) und `sbcl --version` dokumentieren.
- Optional/schwer (nur nach explizitem OK): vollständiger `docker build` des AI-Env-Images; `01_gentoo`-Build ist ausdrücklich ausgenommen.
- Höchstrisiko-Validierung: der SBCL-Regenerierungslauf — er beweist Fix + Klammern + Determinismus in einem Schritt, überschreibt aber das Artefakt (Backup-Pflicht).

## Risks / Rollback

- Klammerfehler in 760-Zeilen-Datei: Mitigation = Known-good-Backup vor jeder Änderung, kleine Diffs, parenmedic + SBCL-Load nach jedem Schritt; Rollback = Backup zurückkopieren (die `*.lisp~`-Dateien nicht löschen, bis der Branch gemergt ist).
- `setup02_run.sh` enthält host-spezifische Pfade (`/home/kiel/stage/…`): auf anderen Hosts bricht `--source-isolation` — im Walkthrough als Portabilitätslücke dokumentieren, ggf. per Env-Variable parametrisieren (nur wenn Frage-2-Antwort es abdeckt, sonst dokumentieren).
- Netzwerkabhängige Builder-Stages (Antigravity-, Copilot-, Kiro-, Azure-, Docker-Repos, `npm view`-Smoke-Tests) können flaky sein — Build-Validierung ggf. auf Generierungsebene beschränken und im Walkthrough vermerken.
- Rollback-Strategie gesamt: Feature-Branch verwerfbar bis zum Merge; nach Merge regulärer Revert-Commit statt History-Rewrite.

## Open Questions

1. Welches Toggle-Profil soll der committete `Dockerfile` abbilden — Laptop-Profil von `origin/main` (CUDA/Emacs/Docker-CLI/Agy/TeamCity/Hooks aus) oder Workstation-Profil des Working Tree (CUDA + Docker-CLI an)? Default-Empfehlung: Laptop-Profil behalten (kleineres, schneller bauendes Image), Workstation-Abweichungen als dokumentierte, nicht-committete lokale Änderung.
2. Ist ein vollständiger `docker build` des AI-Env-Images im Rahmen dieser Aufgabe gewünscht (Dauer, Netzwerk, ggf. GPU-Flag), oder genügt Generierungs- + Unit-Test-Validierung? Default-Empfehlung: ohne vollen Build mergen, Build als Folgeaufgabe in den Walkthrough aufnehmen.
3. Soll `01_gentoo` (nur Versions-Bump, keine Logikänderung) in denselben Branch/Merge oder separat behandelt werden? Default-Empfehlung: im selben Branch als eigener `chore`-Commit verifizieren, kein Extra-Branch.
4. Steht ein DeepWiki-MCP-Zugang im Ausführungs-Container zur Verfügung? Falls nein, entfallen die DeepWiki-Lookups; `deps.md` wird nur bei tatsächlich neuen Abhängigkeiten angefasst. (Keine neuen Programme für den Container aus dem Fix zwingend nötig — Kandidatenliste inkl. `sudo`, Docker-CLI und Mount-Empfehlung für `parenmedic` kommt in den Walkthrough.)

## Requirements-Lücken aus dem Prompt (Vorschläge des Plans)

- Der Prompt nennt keine Test-Erfolgskriterien: ergänzt (Success Criteria + Validation Plan).
- Keine Branch-/Merge-Vorgabe außer „main auf origin ersetzen": ergänzt (Feature-Branch + Fast-Forward, kein Force-Push).
- Keine Aussage zum kanonisierten Toggle-Profil des eingecheckten Dockerfile: als Frage 1 gestellt, mit Default-Empfehlung.
- Keine Scope-Abgrenzung für `01_gentoo` und `reference/`: als Non-goals festgezogen.
- Fehlend und ergänzt: Artefakt-Hygiene (generierter Dockerfile ja; `~`-Backups, `output/`, `binpkgs/` nein), host-spezifische Pfade in `setup02_run.sh`, Parenmedic-False-Positives durch `#r(…)`-Strings (Ground Truth SBCL).
- Mögliche sinnvolle Erweiterungen (nur Walkthrough-Kandidaten, kein Scope): `setup02_run.sh`-Pfade parametrisieren; Generierungs-Determinismus als CI-Check; Smoke-Tests (`*smoke-tests*`) auch offline-fähig machen; `sudo`-/Docker-CLI-Aufnahme ins Image entscheiden.
