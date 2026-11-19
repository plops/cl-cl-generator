# Review: `cl-dockerfile-generator` und `03_ai_env/gen_ai_env.lisp` (Stand 2026-11-19)

Grundlage: `gen.lisp` (Meta-Generator), `source01/dock.lisp` (erzeugter Transpiler),
`source01/run_tests.lisp`, `source01/examples/03_ai_env/gen_ai_env.lisp` (859 Zeilen),
das daraus erzeugte `Dockerfile`, `README.md`, die `test_kirocrew_*.sh`-Skripte sowie
die früheren Pläne (`plan/20260913_01_review`, `03_ai_env/plan/2026*`).

Geprüft: `./setup00_generate_dockerfile.sh` erzeugt ein Dockerfile, das byte-identisch
zum eingecheckten ist. Der Generator ist also deterministisch. Ein Refactoring kann deshalb
mit einem **Golden-Diff** abgesichert werden.

Die Punkte aus dem Review vom 2026-09-13 (`apt-get update`, `:link`/`:chmod`, mehrere
`:mount`, Keyword-Dispatch in `emit-df`) sind in `dock.lisp` inzwischen umgesetzt.

---

## 1. Funktionale Fehler und Irreführendes (zuerst beheben, jeweils eigener Commit)

| # | Befund | Stelle | Auswirkung |
|---|--------|--------|------------|
| F1 | Fast alle Smoke-Tests sind abgeschaltet: `*smoke-tests*` ist `()`, die eigentliche Liste steht hinter `#+nil`. Übrig bleibt nur der Kiro-CLI-ACP-Test. | `gen_ai_env.lisp:267`, `:287-417` | `*enable-tests*` = `t` suggeriert Testabdeckung, die es nicht gibt. Die README (Abschnitt Smoke-Tests) beschreibt Tests, die nicht laufen. |
| F2 | Den C-, CUDA- und Rust-Testprogrammen in der deaktivierten Liste fehlen die Semikolons (`puts("gcc-ok")`, `return 0`, `test_kernel<<<1, 1>>>()`). Dazu kommen merkwürdige `~%~%~%`-Leerzeilen. Das sieht nach einem Konvertierungsartefakt aus (`;` wurde als Lisp-Kommentar entfernt). | `:383-387` | Das Reaktivieren allein würde den Build brechen. Wahrscheinlich wurde die Liste genau deshalb abgeschaltet. |
| F3 | Der CUDA-Smoke-Test ist in `if command -v nvcc` eingewickelt und besteht stillschweigend, wenn `nvcc` fehlt. | `:383` | Bei `:cudnn-devel`/`:devel` kann so kein Fehler auffallen. Besser: nur für `devel`-Flavors erzeugen und dann hart prüfen. |
| F4 | Abgeleitete Parameter werden einmal beim Laden berechnet: `*base-image*`, `*python-libs*` (CUDA-abhängig), `*ubuntu-packages*` (GCC-abhängig), `*arm-none-eabi-toolchain*`, `*jlink-*`, `*dependency-packages*` (spleißt `*archify-browser-packages*` bei Ladezeit). | `:45`, `:81-152`, `:65-74`, `:547` | Wenn man ein Flag nach dem `load` per `setf` ändert (so arbeitet `test_kirocrew_variants.sh`), werden diese Werte **nicht** neu berechnet. Beispiel: `(setf *enable-cuda* nil)` liefert trotzdem `FROM nvidia/cuda…`, inklusive `polars`/`pyarrow`. |
| F5 | `*rust-cache-volume*` wird definiert und in der README dokumentiert, aber nirgends verwendet. Es wird kein `VOLUME` erzeugt. | `:181` | Ein toter Schalter, die Doku verspricht ein Verhalten, das es nicht gibt. |
| F6 | `KIROCREW_BIND` wird doppelt gesetzt (`:564` und `:592`). | runner-stage | Unnötige Layer, verwirrend. |
| F7 | Emacs-Paket (`emacs-nox`) wird bei `*install-emacs*` installiert, aber die Paket-Einrichtung und `.emacs` nur bei `(and *install-sbcl* *install-emacs*)`. Der Emacs-Smoke-Test lädt aber `/root/.emacs`. | `:550`, `:829` | Mit `*install-emacs* t` und `*install-sbcl* nil` scheitert der Test (sobald F1 behoben ist). |
| F8 | Feature-Abhängigkeiten werden nicht geprüft: `*install-difftastic*`/`*install-probe-rs*` brauchen Rust (wird stillschweigend ignoriert), `*install-kirocrew*` setzt `KIROCREW_KIRO_BIN=/usr/local/bin/kiro-cli.real`, also braucht es `*install-kiro-cli*`. | diverse | Inkonsistente Images ohne Fehlermeldung. |
| F9 | Der Kommentar zu `chmod 755 /root` sagt „The run script supplies the host UID/GID“. Laut KiroCrew-Plan läuft der Container aber bewusst als root. | `:578` | Veralteter Kommentar. |
| F10 | `README.md` weicht stark vom Code ab: Defaults für `*cuda-flavor*`, `*cuda-version*`, `*install-gcc*`, `*install-quicklisp*`, `*install-rust*`, `*install-arm-none-eabi*`, `*arm-none-eabi-version*`, `*install-jlink*`, `*jlink-version*`, `*install-copilot*`, `*install-kirocrew*`, `*install-muse*`. Es fehlen `*install-claude*`, `*install-conan*`, `*install-probe-rs*`, `*install-devin-cli*`, `*kirocrew-version*`. | README | Die Dokumentation ist als Referenz unbrauchbar. |
| F11 | Das Laden von `gen_ai_env.lisp` schreibt sofort das Dockerfile (Top-Level-`let` am Dateiende). | `:857` | Variantentests müssen danach „aufräumen“ (siehe Kommentar in `test_kirocrew_variants.sh`). |
| F12 | `generate-ai-env` ruft `write-df … t` (`ignore-hash`) auf. Damit wird die mtime-Optimierung von `write-df` ausgehebelt. | `:855` | Jeder Aufruf schreibt die Datei neu. |

