# Tasks: Refactoring `gen_ai_env.lisp`

> **Status 2026-11-19: umgesetzt** auf Branch `refactor/ai-env-generator`, siehe `walkthrough.md`.
> Abweichungen vom Plan:
> - T1.1–T1.7 und T2.1 sind ein Commit (`2ec881e`). Alle sind golden-neutral, und T2.1 ließ sich
>   mit der textuellen Golden-Methode (`golden/render.py`) ohne Ausgabeänderung umsetzen.
> - T2.2 nutzt `AI_ENV_NO_AUTOGEN`. Die Golden-Methode bleibt textuell; `setf` nach dem Laden
>   prüft `test_ai_env_generation.sh`.
> - T2.3 warnt nur bei KiroCrew ohne kiro-cli, nicht bei Unterfunktionen.
> - T2.4: `*rust-cache-volume*` entfernt statt `VOLUME` zu erzeugen.
> - T3.1: README-Defaults werden per Test geprüft, nicht generiert. T3.2 bewusst nicht umgesetzt.
> - KiroCrew hat niedrige Priorität. Getestet wurden vor allem muse, claude, kiro-cli und copilot.

Arbeite die Tasks **strikt der Reihe nach** ab. Jeder Task endet mit einer Validierung und
einem Commit. Abkürzungen: `03` = `source01/examples/03_ai_env`, `P` = dieser Plan-Ordner.

Gemeinsame Validierung (im Folgenden **V-Golden**):
```bash
P/golden/check.sh        # erzeugt alle Varianten in ein tmp-Verzeichnis und diffs gegen P/golden/*.Dockerfile
03/test_kirocrew_generation.sh
03/test_kirocrew_variants.sh
sbcl --non-interactive --eval '(require "asdf")' \
     --eval '(push (truename "source01/") asdf:*central-registry*)' \
     --eval '(asdf:load-system :cl-dockerfile-generator/tests)' \
     --eval '(cl-dockerfile-generator::run-all-tests)'
```

---

## Phase 0: Sicherheitsnetz

### T0.1 Golden-Variantenmatrix anlegen
- `P/golden/variants.lisp`: eine Tabelle `name → Flag-Belegung`. Mindestens: `default`, `all-on`,
  `all-off`, `no-cuda`, `kirocrew`, `emacs-no-sbcl`.
- `P/golden/check.sh`: erzeugt jede Variante. Die Flags werden **vor** dem Laden von
  `gen_ai_env.lisp` gesetzt (wegen F4, `defparameter` überschreibt sonst). Mit `--update` schreibt
  das Skript die Golden-Files neu, ohne `--update` vergleicht es per `diff -u`.
- Danach prüfen, dass `03/Dockerfile` unverändert ist (`git diff --exit-code`).
- **Validierung:** `check.sh --update` und danach `check.sh` liefern beide Exit 0.
- **Commit:** `test(ai-env): add golden Dockerfile variant matrix`

---

## Phase 1: Reines Refactoring (Golden-Diff muss leer bleiben)

### T1.1 DSL-Helfer für apt und Stage-Header (D1, D2)
- Konstante `+apt-cache-mounts+`, Funktion `apt-install (packages &key before)` → `run`-Form.
- `stage-header (title)` → Liste der drei `comment`-Forms. Achtung: Die Rahmenlängen 68/69 `=`
  unterscheiden sich heute. Vorerst Parameter für die Länge, damit der Diff leer bleibt. Die
  Vereinheitlichung kommt in T2.x als bewusster Diff.
- Alle 11 apt-Stellen und 8 Header ersetzen.
- **Validierung:** V-Golden leer.

### T1.2 Wrapper-Skripte vereinheitlichen (D5)
- `bash-script (&rest lines)` (Prolog `#!/usr/bin/env bash` + `set -euo pipefail`),
  `exec-wrapper (real flags)`. `grok-`, `muse-` und `devin-wrapper-script` sowie das unbenutzte
  `make-bash-script` entfernen. `kiro-cli-` und `kirocrew-wrapper-script` auf `bash-script` umstellen.
- Achtung auf exakte Whitespace-/Newline-Gleichheit (abschließendes `~%`).
- **Validierung:** V-Golden leer.

### T1.3 Builder-Stages zusammenführen (D3)
- `installer-builder-stage (stage-name title &key (packages '("ca-certificates" "curl")) extra-packages commands workdir comment)`.
- `builder-agy/copilot/claude/kiro/kirocrew/teamcity-stage` darauf umstellen, idealerweise als
  Datentabelle `*builder-stages*` mit `(flag-fn . args)`. `generate-ai-env` iteriert darüber.
- **Validierung:** V-Golden leer.

### T1.4 Binary-Wrapping vereinheitlichen (D4)
- `wrap-binary (name wrapper-script &key from src rename-op)` erzeugt die Folge
  „copy/mv → `.real`, Heredoc-Wrapper, chmod“. `rename-op` bildet die heutigen Varianten
  (`mv`/`cp`/direct copy) ab, damit der Diff leer bleibt. Die Vereinheitlichung kommt in T2.6.
- Auf agy, codex, copilot, claude, kiro-cli, kirocrew, grok, muse, devin anwenden.
- **Validierung:** V-Golden leer.

### T1.5 uv-/npm-Tool-Helfer (D6)
- `uv-tool-install`, `npm-global-install`. Auf habit-hooks, deptry, conan, jscpd, codex anwenden.
- **Validierung:** V-Golden leer.

### T1.6 `runner-stage` zerlegen
- Teilfunktionen `runner-base`, `runner-kirocrew`, `runner-apt`, `runner-quality-tools`,
  `runner-archify`, `runner-rust`, `runner-python`, `runner-agent-clis`, `runner-azure`,
  `runner-docker-cli`, `runner-firmware`, `runner-lisp`, `runner-extra-agents`, `runner-emacs`.
  `runner-stage` spleißt sie nur noch in der heutigen Reihenfolge.
