# deps.md — Abhängigkeiten für den vereinheitlichten Transpiler

Notation: `<organization>/<projekt>` (GitHub), direkt für DeepWiki-MCP-Abfragen
(`mcp_deepwiki_ask_wiki_question` mit `repoName`) verwendbar.

Legende Spalte „DeepWiki“: ✓ = am 2026-09-29 erfolgreich abgefragt,
? = nicht geprüft, ✗ = nicht indiziert.

## 1. Eigene Repositories (Referenz-Code, lokal unter `/workspace/src/`)

Die lokalen Checkouts haben **kein** `origin`-Remote bzw. meldet git
„dubious ownership“; für Lesezugriffe `git -c safe.directory='*' …` benutzen
(nicht die globale git-Config ändern).

| GitHub | Lokaler Pfad | Rolle | DeepWiki |
|---|---|---|---|
| `plops/cl-cl-generator` | `cl-cl-generator/` | Host-Repo; CL-Emitter (`emit-cl`) wird als CL-Backend wiederverwendet | ✓ |
| `plops/cl-cpp-generator2` | `cl-cpp-generator2/` | Referenz C++-Backend: Präzedenztabelle, `paren*`, `consume-declare`, Header/Impl-Split | ✓ |
| `plops/cl-py-generator` | `cl-py-generator/` | Referenz Python-Backend: tabellengetriebene Operatoren, `operand-needs-parentheses-p`, exakter Float-Druck, ruff-Erkennung | ✓ |
| `plops/cl-rust-generator` | `cl-rust-generator/` | Referenz Rust-Backend: `*rust-precedence*`, `strip-outer-parens`, 3-Tier-Tests (String/rustfmt/rustc) | ✓ |
| `plops/cl-golang-generator` | `cl-golang-generator/` | Referenz für Tier-B-Backend Go | ? |
| `plops/cl-js-generator` | `cl-js-generator/` | Referenz für Tier-B-Backend JavaScript (`ts.lisp` ist eine identische Kopie) | ? |
| `plops/cl-typescript-generator` | `cl-typescript-generator/` | nur `planning.md` interessant (TS-Konstrukte), Code = JS-Kopie | ? |
| `plops/cl-kotlin-generator`, `plops/cl-swift-generator`, `plops/cl-csharp-generator`, `plops/cl-julia-generator` | jeweils `cl-*-generator/` | Tier C (später), nur als Ideenquelle | ? |
| `HaxeFoundation/haxe` | — (extern) | Architektur-Vorbild: portable Stdlib (`std/` + `_std`, `@:coreApi`, `extern`/`@:native`), Filter `renameVars.ml`/`capturedVars.ml`, C++-Header/Impl-Split (`cppGenClassHeader.ml`) | ✓ |
| — (bewusst ausgeschlossen) | `cl-verilog-generator/`, `cl-tcl-generator/`, `cl-wolfram-generator/`, `cl-vba-generator/`, `cl-elixir-generator/`, `cl-erlang-generator/`, `cl-m-generator/`, `cl-r-generator/`, `cl-ada-generator/` | Begründung siehe `plan.md`, Abschnitt „Zielsprachen“ | ? |

## 2. Common-Lisp-Bibliotheken

Alle über Quicklisp ladbar; am 2026-09-29 im Container mit
`(ql:quickload '(:trivia :fiveam :named-readtables :alexandria :cl-ppcre))`
erfolgreich geladen.

| GitHub | ASDF-System | Version (geladen) | Status | Zweck | DeepWiki |
|---|---|---|---|---|---|
| `keithj/alexandria` (Mirror; Upstream: gitlab.common-lisp.net/alexandria) | `alexandria` | — | bestehend | Utilities (`with-gensyms`, `hash-table-keys`, `if-let`, …) | ? |
| `edicl/cl-ppcre` | `cl-ppcre` | 2.1.2 | bestehend | Regex: Identifier-Mapping, Whitespace-Normalisierung in Tests | ✓ |
| `fare/asdf` | `asdf`, `uiop` | (mit SBCL) | bestehend | System-Definition, `uiop:run-program` (Formatter/Compiler, portabel statt `sb-ext:run-program`), `uiop:read-file-string`, `uiop:with-temporary-file`, `uiop:quit` | ✓ |
| `guicho271828/trivia` | `trivia` | 0.1 | **neu** | Pattern-Matching im Frontend (Surface-S-Expr → IR) | ✓ |
| `lispci/fiveam` | `fiveam` | 1.4.3 | **neu** | Unit-Test-Framework, `asdf:test-system` | ✓ |
| `VincentToups/named-readtables` (Fork; Upstream: `melisgl/named-readtables`) | `named-readtables` | 0.9 | **neu** | Case-erhaltende Readtable (`:invert`) **ohne** globale Mutation von `*readtable*` | ✓ (Fork) |
| `Shinmera/parachute` | `parachute` | — | Alternative, **nicht** gewählt | Test-Framework-Alternative zu FiveAM | ✓ |

### Usage-Examples (aus DeepWiki, gekürzt)

**trivia** — Surface-Form in IR zerlegen:

