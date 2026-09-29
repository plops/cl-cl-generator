# worklog.md — Polyglot-Generator (Schritt-für-Schritt-Log)

Rohquelle für `walkthrough.md`. Pro Schritt: Datum, was gemacht wurde,
Testergebnisse, Abweichungen vom Plan und deren Ursachen.

## Schritt 0.1 — Toolchain (2026-09-29)

`apt-get install -y ecl clang-format golang-go emacs-nox` lief ohne
`apt-get update` durch. Quicklisp lud trivia, fiveam, named-readtables,
alexandria und cl-ppcre ohne Fehler.

| Werkzeug | Version | vorher im Container |
|---|---|---|
| sbcl | SBCL 2.6.0.debian | ja |
| ecl | ECL 24.5.10 | **nein** (apt) |
| g++ | 15.2.0 (Ubuntu 15.2.0-16ubuntu1) | ja |
| clang-format | 21.1.8 | **nein** (apt) |
| python3 | 3.14.4 | ja |
| ruff | 0.16.9 | ja |
| rustc | 1.98.1 | ja |
| cargo clippy | clippy 0.1.98 | ja |
| go | go1.26.0 linux/amd64 | **nein** (apt `golang-go`) |
| emacs | GNU Emacs 30.2 | **nein** (apt `emacs-nox`) |
| parenmedic | 0.1.0 | ja |
| cmake / ninja | 4.2.3 / vorhanden | ja |

## Schritt 0.2 — Gerüst, Syntax-Gate, leere Suite (2026-09-29)

- Angelegt: `.gitignore`, `polyglot-generator.asd`, `src/00-package.lisp`,
  `src/01-syntax.lisp`, `src/02-conditions.lisp`, `tools/lisp-check.{sh,lisp}`,
  `tools/reindent.el`, `run-tests.sh`, `tests/00-suite.lisp`,
  `tests/unit/test-syntax.lisp`.
- `tools/lisp-check.sh` kennt zusätzlich `--fix-indent` (Emacs-Reindent in
  place) und `--tests` (lädt auch das Testsystem).
- Abweichung: `reindent.el` registriert Einrückungsregeln für die eigenen
  Makros (`test`, `define-node`, …), sonst rückt Emacs sie wie Funktionen
  ein. Die `.asd` wird nicht indent-geprüft (ASDF-Stil weicht von
  `common-lisp-indent-function` ab).
- Abweichung: Das Testpaket importiert die internen `polyglot`-Symbole per
  `import` in einem `eval-when` statt per `shadowing-import`, weil SBCL sonst
  beim erneuten Laden eine Package-Variance-Warnung meldet (vom Gate als
  Fehler gewertet).
- Validierung: `tools/lisp-check.sh --tests --indent src/*.lisp tests/…` →
  `LISP-CHECK OK`; `./run-tests.sh` → 7 checks, 0 failures;
  `./run-tests.sh --ecl` → 7 checks, 0 failures; `lisp-check.sh --ecl` →
  `ECL LOAD OK`. Negativtest: Kopie ohne letztes `)` →
  `READ ERROR … form #8 (last good form started at line 43)`, Exit 1.