- Die redundante Sammelbedingung `(or *install-codex* …)` entfernen. Den Kommentar
  „Install or copy other AI CLI tools“ dabei erhalten, sonst entsteht ein Diff. Seine Entfernung
  kommt in T2.x.
- Veraltete Nummerierungs-Kommentare im Lisp-Code entfernen (keine Auswirkung aufs Dockerfile).
- **Validierung:** V-Golden leer. `runner-stage` umfasst höchstens ca. 30 Zeilen.

### T1.7 `eval` ersetzen
- Makro oder Lambda-Tabelle für Bedingungen in `*dependency-packages*` und Smoke-Tests,
  z. B. `(feature-when (or *install-gcc* *install-rust*) …)`. Die Tabellen werden in Funktionen
  umgewandelt, damit sie zur Generierungszeit ausgewertet werden (bereitet F4 vor).
- **Validierung:** V-Golden leer.

---

## Phase 2: Bewusste Verhaltensänderungen (je ein Commit mit Golden-Update)

### T2.1 Abgeleitete Werte als Funktionen (F4)
- `base-image`, `python-libs`, `ubuntu-packages`, `arm-toolchain-name`, `jlink-directory` usw.
  werden zu Funktionen. Optional bleiben überschreibbare Parameter mit `nil` = „berechnet“.
- Neuer Test: Flag nach dem Laden mit `setf` ändern, dann `generate-ai-env`, und prüfen, dass
  `no-cuda` `FROM ubuntu:26.04 AS runner` und kein `polars` enthält.
- Die Golden-Methode in `check.sh` kann jetzt auf `setf` nach dem Laden umgestellt werden.

### T2.2 Kein Seiteneffekt beim Laden (F11, F12)
- `generate-ai-env (&key (output-path …) force)` ohne erzwungenes `ignore-hash`.
- Die Auto-Generierung beim Laden wird nur ausgeführt, wenn `AI_ENV_NO_AUTOGEN` nicht gesetzt ist.
  Alternativ ruft `setup00_generate_dockerfile.sh` `generate-ai-env` explizit auf.
- `test_kirocrew_variants.sh` vereinfachen (kein Aufräumen mehr nötig).

### T2.3 Konfigurationsvalidierung (F8, F7)
- `validate-config`: `warn` bei difftastic/probe-rs ohne Rust, `error` bei KiroCrew ohne kiro-cli.
  Emacs-Einrichtung von SBCL entkoppeln: Pakete und `.emacs` immer mit `*install-emacs*`,
  SLIME-Paket und der SLIME-Test nur mit SBCL.
- Variante `emacs-no-sbcl` im Golden aktualisieren.

### T2.4 Tote/doppelte Teile (F5, F6, F9)
- `*rust-cache-volume*`: entweder `VOLUME ["/root/.cargo"]` erzeugen (nur bei Rust) oder Schalter
  und README-Zeile entfernen. Prüfe dazu `setup02_run.sh`, das das Volume per `-v` mountet.
  Entscheidung im Commit begründen.
- Doppeltes `KIROCREW_BIND` entfernen. Den Kommentar zu `chmod 755 /root` korrigieren.

### T2.5 Smoke-Tests reaktivieren (F1, F2, F3)
- `#+nil`-Liste aktivieren, `*smoke-tests*` und `*kirocrew-smoke-tests*` zu einer Tabelle
  zusammenführen.
- C-/CUDA-/Rust-Code reparieren (Semikolons, überflüssige Leerzeilen) und am besten als
  `#r`-Strings statt `format` mit `~%` schreiben.
- CUDA-Test nur für `:devel`/`:cudnn-devel` erzeugen, dann ohne `if command -v nvcc`.
- Testskripte, die sich auf Netz-Versionen verlassen (Codex „matches latest npm release“),
  auf robuste Prüfungen beschränken.
- **Validierung zusätzlich:** Kleines CUDA-freies Testimage bauen (`*enable-cuda* nil`, gcc, rust,
  python, sbcl, emacs, docker-cli). `docker build` muss alle Smoke-Tests ausführen und bestehen.
  Das Build-Log in `P/logs/` ablegen.

### T2.6 Kosmetik am erzeugten Dockerfile
- Einheitliche Header-Rahmen, einheitliches Wrapping (`.real` per `mv`, nie `cp`), wo
  möglich `COPY --chmod=755 <<EOF` (dafür `gen.lisp` erweitern, `dock.lisp` neu erzeugen,
  Unit-Test ergänzen), „Stage 2“-Titel bereinigen.
- Golden-Diff im Commit kurz zusammenfassen.

---

## Phase 3: Dokumentation

### T3.1 README synchronisieren (F10)
- Alle `defparameter` bekommen einen Docstring. Ein Helfer (z. B. `print-parameter-table`)
  erzeugt die Markdown-Tabelle, oder ein Test vergleicht die README-Defaults mit dem Code.
- Fehlende Einträge ergänzen (claude, conan, probe-rs, devin-cli, kirocrew-version).
- Abschnitt „Reproduzierbarkeit / ungepinnte Quellen“ ergänzen.

### T3.2 Optional: Feature-Registry
- Nur umsetzen, wenn nach Phase 1–2 pro Feature immer noch mehr als 3 Stellen geändert werden
  müssen. Vorher kurz begründen. Die Layer-Reihenfolge muss erhalten bleiben.

### T3.3 Walkthrough
- `P/walkthrough.md` nach den Regeln in `prompt.txt` schreiben, danach committen.