```lisp
(trivia:match form
  ((list* 'if test then rest)
   (make-if-node :test test :then then :else (first rest)))
  ((guard (list* head args) (operator-symbol-p head))
   (make-binop-node head args)))
;; eigene Patterns: (trivia:defpattern name (args) ...) aus trivia.level2,
;; wird durch (ql:quickload :trivia) mitgeladen.
```

**named-readtables** — Readtable lokal pro Datei:

```lisp
;; in syntax.lisp (vor allen anderen Dateien laden)
(named-readtables:defreadtable polyglot-syntax
  (:merge :standard)
  (:case :invert))
;; am Anfang jeder DSL-/Beispiel-Datei
(named-readtables:in-readtable polyglot-syntax)
```

`in-readtable` bindet `*readtable*` nur für die gerade kompilierte/geladene
Datei (via `eval-when`), funktioniert mit ASDF `compile-file`/FASL. Das
ersetzt das bisherige `(setf (readtable-case *readtable*) :invert)`, das bei
jedem Laden die globale Readtable verändert (Seiteneffekt in c.lisp:5,
py.lisp:86, rs.lisp:20).

**fiveam** — Suite, Checks, CI-Exit-Code:

```lisp
(fiveam:def-suite :polyglot)
(fiveam:in-suite :polyglot)
(fiveam:test precedence-add-mul
  (fiveam:is (string= "1 + 2 * 3" (emit-expr :python '(+ 1 (* 2 3)))))
  (fiveam:signals unsupported-construct (emit-expr :python '(cpp:namespace x))))
;; Skript: exit != 0 bei Fehlern
(uiop:quit (if (fiveam:run! :polyglot) 0 1))
;; .asd: :perform (test-op (o c) (uiop:symbol-call :fiveam :run! :polyglot))
```

**uiop** — externer Formatter mit Exit-Code:

```lisp
(multiple-value-bind (out err code)
    (uiop:run-program (list "clang-format" "--style=llvm")
                      :input pathname :output :string
                      :error-output :string :ignore-error-status t)
  (if (zerop code) out (progn (warn "clang-format: ~a" err) nil)))
```

**cl-ppcre**:

```lisp
(cl-ppcre:regex-replace-all "\\s+" string " ")   ; Whitespace normalisieren
(cl-ppcre:split "\\n" string)                     ; Zeilen
(cl-ppcre:regex-replace-all "-" "foo-bar" "_")     ; kebab -> snake
```

## 3. Lisp-Implementierungen und Paketverwaltung

| GitHub | Rolle | Im Container | DeepWiki |
|---|---|---|---|
| `sbcl/sbcl` | Primäre Implementierung (Build, Tests, Syntax-Check nach jeder Änderung) | ✓ `/usr/bin/sbcl` 2.6.0 | ? |
| `roswell/ecl` (Mirror; Upstream: gitlab.com/embeddable-common-lisp/ecl) | Zweiter Syntax-/Portabilitäts-Check: `ecl --norc --load datei.lisp --eval '(ext:quit 0)'` | ✗ (apt: `ecl` 24.5.10 verfügbar) | ✓ |
| `quicklisp/quicklisp-client` | Laden der Bibliotheken; `~/quicklisp/local-projects/` | ✓ `/root/quicklisp` | ? |

Hinweis: `cl-cl-generator` ist **nicht** in `~/quicklisp/local-projects`
verlinkt; bestehende Skripte pushen den Repo-Pfad auf
`asdf:*central-registry*`.

## 4. Externe Werkzeuge (Formatter, Compiler, Laufzeiten)

| GitHub | Werkzeug | Backend | Einsatz | Im Container |
|---|---|---|---|---|
| `llvm/llvm-project` | `clang-format` | C++ | Formatter (optional, Warnung falls fehlend) | ✗ (apt: `clang-format` 21.1.6) |
| `gcc-mirror/gcc` | `g++` | C++ | Integrationstests: kompilieren und ausführen (`-std=c++20`) | ✓ 15.2.0 |
| `astral-sh/ruff` | `ruff format` / `ruff check` | Python | Formatter + Syntax-Check | ✓ `/workspace/.venv/bin/ruff` |
| `python/cpython` | `python3` | Python | Integrationstests ausführen | ✓ 3.14.4 |
| `rust-lang/rustfmt` | `rustfmt` | Rust | Formatter + Syntax-Check | ✓ |
| `rust-lang/rust` | `rustc`, `cargo` | Rust | Integrationstests kompilieren/ausführen | ✓ cargo 1.98.1 |
| `golang/go` | `go`, `gofmt` | Go (Tier B) | Formatter + Tests | ✗ (apt: `golang-go` 1.26) |
| `nodejs/node` | `node` | JavaScript (Tier B) | Tests ausführen | ✓ v22.22.1 |
| `microsoft/TypeScript` | `tsc` | TypeScript (Tier B) | Typcheck (`npx tsc --noEmit`) | ✗ (npm) |
| `prettier/prettier` | `prettier` | JS/TS (Tier B, optional) | Formatter | ✗ (npm) |
| — (lokal) | `/workspace/src/parenmedic/zig-out/bin/parenmedic` | alle `.lisp` | Klammer-Diagnose (`parenmedic diagnose --format=simple`), SBCL bleibt Ground Truth | ✓ |