## 2. Duplizierter Code

| # | Muster | Vorkommen | Vorschlag |
|---|--------|-----------|-----------|
| D1 | `(run :mount ("type=cache,target=/var/cache/apt,sharing=locked" "type=cache,target=/var/lib/apt/lists,sharing=locked") (and "apt-get update" "apt-get install -y --no-install-recommends …"))` | 11× | `(apt-install packages &key pre-commands)` → ein `run`-Form. Konstante `+apt-cache-mounts+`. |
| D2 | Drei `comment`-Zeilen mit `====`-Rahmen als Stage-Header, dazu unterschiedliche Rahmenlängen (`=` 68 vs. 69). | 8× | `(stage-header title)` → Liste von Forms. |
| D3 | Builder-Stages `agy`, `copilot`, `claude`, `kiro`, `kirocrew`, `teamcity` sind identisch aufgebaut: `from builder-base :as X`, `DEBIAN_FRONTEND`, apt `ca-certificates curl [+extra]`, `workdir`, `comment`, `run (and …)`. | 6 Funktionen, ca. 100 Zeilen | Eine Funktion `(installer-builder-stage name title &key packages commands)`, oder deklarativ als Tabelle `*builder-stages*`. |
| D4 | Das Wrapper-Muster „Binary → `X.real`, Heredoc-Wrapper nach `X`, `chmod +x`“ gibt es 9×. Es ist dazu inkonsistent: mal `mv`, mal `cp` (dann bleibt das Original liegen), mal `copy … X.real` direkt, mal separates `chmod` für `.real`. | agy, codex, copilot, claude, kiro-cli, kirocrew, grok, agent, muse, devin | `(wrap-binary name script-fn &key from-stage src)` liefert die drei bis vier Forms. Es gibt ein festes Namensschema `/usr/local/bin/<name>.real`. |
| D5 | `grok-wrapper-script`, `muse-wrapper-script` und `devin-wrapper-script` sind inhaltlich identisch mit `agent-wrapper-script` (nur ein anderes Flag). `make-bash-script` wird nirgends benutzt. `kiro-cli-wrapper-script` und `kirocrew-wrapper-script` duplizieren den Bash-Prolog. | `:219-265` | Eine Funktion `bash-script (&rest lines)` für den Prolog, eine `exec-wrapper (real flags)`. Den Rest löschen. |
| D6 | `uv tool install X` mit `--mount=type=cache,target=/root/.cache/uv` (habit-hooks, deptry, conan) und `npm install -g X` mit npm-Cache (jscpd, codex). | 5× | `(uv-tool-install spec comment)`, `(npm-global-install spec comment)`. |
| D7 | Paketlisten überlappen sich über Layer hinweg: `git` (Basis + `*ubuntu-packages*`), `build-essential` (`*ubuntu-packages*` + `*dependency-packages*`). `remove-duplicates` wirkt nur innerhalb einer Liste. | `:601`, `:548` | Pakete zentral sammeln und über alle Layer deduplizieren. Alternativ bewusst dokumentieren, dass die Layer unabhängig cachen sollen. |
| D8 | Feature-Bedingungen stehen an 3 bis 4 Stellen pro Feature (Flag-Definition, `*dependency-packages*`, Builder, Runner, Smoke-Test, README). Ein neues Feature erfordert Änderungen an weit auseinanderliegenden Stellen. | gesamt | Optional (Phase 3): Feature-Registry, siehe unten. |

## 3. Wartbarkeit und Lesbarkeit

- **`eval` auf Bedingungs-Ausdrücken** (`test-stage`, `*dependency-packages*`). Das funktioniert, ist aber
  schwer zu debuggen und fehleranfällig bei Symbolen aus fremden Packages. Besser ist ein Makro
  `(when-feature (or *a* *b*) …)` oder eine Liste von Lambdas, die zur Generierungszeit aufgerufen werden.
- **`runner-stage` ist eine einzige Funktion mit ca. 290 Zeilen.** Sie sollte in benannte Teilfunktionen
  aufgeteilt werden (`runner-env`, `runner-apt`, `runner-rust`, `runner-agent-clis`,
  `runner-firmware`, `runner-lisp`, `runner-emacs` …), die `runner-stage` nur noch der Reihe nach spleißt.
  Die Reihenfolge der Layer bleibt so explizit sichtbar.
- **Veraltete Nummerierung** in den Kommentaren („1.“, „2.“, „3.“, „4.“, „6.“, „Stage 2“).
- **Sammelbedingung** `(or *install-codex* *install-copilot* … *install-teamcity-cli*)` um den Block
  der KI-CLIs. Sie ist redundant (jedes Element hat eine eigene `when`) und vergisst agy/grok/muse.
- **Auskommentierte Pakete** mit kaputter Einrückung (`;"dnsutils"` in Spalte 40). Lieber als
  explizite, kommentierte Liste „optional“ führen oder entfernen.
- **Hart codierte Pfade** (`/workspace/src/cl-py-generator` …) für Quicklisp-Symlinks sollten als
  Parameter `*quicklisp-local-projects*` geführt werden.
- **Lange einzeilige Shell-Strings** (Emacs-Paketinstallation, Quicklisp-Prefetch, Azure-Repo-Setup).
  `run :heredoc` oder eine Lisp-Liste von Paketen/Systemen, aus der der Befehl erzeugt wird,
  machen sie lesbar und diffbar.
- **Gemischte Einrückung** (Tabs und Spaces, z. B. `:656-660`, `:814-826`).
- **Reproduzierbarkeit** (nur dokumentieren, nicht stillschweigend ändern): `uv:latest`,
  `codex@$(npm view …)`, `kiro-cli latest`, `rustup stable`, `probe-rs latest`,
  `archify-chrome stable`. Eine Liste in der README reicht. Pinning ist eine separate Entscheidung.
- **Sicherheit / Lieferkette** (nur dokumentieren): mehrere `curl … | sh`. Das ist für diese
  Entwicklungsumgebung akzeptiert, sollte aber als bewusste Entscheidung in der README stehen.

## 4. Kleinere Punkte in `dock.lisp` / `gen.lisp`

- `copy :heredoc` unterstützt keine Optionen (`:chmod`). Mit `COPY --chmod=755 <<EOF /usr/local/bin/x`
  ließe sich das separate `RUN chmod +x` je Wrapper sparen (D4). Das ist eine kleine Erweiterung in
  `gen.lisp`, danach `dock.lisp` neu erzeugen und einen Test in `run_tests.lisp` ergänzen.
- `:healthcheck` dupliziert die Logik von `emit-json-or-shell`.
- `parse-copy-add-args` wird auch für `healthcheck` benutzt. Der Name passt nicht mehr (`parse-options`).
- `read-balanced` kennt keine Strings/Escapes. Das ist bekannt und dokumentiert, keine Änderung nötig.

## 5. Vorgeschlagene Zielstruktur von `gen_ai_env.lisp`

```text
1. Setup / Package
2. Konfiguration: nur primitive Schalter und Versionen (defparameter)
3. Abgeleitete Werte als FUNKTIONEN (base-image, python-libs, ubuntu-packages, toolchain-names …)
4. validate-config: Abhängigkeiten prüfen (warn oder error)
5. DSL-Helfer: stage-header, apt-install, uv-tool-install, npm-global-install,
   bash-script, exec-wrapper, wrap-binary, installer-builder-stage
6. Daten-Tabellen: Builder-Stages, Dependency-Pakete (mit Lambda-/Makro-Bedingung), Smoke-Tests
7. Stage-Funktionen: builder-stages, runner-* Teilfunktionen, runner-stage, test-stage
8. generate-ai-env (&key output-path) – ohne ignore-hash
9. main: nur ausführen, wenn nicht explizit unterdrückt (z. B. Env-Var AI_ENV_NO_AUTOGEN)
   oder Generierung ganz in setup00_generate_dockerfile.sh verlagern
```

Optionale Phase 3 (nur bei klarem Mehrwert): ein Feature-Eintrag bündelt alles zu einem Tool:

```lisp
(deffeature :copilot
  :enabled *install-copilot*
  :builder (installer-builder-stage 'builder-copilot "GitHub Copilot CLI Download"
             :commands '("curl -fsSL https://gh.io/copilot-install -o copilot-install.sh"
                         "PREFIX=/usr/local VERSION=latest bash copilot-install.sh"
                         "rm copilot-install.sh"))
  :runner (wrap-binary "copilot" (exec-wrapper "--allow-all")
                       :from 'builder-copilot :src "/usr/local/bin/copilot")
  :smoke  ("Copilot CLI version" "copilot --version"))
```

Achtung: Die Layer-Reihenfolge im Runner bestimmt das Docker-Caching. Eine Registry darf die
heutige Reihenfolge nicht unbeabsichtigt ändern.
