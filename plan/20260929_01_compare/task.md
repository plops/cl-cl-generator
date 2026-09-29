# task.md — Polyglot-Generator (`example/13_polyglot_generator`)

Dieser Plan leitet sich aus [plan.md](./plan.md) ab (Stand Runde 3,
freigegeben). Er richtet sich an einen **unabhängigen AI-Agenten**, der die
komplette Implementierung in Common Lisp übernimmt.

**Arbeitsweise.** Arbeite **seriell von oben nach unten**. Jeder Schritt
endet mit seiner Validierung. Beginne einen Schritt erst, wenn der vorige
grün **und** committet ist. Fehlschläge werden nicht übersprungen, sondern
behoben. Ist ein Schritt nach zwei ernsthaften Anläufen nicht grün:
1. Ursache in `worklog.md` festhalten.
2. Einen grundsätzlich anderen Ansatz wählen.
3. Weicht dieser Ansatz von `plan.md` ab, **beim User nachfragen**.

**Verbindlich** sind `plan.md`, Abschnitte K1, K1b, K2, K3, K4, E1–E15,
R1–R20 und die „Annahmen“. Dieses Dokument legt zusätzlich die DSL-Syntax,
die Dateistruktur und die Reihenfolge fest.

---

## 0. Kontext-Aufbau (Pflichtlektüre vor Schritt 0.1)

Lies diese Dateien, bevor du Code schreibst. Die Zeilenangaben sind
ungefähr; suche im Zweifel nach dem Symbolnamen.

| Datei (relativ zu `/workspace/src/`) | Warum |
|---|---|
| `cl-cl-generator/plan/20260929_01_compare/plan.md` | Enthält alle Architektur-Entscheidungen (K1–K4, E1–E15, R1–R20); dieser Plan setzt sie nur um. |
| `cl-cl-generator/plan/20260929_01_compare/deps.md` | Liste der Bibliotheken und Werkzeuge samt DeepWiki-Namen und Usage-Beispielen für trivia, fiveam, named-readtables und uiop. |
| `cl-cl-generator/plan/20260929_01_compare/prompt.txt` | Der ursprüngliche Auftrag des Users (Rahmenbedingungen, Ausgabeordner). |
| `cl-cl-generator/cl.lisp` | `emit-cl` wird vom CL-Backend wiederverwendet; zeigt die pprint-Dispatch-Regeln für `toplevel`, `comment` und `raw`. |
| `cl-cl-generator/package.lisp`, `cl-cl-generator/cl-cl-generator.asd` | Exportierte API (`emit-cl`, `toplevel`, `comment`, `comments`, `raw`) und wie man das System als Abhängigkeit lädt. |
| `cl-cl-generator/run-tests.sh`, `cl-cl-generator/tests.lisp` | Konvention zum Bootstrapping: Repo-Pfad auf `asdf:*central-registry*` pushen, dann `ql:quickload`. |
| `cl-cl-generator/.agents/skills/parenthesis_matching/SKILL.md` | Bewährte Techniken, um Klammerfehler zu finden. **Unbedingt lesen.** |
| `cl-cl-generator/.agents/skills/cl-cl-generator/SKILL.md` | Stil der Repo-Beispiele (Backquote-Builder, `,@(loop …)`). |
| `cl-cl-generator/example/00_test/gen.lisp` | Kleinstes Beispiel für die Bootstrap-Präambel eines Generators im Repo. |
| `cl-py-generator/py.lisp` (≈ Z. 228–282, 321, 350–723) | Vorlage zum Portieren: Formatter-Erkennung, exakter Float-Druck, Operator-Tabellen, `operand-needs-parentheses-p`, `effective-operator`. |
| `cl-py-generator/transpiler-tests.lisp`, `cl-py-generator/paren-tests.lisp` | Format der Testtabellen, ruff-normalisierter Vergleich, Doku-Generierung, Zufalls-Differenztests (LCG, Seed 42). |
| `cl-cpp-generator2/c.lisp` (≈ Z. 152–256, 376–493, 887–1022, 1395–1433, 1543–1603) | Vorlage für C++-Präzedenz und `consume-declare`/`parse-defun`, **und** Anti-Muster: Semikolon-Heuristik und Hook-basierter Header-Split, die nicht übernommen werden. |
| `cl-cpp-generator2/t/02_paren_precedence/paren-tests.lisp` | C++-Wertetests mit g++ als Vorlage für die Zufallstests in Schritt 3.2. |
| `cl-cpp-generator2/example/149_shunting_yard/util.lisp` | Zeigt, wie der Header-Split bisher per `write-class` gelöst war, damit du ihn **nicht** so baust. |
| `cl-rust-generator/rs.lisp` (≈ Z. 247, 281, 320–328, 360, 471–482, 528–648) | Vorlage für Rust: Array-Typen, `render-parameter`, Block-Splicing, `strip-outer-parens`, `*rust-precedence*`, `non`-Assoziativität. |
| `cl-rust-generator/operator-precedence.md` | Quelle der Rust-Präzedenztabelle. |
| `cl-rust-generator/transpiler-tests.lisp` (≈ Z. 1341–1464) | Wertetests mit `rustc` und Syntaxprüfung per `rustfmt` als Vorlage. |
| `cl-golang-generator/go.lisp` | Nur Ideenquelle für Go-Syntax (`:=`, `defer`, Interfaces); nicht portieren. |
| `cl-cl-generator/plan/20260920_01_fix_docker_gen/{task.md,walkthrough.md}` | Stil früherer Pläne und Walkthroughs in diesem Repo. |
| `cl-cl-generator/example/05_dockerfile_meta/source01/examples/03_ai_env/gen_ai_env.lisp` | Aus dieser Datei entsteht das Container-Dockerfile; relevant für die Paketliste im Walkthrough. **Nicht verändern.** |

DeepWiki (MCP `mcp_deepwiki_ask_wiki_question`) nutzt du, wenn Fragen offen
sind:
- `HaxeFoundation/haxe`: `src/filters/renameVars.ml`,
  `src/filters/safe/capturedVars.ml`, `cppGenClassHeader.ml`.
- Die Bibliotheken aus `deps.md`.

---

## 1. Verbindliche Regeln

### 1.1 Klammer-Hygiene — LIES DAS ZWEIMAL

> **Warnung:** KI-Agenten sind bei Common Lisp **extrem anfällig für
> Klammerfehler**. Ein einziges fehlendes oder überzähliges `)` verschiebt
> die Struktur ganzer Funktionen. Der Fehler fällt oft erst viele Zeilen
> später auf, z. B. als „end of file“, „malformed let binding“ oder als
> Funktion, die plötzlich *innerhalb* einer anderen definiert ist. Solche
> Fehler kosten mehr Zeit als jede andere Fehlerklasse. Deshalb gelten die
> folgenden Regeln **ohne Ausnahme**:

1. **Pedantisch einrücken.** Standard-CL-Stil:
   - Rumpfformen von `defun`/`let`/`when`/`loop` um 2 Spalten eingerückt,
     Argumente untereinander ausgerichtet.
   - Schließende Klammern sammeln sich am Ende der letzten Zeile, nie auf
     eigener Zeile.
   - Die Einrückung **muss** die Klammerstruktur widerspiegeln. Wenn du
     beim Lesen eine andere Struktur siehst als der Reader, ist das ein
     Fehler.
   - Prüfe das mit `tools/lisp-check.sh --indent <datei>`: Die Datei wird
     mit Emacs neu eingerückt und verglichen. Jeder Diff zeigt, dass
     Einrückung und Klammern nicht zusammenpassen, und muss behoben werden.
2. **Winzige Schritte.**
   - Ein Edit ändert **genau eine** Toplevel-Form (`defun`, `defmacro`,
     `defclass`, `defmethod`, …) und höchstens ~40 Zeilen.
   - Mehrere Formen werden in mehreren Edits geändert, **nicht** in einem.
   - Schreibe zuerst kleine Hilfsfunktionen statt tief verschachtelter
     Formen (Richtwert: höchstens 7 offene Klammerebenen innerhalb einer
     Funktion).
3. **Nach jeder Änderung sofort prüfen:**
   `tools/lisp-check.sh <geänderte-datei>` muss mit `LISP-CHECK OK` enden,
   **bevor** du die nächste Änderung beginnst.
   - SBCL ist die Ground Truth. `parenmedic` ist ein zusätzlicher Hinweis
     mit bekannten Fehlalarmen, z. B. bei `#\(` und `#r(`.
   - An Phasen-Gates zusätzlich `--ecl`.
4. **Bei einem Fehler nicht weiterbauen:**
   - Erst die Ursache finden (Techniken aus `SKILL.md`: Tiefenprofil pro
     Zeile, Bisektion mit `#+nil`).
   - Nie „reparieren“, indem du Klammern am Dateiende anhängst oder
     entfernst.
   - Wenn es nach zwei Versuchen nicht klappt: auf den letzten grünen Stand
     zurück (`cp datei.bak-<schritt> datei` bzw.
     `git -c safe.directory='*' checkout -- datei`) und kleiner neu
     beginnen.
5. **Backups:** Vor jedem Edit über 20 Zeilen
   `cp <datei> <datei>.bak-<schritt>` anlegen (per `.gitignore`
   ausgeschlossen). Am Ende des Schritts wieder löschen.
6. **Backquote-Templates** (`` ` `` / `,` / `,@`) testest du immer mit
   einem Unit-Test auf das expandierte Ergebnis. Zeichenketten mit Klammern
   oder geschweiften Klammern, z. B. C++-Code-Schnipsel wie `"{}"`, legst
   du als benannte Konstanten ab, statt sie in tief verschachtelte Formen
   einzubetten.
7. **Größenlimits:** Funktionen ≤ 60 Zeilen, Dateien ≤ ~300 Zeilen, jede
   Datei hat genau eine Zuständigkeit. Wird eine Datei zu groß, teilst du
   sie auf, bevor du weiterschreibst.

### 1.2 Code-Konventionen

- **Portabilität:** Kein `sb-ext`/`sb-impl` im Kern. Externe Programme
  laufen über `uiop:run-program`, Dateien über `uiop`/`cl`.
- **Keine globale Mutation** von `*readtable*`. DSL- und Testdateien
  beginnen mit `(pg:in-dsl)`. Das Makro expandiert zu `in-readtable` für
  `polyglot-syntax` und setzt `*read-default-float-format*` innerhalb von
  `eval-when` auf `double-float`.
- **Fehler** sind Conditions aus `src/02-conditions.lisp`: `dsl-error`,
  `unsupported-construct`, `dsl-warning`. Sie enthalten immer die
  Quellform und, falls bekannt, das Backend. Kein `break`, kein
  `(error "string")` ohne Condition-Klasse.
- **Kommentare und Docstrings** schreibst du auf Englisch, jeden
  exportierten Namen mit Docstring.
- **Namen:** Paket `polyglot` mit Nickname `pg`. Die Erweiterungspakete
  sind `polyglot.cpp`, `polyglot.py`, `polyglot.rs` und `polyglot.go` mit
  den Nicknames `cpp`, `py`, `rs` und `go`.
- **Determinismus:** Bei der Ausgabe nie über Hash-Tables iterieren, ohne
  vorher zu sortieren.

### 1.3 Git-Vorgaben (strikt)

- **Wo:** Repo `/workspace/src/cl-cl-generator`, Branch `main`, **kein**
  neuer Branch. Die globale git-Config wird **nicht** verändert. Jeder
  Befehl läuft als `git -c safe.directory='*' …`.
- **Was:** Stage nur Pfade unter `example/13_polyglot_generator/` und die
  eigenen Plan-Dateien `plan/20260929_01_compare/{task.md,walkthrough.md,worklog.md}`,
  jeweils mit explizitem Pfad.
  - **Nie** `git add -A` oder `git add .`.
  - Fremde Änderungen im Arbeitsbaum bleiben **unberührt und unstaged**,
    z. B. `example/05_dockerfile_meta/…/Dockerfile`, `gen_ai_env.lisp`,
    `01_gentoo/binpkgs/` und `output/`.
- **Commit-Format:** jeder Commit im
  [Conventional-Commit](https://www.conventionalcommits.org/)-Format
  **mit ausführlichem Body**.

  ```
  <type>(<scope>): <imperative summary, max. 72 Zeichen>

  Was: <welche Dateien/Funktionen, was sie tun>
  Warum: <Bezug auf plan.md-Abschnitt / Requirement>
  Wie validiert: <exakte Befehle + Ergebnis, z. B. "./run-tests.sh: 57 checks, 0 failures">
  Einschränkungen: <bekannte Lücken oder "keine">

  Refs: plan/20260929_01_compare/task.md Schritt <X.Y>
  ```

  - `type` ∈ `feat, fix, test, refactor, docs, chore, build`.
  - `scope` ∈ `polyglot, ir, frontend, passes, printer, driver, backend-cl, backend-py, backend-cpp, backend-rust, backend-go, tests, docs, plan`.
- **Autor:** `git -c safe.directory='*' -c user.name="wol pumba" -c user.email="wolpumba@gmail.com" commit -F <msgfile>`,
  mit der Nachricht aus einer Datei, damit der Body erhalten bleibt.
- **Verboten:** Push (ohne ausdrückliche Freigabe des Users), `--amend`,
  `--no-verify`, `reset --hard`, `clean -f`, Rebase.
- **Takt:** mindestens ein Commit pro Schritt. Größere Schritte werden in
  mehrere Commits aufgeteilt, jeweils nur mit grünen Tests.

### 1.4 Validierungsbausteine

Die Schritte verweisen auf diese Bausteine:

| Kürzel | Befehl (cwd `example/13_polyglot_generator/`) | Erwartung |
|---|---|---|
| **V-SYN** | `tools/lisp-check.sh [--indent] <dateien…>` | endet mit `LISP-CHECK OK`, Exit 0 |
| **V-UNIT** | `./run-tests.sh` | FiveAM: 0 Failures, Exit 0 |
| **V-ECL** | `tools/lisp-check.sh --ecl src/*.lisp` bzw. `./run-tests.sh --ecl` | ECL lädt das System (ab Phase 1 mit Unit-Tests) |
| **V-INT** | `./run-integration.sh [programm…] [--targets cpp,rust,python,go,cl]` | alle Programme mit gleicher stdout wie die CL-Referenz und `expected.txt`, alle Idiomatik-Gates grün; fehlende Tools ⇒ `SKIPPED` (nie `PASS`) |
| **V-DOC** | `./run-tests.sh --docs-check` | `SUPPORTED_FORMS.md` ist aktuell |

Führe in `worklog.md` im Planungsordner ein fortlaufendes Log: pro Schritt
Datum, was gemacht wurde, Testergebnisse, Abweichungen vom Plan und deren
Ursachen. Es ist die Rohquelle für den Walkthrough.

---

## 2. DSL-Referenz (verbindliche Surface-Syntax)

Formen werden über den **Symbolnamen** erkannt (`string=` auf dem Namen
nach `:invert`). Das Paket des Symbols ist egal, außer bei den
Erweiterungspaketen `cpp:`, `py:`, `rs:` und `go:`.

**Projekt und Module (K2)**

```lisp
(defproject demo (:modules geometry app) (:entry app))
(defmodule geometry (:export point distance) (:import util (:std :math :io))
  item…)
```

**Items**

```lisp
(defconst max-size :int 100)
(defun name (a b) "doc" (declare …) body…)       ; kein &optional/&key im MVP ⇒ unsupported-construct
(defstruct point (:implements shape) (x :f64 0d0) (y :f64 0d0)
  (defmethod norm ((self :in)) (declare (values :f64)) …))
(definterface shape (:extends named)
  (defmethod area ((self :in)) (declare (values :f64)))             ; abstrakt
  (defmethod describe ((self :in)) (declare (values :string)) …))    ; Default
(defclass button (widget) (:implements clickable)
  (label :string "")
  (defmethod area ((self :in)) (declare (values :f64) (override)) (+ 1d0 (call-super))))
(defmethod area ((c circle :in)) …)               ; außerhalb: Receiver (name typ modus)
(defextern c-sqrt ((x :f64)) :f64
  (:cpp "std::sqrt" :includes ("<cmath>")) (:rust "f64::sqrt" :method t)
  (:python "math.sqrt" :imports ("math")) (:go "math.Sqrt" :imports ("math")) (:cl "sqrt"))
```

**Declare-Klauseln**

| Klausel | Bedeutung |
|---|---|
| `(type T v…)` | Typ von Variablen oder Parametern |
| `(values T)` | Rückgabetyp; fehlt die Klausel ⇒ `:void` |
| `(mode :in\|:inout\|:sink v…)` | Übergabemodus (K1) |
| `(borrows-from p…)` | Ergebnis leiht von p (K1b) |
| `(outlives :a :b)` | Region `:a` lebt mindestens so lange wie `:b` |
| `(virtual)` `(override)` `(abstract)` | Vererbung (K3) |
| `(pure)` | keine Seiteneffekte (E8) |
| `(capture :value\|:ref)` | Closure-Capture (E3); Default `:value` |

**Statements**

`let`, `let*`, `setf` (Paare), `incf`/`decf`, `if`, `when`, `unless`,
`cond` (mit `t` als Default), `while`, `dotimes (i n)`, `dolist (x seq)`,
`return`, `break`, `continue`, `progn`, `if-let (v expr)`,
`comment`/`comments`, `raw`, `(target-case (:cpp …) (:rust …) (t …))`.

**Ausdrücke**

- Literale: Integer, Double (`1d0`), String, Character, `true`/`false`,
  `nil` (nur im Sinne von E7).
- Arithmetik: `+ - *`; `/` nur für Floats; `truncate floor mod rem`.
- Vergleich: `= /= < <= > >=` (`=` gilt für alle Typen mit Gleichheit).
- Logik und Bits: `and or not`, `logand logior logxor lognot`,
  `shl shr`.
- Zugriff: `(dot obj feld [feld…])`, `(aref v i)`.
- Methodenaufruf: `(area c)`, also ein Funktionsaufruf, bei dem `resolve`
  eine Methode am Typ des ersten Arguments findet.
- Konstruktor: `(make-<struct> :feld wert …)`.
- Collections: `(vec-of T x…)`, `(map-of K V)`.
- Ownership: `(box x)`, `(clone x)`, `(move x)`, `(call-super args…)`.
- Funktionen: `(lambda (a) (declare …) body…)`, `(funcall f args…)`.
- Intrinsics (K4).

**Typen**

- Primitive: `:i8 :i16 :i32 :i64 :int :u8 :u16 :u32 :u64 :f32 :f64 :bool
  :string :char :void`.
- Zusammengesetzt: `(vec T)`, `(array T n)`, `(map K V)`, `(optional T)`,
  `(box T)`, `(dyn I)`, `(fn (T…) R)`.
- Geliehen (K1b): `(ref T [:region])`, `(mut-ref T [:region])`,
  `(view :string|(vec T) [:region|:static])`.
- Benannte Typen: Symbol.

**Makros:** `(pg:define-dsl-macro name (args) body…)` wird vor dem Parsen
expandiert (Tiefenlimit 100 ⇒ `dsl-error`).

**Intrinsics (K4, Mindestsatz):**
`print-line format-string length string-byte-length string-char-count push
vec-of map-get map-set map-contains map-keys-sorted string-concat sqrt abs
min max truncate floor mod rem clone move`. Die Argumentreihenfolge folgt
CL: `(push item place)`, `(map-get map key)`, `(map-set map key value)`.

---

## 3. Zielstruktur

Alles liegt unter `/workspace/src/cl-cl-generator/example/13_polyglot_generator/`.
Die ASDF-Komponenten sind `:serial t` in dieser Reihenfolge.

```
README.md                     Überblick, Schnellstart, Verweis auf SUPPORTED_FORMS.md
SUPPORTED_FORMS.md            aus der Spec-Tabelle generiert (nicht von Hand editieren)
polyglot-generator.asd        Systeme polyglot-generator und polyglot-generator/tests
run-tests.sh                  Unit- und Spec-Tests (FiveAM); --ecl, --docs, --docs-check
run-integration.sh            Tier-2/3-Tests der Programme unter tests/integration/programs
polyglot-gen.sh               CLI: polyglot-gen.sh <projekt.lisp> --targets … --out …
.gitignore                    build/, *.fasl, *.bak-*, *~
tools/lisp-check.sh|.lisp     Syntax-Gate (parenmedic, SBCL-Read/Load, --indent, --ecl)
tools/reindent.el             Emacs-Batch-Reindent (common-lisp-indent-function)
src/00-package.lisp           Pakete polyglot (pg), polyglot.cpp|py|rs|go
src/01-syntax.lisp            defreadtable polyglot-syntax, Makro in-dsl
src/02-conditions.lisp        dsl-error, unsupported-construct, dsl-warning
src/03-names.lisp             source-spelling (Umkehr von :invert), snake/pascal/camel/upper-snake
src/ir/10-node.lisp           define-node, Basisklasse, children/walk/rebuild
src/ir/11-types.lisp          Typ-IR: parse, Prädikate (copy-type-p, borrowed-p, regions)
src/ir/12-expr.lisp           Ausdrucksknoten
src/ir/13-stmt.lisp           Statementknoten
src/ir/14-items.lisp          function, param, struct, interface, class, method, const, extern, module, project
src/frontend/20-registry.lisp define-surface-form, define-dsl-macro, target-case, Erweiterungsformen
src/frontend/21-expr.lisp     Parser für Ausdrücke (trivia:match)
src/frontend/22-stmt.lisp     Parser für Statements
src/frontend/23-declare.lisp  declare-Klauseln
src/frontend/24-items.lisp    Parser für Items, defmodule, defproject
src/frontend/25-intrinsics.lisp define-intrinsic, defextern (Deklarationsseite)
src/passes/30-pipeline.lisp   Pass-Registry, Reihenfolge, Aktivierung per Capability
src/passes/31-desugar.lisp    when/unless/cond/dotimes/incf …
src/passes/32-resolve.lisp    Scopes, Symboltabelle, Signaturen, leichte Typableitung
src/passes/33-check.lisp      E1, E5, E7, E14, void-Returns, K1b-Mehrdeutigkeit
src/passes/34-mutability.lisp K1-Mutabilitätsinferenz
src/passes/35-vtable.lisp     Methodenauflösung und Vtables (K3)
src/passes/36-composition.lisp inheritance->composition (K3, für Rust/Go)
src/passes/37-rename.lisp     E3/E4: Rollen-Namen, reservierte Wörter, Shadowing, Kollisionen
src/passes/38-lower.lisp      E9/E10/E11
src/passes/39-order-args.lisp E8
src/passes/40-capability.lisp unsupported-construct
src/printer/50-writer.lisp    Zeilen- und Indent-Builder
src/printer/51-precedence.lisp generische Präzedenz-Engine (voll/minimal)
src/printer/52-literals.lisp  String-Escaping (E1), Floats (Round-Trip), Integer
src/backend/60-protocol.lisp  Klasse backend, generische Funktionen, Config, Artefakte
src/backend/cl/*.lisp         CL-Backend (Oracle; nutzt cl-cl-generator:emit-cl)
src/backend/python/*.lisp     Python-Backend
src/backend/cpp/*.lisp        C++-Backend (expr, stmt, items, split, build)
src/backend/rust/*.lisp       Rust-Backend (expr, stmt, items, lifetimes, cargo)
src/backend/go/*.lisp         Go-Backend
src/driver/80-artifacts.lisp  Artefakt-Struktur
src/driver/81-format.lisp     Formatter-Registry
src/driver/82-write.lisp      write-project (idempotent, Header-Kommentar, git-Hash)
src/driver/83-cli.lisp        Einstieg für polyglot-gen.sh
tests/00-suite.lisp           FiveAM-Suites
tests/unit/test-*.lisp        eine Testdatei pro src-Datei
tests/spec/*.lisp             Spec-Tabellen (plists), Runner, Doku-Generator
tests/paren/*.lisp            Zufalls-Präzedenztests
tests/integration/run.lisp    Runner für V-INT
tests/integration/programs/pNN_name/{project.lisp,expected.txt}
examples/01_shapes/{project.lisp,gen.lisp,source01/<target>/…}   committete Beispielausgabe
build/                        (gitignored) Ausgaben der Integrationstests
```

Bei Bedarf darfst du feiner aufteilen (Limit 300 Zeilen pro Datei). Jede
Abweichung von dieser Struktur hältst du in `worklog.md` fest.

---

## 4. Serielle Task-Liste

### Phase 0 — Vorbereitung

#### Schritt 0.1 — Toolchain installieren und erfassen

1. `apt-get install -y ecl clang-format golang-go emacs-nox`
   (`apt-get update` nur, falls nötig).
2. `sbcl --non-interactive --eval '(ql:quickload (list :trivia :fiveam :named-readtables :alexandria :cl-ppcre))'`.
3. Versionen von `sbcl`, `ecl`, `g++`, `clang-format`, `python3`, `ruff`,
   `rustc`, `cargo clippy`, `go`, `emacs` und `parenmedic` in
   `worklog.md` eintragen (Grundlage für Walkthrough §5).
- **Validierung:** Alle Befehle `--version` liefern Exit 0. Ist ein Paket
  nicht installierbar, notierst du das; die betroffenen Tests laufen
  später als `SKIPPED`.
- **Commit:** keiner, weil keine Dateien im Repo entstehen.

#### Schritt 0.2 — Gerüst, Syntax-Gate und leere Test-Suite

1. Ordner und `.gitignore` anlegen.
2. `polyglot-generator.asd` anlegen.
   - `:depends-on`: `alexandria`, `cl-ppcre`, `trivia`, `named-readtables`
     und `cl-cl-generator`.
   - Das Testsystem hängt zusätzlich von `fiveam` ab und definiert
     `:perform (test-op …)`.
3. `src/00-package.lisp`, `src/01-syntax.lisp` (`defreadtable` mit
   `(:merge :standard) (:case :invert)`, Makro `in-dsl`) und
   `src/02-conditions.lisp` anlegen.
4. `tools/lisp-check.lisp` und `tools/lisp-check.sh` schreiben:
   - (a) `parenmedic diagnose --format=simple` nur als Warnung.
   - (b) SBCL lädt die Abhängigkeiten, dann `00-package` und `01-syntax`,
     und liest jede übergebene Datei Form für Form mit
     `polyglot-syntax`. Bei einem Fehler gibt es Dateiname, Nummer der Form
     und Startzeile der letzten erfolgreich gelesenen Form aus.
   - (c) `asdf:load-system :polyglot-generator :force t`. Jede `warning`,
     die keine `style-warning` ist, gilt als Fehler.
   - (d) `--indent`: Emacs-Reindent einer Kopie mit `tools/reindent.el`,
     dann `diff -u`.
   - (e) `--ecl`: `ecl --norc --load ~/quicklisp/setup.lisp --eval …`
     (Registry-Push wie in `run-tests.sh`), lädt das System.
   - (f) Ausgabe `LISP-CHECK OK` bzw. Exit ≠ 0.
5. `run-tests.sh`:
   - pusht `../../` (Repo-Root, damit `cl-cl-generator` gefunden wird) und
     das eigene Verzeichnis auf `asdf:*central-registry*`,
   - lädt `polyglot-generator/tests`,
   - endet mit `(uiop:quit (if (fiveam:run! :polyglot) 0 1))`.
   - Ein Smoke-Test prüft, dass `(pg:in-dsl)` `Point` als gemischte
     Schreibweise liest.
6. **Negativtest für das Gate:** Kopiere eine Datei nach `/tmp`, entferne
   ein `)` und prüfe, dass `lisp-check.sh` sie ablehnt. Die Kopie wird
   danach gelöscht.
- **Validierung:** V-SYN auf allen Dateien (mit `--indent`), V-UNIT, V-ECL
  (nur Laden).
- **Commit:** `chore(polyglot): scaffold example 13 with asdf system, readtable and check tooling`.

### Phase 1 — Kern: generische Zwischenrepräsentation, Frontend, Passes, Printer, Driver

Jeder Schritt schreibt `tests/unit/test-<datei>.lisp` **zusammen mit** dem
Code. Ein Schritt ist erst fertig, wenn seine Unit-Tests existieren und
grün sind.

#### Schritt 1.1 — Namen (`src/03-names.lisp`)

- **Funktionen:**
  - `source-spelling`: Umkehr von `:invert`. Ein Name nur aus
    Großbuchstaben war ursprünglich klein geschrieben, einer nur aus
    Kleinbuchstaben groß; gemischte Namen bleiben und gelten als
    **verbatim**.
  - `to-snake`, `to-pascal`, `to-camel`, `to-upper-snake`.
- **Tests:** `point-3d` → `point_3d`/`Point3d`/`point3d`/`POINT_3D`;
  `Point`/`|HTTPServer|` bleiben verbatim; die leere Eingabe führt zu einem
  Fehler.
- **Validierung:** V-SYN, V-UNIT.
- **Commit:** `feat(frontend): add source-spelling and role-based case conversion`.

#### Schritt 1.2 — Knoten-Infrastruktur (`src/ir/10-node.lisp`)

- **`define-node name (supers) slots`** erzeugt:
  - die Klasse,
  - den Konstruktor `make-<name>` mit Keywords,
  - die Liste der Kind-Slots,
  - einen Slot `source` für die Quellform.
- **Weitere Funktionen:**
  - `node-children`
  - `walk-nodes`: Pre-Order mit Callback
  - `rebuild-node`: kopiert einen Knoten mit geänderten Slots, der
    Original-Knoten bleibt unverändert
- **Tests:** Konstruktion, Traversierung, `rebuild` verändert das Original
  nicht, `print-object` ist lesbar.
- **Validierung:** V-SYN, V-UNIT.
- **Commit:** `feat(ir): add define-node macro and generic traversal`.

#### Schritt 1.3 — Typ-IR (`src/ir/11-types.lisp`)

- **Typ-Parser** für alle Typformen aus §2. Ein ungültiger Typ führt zu
  `dsl-error` mit Quellform.
- **Prädikate:**
  - `copy-type-p`: Primitive plus `:char`/`:bool`; `:string` ist
    **kein** Copy-Typ.
  - `borrowed-type-p`
  - `type-regions`: liefert die benannten und unbenannten Regionen
    eines Typs.
- **Tests:** jede Typform, `(ref (vec :i64) :a)`,
  `(view :string :static)`, verschachtelte Typen, Fehlerfälle.
- **Validierung:** V-SYN, V-UNIT.
- **Commit:** `feat(ir): add type representation with borrow regions`.

#### Schritt 1.4 — Ausdrücke: Knoten und Parser (`src/ir/12-expr.lisp`, `src/frontend/20-registry.lisp`, `src/frontend/21-expr.lisp`)

1. **Registry:** `define-surface-form` registriert einen Parser unter dem
   Symbolnamen. Unbekannte Köpfe werden zu Aufrufknoten.
2. **Operatoren** werden auf abstrakte Op-Keywords abgebildet, z. B. `+` →
   `:add` und `/=` → `:ne`.
3. **Literale:**
   - Ein Single-Float-Literal führt zu `dsl-error` („use 1d0“), außer im
     `:f32`-Kontext.
   - `true`/`false`/`nil` werden gemäß E7 behandelt.
- **Tests:**
  - alle Operatoren und Literale
  - `(- x)` wird unär geparst
  - `(dot a b c)` als Kette
  - verschachtelte Aufrufe
  - Quellform im Fehlerobjekt
- **Validierung:** V-SYN, V-UNIT.
- **Commit:** `feat(frontend): parse expressions into IR`.

#### Schritt 1.5 — Statements (`src/ir/13-stmt.lisp`, `src/frontend/22-stmt.lisp`)

- **Formen:** alle Statements aus §2.
- **Fehlerfälle:** `setf` mit ungerader Argumentzahl und leeres `cond`
  führen zu `dsl-error`.
- **Tests:** eine Form pro Statement, Verschachtelung, Fehlerfälle.
- **Validierung:** V-SYN, V-UNIT.
- **Commit:** `feat(frontend): parse statements into IR`.

#### Schritt 1.6 — Declare, Funktionen, Lambdas (`src/frontend/23-declare.lisp`)

- **Umfang:** alle Declare-Klauseln aus §2.
- **Fehlerfälle:**
  - `&optional`/`&key` führen zu `unsupported-construct`.
  - Doppelte oder unbekannte Klauseln führen zu `dsl-error`.
- **Tests:** jede Klausel, ein Docstring vor `declare`, Mehrfach-Variablen
  in `type`.
- **Validierung:** V-SYN, V-UNIT.
- **Commit:** `feat(frontend): parse declare clauses, functions and lambdas`.

#### Schritt 1.7 — Items, Module, Projekt (`src/ir/14-items.lisp`, `src/frontend/24-items.lisp`)

- **Formen:** `defproject`, `defmodule` (Export/Import), `defconst`,
  `defstruct`, `definterface`, `defclass` (Basis, `:implements`),
  `defmethod` innerhalb und außerhalb von Klassen.
- **Normalisierung:** Der Receiver wird zu einem Parameter mit Modus. Die
  Sichtbarkeit ergibt sich aus `:export`.
- **Tests:**
  - ein Modul mit allen Items
  - Normalisierung der Receiver-Syntax
  - Export eines unbekannten Namens ⇒ `dsl-error`
- **Validierung:** V-SYN, V-UNIT.
- **Commit:** `feat(frontend): parse items, modules and projects`.

#### Schritt 1.8 — Makros, `target-case`, Erweiterungsformen

- **`define-dsl-macro`**
  - wird vor dem Parsen expandiert
  - Tiefenlimit 100
- **`target-case`**
  - wird erst beim Backend-Lauf aufgelöst
  - IR-Knoten `target-case` mit Zweigen je Backend
- **Erweiterungsformen**
  - Formen aus `cpp:`/`py:`/`rs:`/`go:` werden zu Knoten `target-form`
    mit Backend-Tag und roher Form.
  - Andere Backends lehnen sie im Capability-Pass ab.
- **Tests:**
  - Makro-Expansion, auch rekursiv
  - Endlosrekursion ⇒ `dsl-error`
  - `target-case` mit `t`-Zweig
- **Validierung:** V-SYN, V-UNIT.
- **Commit:** `feat(frontend): add dsl macros, target-case and extension forms`.

#### Schritt 1.9 — Intrinsics und Externs (`src/frontend/25-intrinsics.lisp`)

- **`define-intrinsic`**
  - Syntax wie in plan.md K4, Platzhalter `$name`
  - speichert Signatur plus Expansion pro Backend
  - Metadaten `:includes`, `:imports`, `:uses` und `:prelude`
- **`defextern`** analog.
- Die Deklarationen des Mindestsatzes (Signaturen) kommen **hier** hinein,
  die Expansionen pro Backend erst in den Backend-Schritten.
- **Tests:**
  - Registrierung und Lookup
  - fehlende Expansion für ein Backend ⇒ `unsupported-construct` beim
    Emittieren
- **Validierung:** V-SYN, V-UNIT.
- **Commit:** `feat(frontend): add intrinsic and extern registries`.

#### Schritt 1.10 — Pass-Pipeline und `desugar` (`src/passes/30-pipeline.lisp`, `31-desugar.lisp`)

- **`define-pass`**
  - Name, Abhängigkeiten, Aktivierungsbedingung über die Backend-Config
  - `run-passes backend project` gibt ein neues Projekt zurück
- **`desugar`**
  - `when`/`unless`/`cond` → `if`-Ketten
  - `dotimes` → `for-range`
  - `incf`/`decf` → Compound-Assign
- **Tests:**
  - Reihenfolge der Pipeline
  - Äquivalenz jeder Desugar-Regel als IR-Struktur
- **Validierung:** V-SYN, V-UNIT.
- **Commit:** `feat(passes): add pass pipeline and desugaring`.

#### Schritt 1.11 — `resolve` (`src/passes/32-resolve.lisp`)

- **Scopes:** Scope-Baum mit Bindungen; jeder Variablen-Ref zeigt auf ihre
  Bindung.
- **Symboltabelle** pro Projekt: Funktionen, Methoden pro Typ, Structs,
  Klassen, Interfaces, Externs, Intrinsics und importierte Namen.
- **Leichte Typableitung**
  - Umfang: Literale, deklarierte Variablen, Feldtypen, Rückgabetypen,
    Operatoren über gleiche Typen.
  - Ist ein Typ unbekannt, wird er `:unknown`. Das ist erlaubt, solange
    kein Backend ihn braucht.
- **Methodenaufrufe:** `(area c)` wird zum Methodenaufruf, wenn `area` am
  Typ von `c` existiert.
- **Tests:**
  - Shadowing wird korrekt gebunden
  - unbekannte Variable ⇒ `dsl-error`
  - Methodenauflösung, auch über Interfaces
  - Importe zwischen Modulen
- **Validierung:** V-SYN, V-UNIT.
- **Commit:** `feat(passes): resolve scopes, signatures and light types`.

#### Schritt 1.12 — `check` (`src/passes/33-check.lisp`)

- **Prüfungen:**
  - E5: Nicht-Copy-Wert ohne `clone`/`move` zugewiesen oder gebunden
  - E7: `nil` ohne bekannten Typ
  - E14: Float direkt an `print-line`
  - E1: `length` auf `:string`
  - nicht-`:void`-Funktion ohne `return` auf allen Pfaden
  - K1b: Referenz-Ergebnis mit mehreren Referenz-Parametern ohne
    `borrows-from`. Die Meldung nennt die Kandidaten.
- **Tests:** je ein Positiv- und ein Negativfall pro Regel. Die
  Fehlermeldung enthält die Quellform.
- **Validierung:** V-SYN, V-UNIT.
- **Commit:** `feat(passes): add semantic checks for ownership, nil, floats and borrows`.

#### Schritt 1.13 — Mutabilität (`src/passes/34-mutability.lisp`)

- **Markierung** einer lokalen Variablen als `mutable`, wenn sie
  - nach der Initialisierung zugewiesen wird,
  - an `incf`/`push`/`map-set` übergeben wird,
  - als `:inout` übergeben wird,
  - als Receiver einer `:inout`-Methode dient,
  - oder wenn auf eines ihrer Felder zugewiesen wird.
- **Tests:** jede Regel; unveränderte Variablen bleiben unveränderlich.
- **Validierung:** V-SYN, V-UNIT.
- **Commit:** `feat(passes): infer local mutability`.

#### Schritt 1.14 — Vtables (`src/passes/35-vtable.lisp`)

- **Methodenauflösung** pro konkreter Klasse: welche Implementierung
  jede virtuelle Methode erhält.
- **`call-super`-Ziel** jeder Methode.
- **Validierung** von `override` (Basis muss virtuell sein) und von
  abstrakten Methoden in konkreten Klassen.
- **Tests:**
  - drei Ebenen (Widget/Button/FancyButton)
  - fehlerhaftes `override` ⇒ `dsl-error`
  - Interface-Default-Methoden
- **Validierung:** V-SYN, V-UNIT.
- **Commit:** `feat(passes): compute method resolution and vtables`.

#### Schritt 1.15 — `rename` (`src/passes/37-rename.lisp`)

- **Konfigurierbar per Backend-Config:**
  - `:naming` (Rolle → Konvention)
  - `:reserved` (Liste)
  - `:escape` (Funktion)
  - `:shadowing` (`:allow` / `:block` / `:rename`)
  - `:private-prefix`
  - `:export-case` (Go)
- **Kollisionscheck** nach dem Mapping.
- **Tests** mit zwei Fake-Configs, einer Rust-ähnlichen und einer
  Python-ähnlichen:
  - `type` → `r#type` bzw. `type_`
  - `self` → `self_`
  - Shadowing wird umbenannt bzw. erhalten
  - Kollision `foo-bar`/`foo_bar` ⇒ `dsl-error`
  - Determinismus
- **Validierung:** V-SYN, V-UNIT.
- **Commit:** `feat(passes): add config-driven renaming for names, keywords and shadowing`.

#### Schritt 1.16 — `lower`, `order-args`, `capability` (`38-lower.lisp`, `39-order-args.lisp`, `40-capability.lisp`)

- **Lowering-Regeln:**
  - E9: `if`/`let` als Wert wird zu einem Ternär-Ausdruck oder zu einer
    Temporär-Variable plus Statements.
  - E10: Lambda-Lifting.
  - E11: Kommentare aus Ausdrücken vor das Statement verschieben, mit
    Warnung.
- **E8:** Argumente mit Seiteneffekten in Temporäre ziehen, wenn die
  Config `:unspecified-arg-order t` setzt.
- **Capability:**
  - Jeder Knotentyp und jedes Feature wird gegen `:supports` geprüft.
  - Nicht unterstützt ⇒ `unsupported-construct` mit Backend und Form.
- **Tests** mit Fake-Configs, je Regel ein Fall.
- **Validierung:** V-SYN, V-UNIT.
- **Commit:** `feat(passes): add expression lowering, argument ordering and capability checks`.

#### Schritt 1.17 — Printer (`src/printer/50-writer.lisp`, `51-precedence.lisp`, `52-literals.lisp`)

1. **Writer:** Zeilen und Indent-Ebenen, `with-block`, `emit-line`.
   Ausgabe mit `\n` und genau einem abschließenden Newline.
2. **Präzedenz-Engine:** verallgemeinert aus `py.lisp`
   (`operand-needs-parentheses-p`, `effective-operator`) und `rs.lisp`
   (`non`-Assoziativität).
   - Tabelleneintrag: `(:op :add :token "+" :level n :assoc :left|:right|:non :chain nil|t)`.
   - Modi `:full` und `:minimal`; der Modus `:full` ist das Oracle.
3. **Literale:**
   - String-Escaping pro Stil (`:c`, `:python`, `:rust`, `:go`, `:cl`)
     mit Option `:ascii-only`.
   - Float-Round-Trip nach dem Ansatz aus `py.lisp` (≈ Z. 321:
     `prin1` mit gebundenem `*read-default-float-format*`).
   - Negative Literale.
- **Tests:**
  - Präzedenz mit einer C-artigen und einer Python-artigen Tabelle,
    portiert aus `cl-py-generator/paren-tests.lisp`
    (`*effective-operator-cases*`)
  - Escaping von `"`, `\`, `\n`, Tab, NUL, `ä`, `😀`
  - Floats `0.1d0`, `1d300`, `-0d0`, `1d0`
- **Validierung:** V-SYN, V-UNIT.
- **Commit:** `feat(printer): add line writer, generic precedence engine and literal printing`.

#### Schritt 1.18 — Driver (`src/driver/80-artifacts.lisp`, `81-format.lisp`, `82-write.lisp`)

- **Artefakt:** Struktur `artifact` mit `path`, `kind` und `content`.
- **`write-project`**
  - Signatur: `(write-project project &key targets out (format t) (mode :minimal))`.
  - Pro Backend: Passes laufen, dann `module-artifacts`.
  - Jede Datei bekommt einen Header-Kommentar mit Generator, Quelldatei
    und git-Hash (`git -c safe.directory='*' rev-parse --short HEAD`,
    Fallback `unknown`).
  - Geschrieben wird nur, wenn sich der Inhalt auf der Platte
    unterscheidet.
  - Nach dem Schreiben läuft der Formatter.
  - Rückgabe: Liste `(pfad . :written|:unchanged)`.
- **Idempotenz:** Der Vergleich mit dem Dateiinhalt findet **nach** dem
  Formatieren statt. Dafür wird der Formatter auf eine temporäre Kopie
  angewendet (`uiop:with-temporary-file`), damit unveränderte Dateien
  unangetastet bleiben.
- **Formatter-Registry:** Kommando pro Backend. Fehlt es, gibt es genau
  eine Warnung pro Lauf.
- **Tests:**
  - zweiter Lauf ⇒ alle Dateien `:unchanged`, `file-write-date` gleich
  - Formatter-Name existiert nicht ⇒ Warnung, trotzdem geschrieben
  - Ausgabe mit Umlauten ist UTF-8
- **Validierung:** V-SYN, V-UNIT.
- **Gate Phase 1:** V-SYN `--indent` über `src/`, V-UNIT, V-ECL (System
  plus Unit-Tests).
- **Commit:** `feat(driver): add idempotent project writer and formatter registry`.

### Phase 2 — Backends (Portierung und Refactoring der sprachspezifischen Generatoren)

Für jedes Backend gilt dieselbe Struktur:
- eine Datei `config.lisp` mit Reserved-Liste, Naming, Capabilities,
  Operator-Tabelle und Formatter,
- danach je eine Datei für `expr`, `stmt`, `items` und `artifacts`,
- die Intrinsic-Expansionen stehen in `intrinsics.lisp`.

Portiere Tabellen und Wissen aus den Altgeneratoren, **nicht** deren
Architektur. Jeder Backend-Schritt erweitert die Spec-Tabelle
(`tests/spec/`) um die erwarteten Strings des Backends für alle bis dahin
unterstützten Formen. Ab Schritt 2.1 ergänzt jeder Schritt außerdem
Integrationsprogramme (siehe Phase 4, Liste in Schritt 4.2). Der Runner aus
Schritt 4.1 entsteht **vorgezogen in Schritt 2.1** in einer Minimalversion.

#### Schritt 2.1 — Backend-Protokoll und CL-Backend (Oracle) plus erster Durchstich

1. **`src/backend/60-protocol.lisp`**
   - Klasse `backend`
   - generische Funktionen `backend-config`, `emit-expr`, `emit-stmt`,
     `emit-item` und `module-artifacts`
   - Registry `find-backend`
2. **CL-Backend**
   - Die IR wird auf CL-S-Expressions abgesenkt und mit
     `cl-cl-generator:emit-cl` in `toplevel` gedruckt.
   - Pro Modul entstehen `defpackage`/`in-package` und eine Datei; dazu
     kommt die `.asd` des Projekts.
   - `print-line` wird zu `format t "~a~%"`, `format-string` wird auf CL
     `format` übersetzt (`{:.2f}` → `~,2f`).
3. **Integrations-Runner (Minimalversion):**
   - `tests/integration/run.lisp` und `run-integration.sh`
   - Pro Programm: `project.lisp` laden, dann `write-project` nach
     `build/<prog>/cl/`.
   - Ausführung in einem **separaten** `sbcl --non-interactive`-Prozess
     (ASDF lädt die generierte `.asd`, dann wird `main` aufgerufen).
   - stdout wird mit `expected.txt` verglichen.
4. **Programme:** `p01_hello` und `p02_arith` anlegen.
- **Validierung:** V-SYN, V-UNIT, `./run-integration.sh p01_hello p02_arith --targets cl`.
- **Commits:**
  - `feat(backend-cl): add backend protocol and common lisp oracle backend`
  - `test(tests): add integration runner with hello and arithmetic programs`

#### Schritt 2.2 — Python-Backend

- **Syntax:**
  - Einrückungsblöcke, `pass` bei leeren Blöcken (E2)
  - `@dataclass` für Structs, `ABC` für Interfaces, native Klassen mit
    `super()`
- **Module:**
  - `__all__` für Exporte, Präfix `_` für private Namen
  - Imports `from m import x`, Einstiegspunkt `if __name__ == "__main__":`
- **Semantik:**
  - Shadowing: `:rename`
  - Closures: `lambda x=x:` (E3)
  - `truncate`/`floor`/`mod`/`rem` gemäß plan.md (`floor` → `//`,
    `truncate` über `math.trunc`, `rem` über `math.fmod` bzw. eine
    Int-Variante in der Prelude)
- **Werkzeuge:** Formatter `ruff format`, Gate `ruff check`.
- **Validierung:**
  - V-SYN, V-UNIT (Spec-Strings Python)
  - `./run-integration.sh p01_hello p02_arith --targets cl,python`
- **Commit:** `feat(backend-py): add python backend`.

#### Schritt 2.3 — C++ Teil A: Ausdrücke, Statements, Funktionen, ein Modul mit Split

- **Typ-Mapping:**
  - `:int` → `std::int64_t`, `:string` → `std::string`
  - `vec`/`map`/`optional` → `std::vector`/`std::map`/`std::optional`
- **Modi (K1):** `const T&` / `T&` / `T`; Primitive per Wert.
- **Mutabilität:** unveränderliche Locals als `const auto`.
- **Split von Anfang an:** Auch ein Einzelmodul wird zu `.hpp` plus
  `.cpp`.
  - `.hpp`: `#pragma once`, `namespace`, öffentliche Prototypen
  - `.cpp`: privat im anonymen Namespace, Prototypen oben
- **Build:** `CMakeLists.txt` als Artefakt.
- **Werkzeuge:** Formatter `clang-format --style=llvm`.
- **Runner:**
  - `g++ -std=c++20 -Wall -Wextra -Werror -O0 *.cpp`
  - einmalig zusätzlich `cmake -G Ninja` plus Build
- **Validierung:** V-SYN, V-UNIT, `./run-integration.sh p01_hello p02_arith --targets cl,python,cpp`.
- **Commit:** `feat(backend-cpp): add c++ expressions, statements and single-module split`.

#### Schritt 2.4 — C++ Teil B: Mehrmodul-Split

- **Include-Analyse** nach dem Haxe-Muster (plan.md K2):
  - Typen, die per Wert benutzt werden, kommen als Include in den Header.
  - `box`, `dyn` und Referenzparameter werden im Header vorwärtsdeklariert.
  - Die `.cpp` inkludiert alles.
- **Typ-Ordnung:**
  - topologische Sortierung der Structs
  - Zyklus über Werte ⇒ `dsl-error`
- **Programm:** `p09_multimodule` anlegen (siehe 4.2).
- **Tests:**
  - Unit-Tests der Include-Analyse auf IR-Ebene
  - Spec-Strings für Header und `.cpp`
- **Validierung:** V-SYN, V-UNIT, `./run-integration.sh p09_multimodule --targets cl,python,cpp`.
- **Commit:** `feat(backend-cpp): add multi-module header analysis and forward declarations`.

#### Schritt 2.5 — C++ Teil C: Structs, Methoden, Interfaces, Vererbung, Views

- **Methoden:** `const`-Methoden bei Receiver `:in`.
- **Interfaces:**
  - Interfaces werden zu abstrakten Klassen mit virtuellem Destruktor.
  - `box`/`dyn` → `std::unique_ptr`.
  - `make-…` → Aggregat-Init bzw. `std::make_unique`.
- **Vererbung:** native, mit `public`, `virtual`/`override` und
  `Base::m()` für `call-super`.
- **Views und Referenzen:**
  - `view` → `std::string_view` / `std::span<const T>`.
  - `ref`-Felder → `const T*` mit automatischem `->`.
- **Programme:**
  - `p05_modes`, `p07_interfaces` und `p08_inheritance` anlegen (vorerst
    `--targets cl,python,cpp`)
  - `p06_borrows` nur C++-seitig vorbereiten
- **Validierung:** V-SYN, V-UNIT, V-INT für die genannten Programme.
- **Commit:** `feat(backend-cpp): add structs, interfaces, inheritance and views`.

#### Schritt 2.6 — Rust Teil A: Kern, Modi, Mutabilität, Cargo

- **Präzedenz:** Tabelle aus `rs.lisp`/`operator-precedence.md`.
- **Aufrufstellen:** automatisch `&x`/`&mut x` anhand der Signaturen (K1).
- **Bindungen:** `let` bzw. `let mut` gemäß Mutabilitäts-Pass.
- **Schleifen:** `for x in &v` / `&mut v` / `v`.
- **`Option`:** `if let Some(x)`.
- **Ausgabe:** `println!`/`format!`.
- **Namen:** Rollen-Naming (`PascalCase` für Typen) und `r#`-Escapes.
- **Module:** `main.rs` mit `mod`-Deklarationen, dazu `Cargo.toml`.
- **Prelude:** `floor`/`mod` für negative Zahlen korrekt, z. B. über
  `div_euclid` plus Korrektur oder eine Helper-Funktion.
- **Werkzeuge:**
  - Formatter `rustfmt --edition 2021`
  - Runner: `cargo build` und `cargo clippy -- -D warnings` mit
    gemeinsamem `CARGO_TARGET_DIR=build/_cargo`
- **Validierung:** V-SYN, V-UNIT, `./run-integration.sh p01_hello p02_arith p05_modes p09_multimodule --targets cl,python,cpp,rust`.
- **Commit:** `feat(backend-rust): add rust core with parameter modes and mutability`.

#### Schritt 2.7 — Rust Teil B: Structs, Traits, `dyn`, Lifetimes (K1b)

- **Structs** mit `impl`; Receiver `&self`, `&mut self` oder `self`.
- **Interfaces:** `trait` mit Default-Methoden, `impl Trait for X`,
  `Box<dyn Trait>`.
- **Lifetimes:**
  - Elision-Regeln implementieren; `borrows-from` erzeugt `<'a>`.
  - Structs mit Regionen bekommen `struct X<'a>` und `impl<'a>`.
  - `outlives` → `'a: 'b`.
- **Programm:** `p06_borrows` vollständig (`longest`, `Parser<'a>`,
  Slice-Iterator).
- **Negativtest:** fehlendes `borrows-from` ⇒ verständlicher
  `dsl-error` (Unit-Test).
- **Validierung:** V-SYN, V-UNIT, `./run-integration.sh p05_modes p06_borrows p07_interfaces --targets cl,python,cpp,rust`.
- **Commit:** `feat(backend-rust): add traits, dyn dispatch and lifetime generation`.

#### Schritt 2.8 — Kern-Erweiterung: `inheritance->composition` plus Rust-Vererbung

- **`src/passes/36-composition.lisp`:** Schritte 1–6 aus plan.md K3
  Stufe 2:
  - Basis als Feld `base`
  - Dyn-Trait pro Wurzel mit Accessoren
  - freie generische Funktionen für die Rümpfe
  - Delegation gemäß Vtable aus Schritt 1.14
  - Rewrites von `call-super`, Feldzugriffen und Konstruktoren
  - nicht-virtuelle Methoden
- **Aktivierung:** über die Capability `:implementation-inheritance nil`.
- **Tests:**
  - Unit-Tests auf IR-Ebene (Struktur der erzeugten Items)
  - `p08_inheritance` in Rust
- **Validierung:** V-SYN, V-UNIT, `./run-integration.sh p08_inheritance --targets cl,python,cpp,rust`, `clippy -D warnings`.
- **Commit:** `feat(passes): lower implementation inheritance to composition for rust`.

#### Schritt 2.9 — Go-Backend (Nachweis R3)

- **Regel:** Nur neue Dateien unter `src/backend/go/`. **Jede** Änderung
  außerhalb davon gilt als Kernänderung. Sie wird **vorher** in
  `worklog.md` begründet und im Commit-Body markiert
  (`Kernänderung: …`).
- **Namen:** Exporte `PascalCase`, private Namen `camelCase`.
- **Modi:** `:inout` → `*T` plus `&x` an der Aufrufstelle.
- **Vererbung:** Interfaces nativ; Vererbung über denselben
  Composition-Pass.
- **Projekt:** Package-Verzeichnis pro Modul, Entry `package main`,
  `go.mod` (`module <projekt>`, `go 1.22`).
- **Werkzeuge:** Formatter `gofmt`; Runner `go vet ./...` und `go run .`.
- **Validierung:** V-SYN, V-UNIT, `./run-integration.sh --targets cl,python,cpp,rust,go` (alle bisherigen Programme).
- **Commit:** `feat(backend-go): add go backend without core changes`
  bzw. mit markierten Kernänderungen.

#### Schritt 2.10 — Intrinsics vervollständigen, Prelude-Audit

- **Vollständigkeit:** Jedes Intrinsic aus §2 hat eine Expansion in allen
  fünf Backends.
- **Prelude:** Sie wird nur erzeugt und eingebunden, wenn ein Intrinsic sie
  braucht. Test: `p01_hello` erzeugt **keine** Prelude.
- **Programm:** `p04_collections` anlegen (Map mit `map-keys-sorted`,
  `clone`/`move`).
- **Validierung:** V-SYN, V-UNIT, V-INT (alle Programme, alle Targets).
- **Commit:** `feat(backend-cl): complete portable intrinsics and on-demand preludes`.
  Nimm den Scope des Backends, das am meisten geändert wurde, oder
  `polyglot`.
- **Gate Phase 2:** V-SYN `--indent` über alles, V-UNIT, V-ECL, V-INT.

### Phase 3 — Unit-Tests und Spezifikation

#### Schritt 3.1 — Spec-Tabelle vervollständigen und Doku generieren

- **Spec-Einträge:**
  - Jede Surface-Form aus §2 hat mindestens einen Eintrag der Form
    `(:name :tags :lisp :expect (:cl … :python … :cpp … :rust … :go …))`
    mit erwarteten Strings pro Backend.
  - Der Vergleich normalisiert Whitespace (`cl-ppcre`).
  - Formen, die ein Backend bewusst nicht unterstützt, tragen
    `:expect-error unsupported-construct`.
- **Doku:**
  - `./run-tests.sh --docs` erzeugt `SUPPORTED_FORMS.md` mit Tabellen pro
    Tag.
  - `--docs-check` scheitert, wenn die Datei veraltet ist.
- **Validierung:** V-UNIT, V-DOC.
- **Commit:** `test(tests): complete spec table and generate SUPPORTED_FORMS.md`.

#### Schritt 3.2 — Zufalls-Präzedenztests pro Backend

- **Vorlagen:** `cl-py-generator/paren-tests.lisp` und
  `cl-cpp-generator2/t/02_paren_precedence/`.
- **Ausdrücke:**
  - 400 zufällige Ausdrücke der Tiefe 3, LCG mit Seed 42
  - über `:int` mit festen Variablen `a=7, b=3, c=2, d=5`
- **Vergleich:** Jeder Ausdruck wird in beiden Modi (`:full`/`:minimal`)
  in **ein** Programm pro Backend geschrieben und ausgeführt. Die Werte
  müssen gleich sein **und** gleich dem CL-Wert.
- **Division:** Nur `truncate`/`floor`/`mod`/`rem` mit Nenner ≠ 0
  (Generator erzwingt `(+ 1 (abs x))` im Nenner).
- **Laufzeit** unter 2 Minuten; fehlende Compiler ⇒ `SKIPPED`.
- **Validierung:** `./run-tests.sh --paren` grün für alle vorhandenen
  Toolchains.
- **Commit:** `test(tests): add randomized precedence differential tests for all backends`.

#### Schritt 3.3 — Abdeckungs-Audit

- **Liste** in `worklog.md`: Jede Condition-Klasse, jede Check-Regel und
  jeder Pass hat mindestens einen Negativtest. Jede Datei unter `src/` hat
  eine Testdatei.
- **Lücken** werden geschlossen.
- **Validierung:** V-UNIT.
- **Commit:** `test(tests): close unit test coverage gaps`.

### Phase 4 — Integrationstests (Validierung des generierten C++/Python/Rust/Go/CL-Codes)

#### Schritt 4.1 — Runner fertigstellen

- **Zusammenfassung:** eine Tabelle Programm × Target mit
  `PASS`/`FAIL`/`SKIPPED` und der Zeit.
- **Fehlerdiagnose:** Bei `FAIL` werden Diff und Compiler-Log nach
  `build/<prog>/<target>/failure.log` geschrieben.
- **Idiomatik-Gates** gehören zum `PASS`:
  - Rust: `cargo clippy -- -D warnings`
  - Python: `ruff check`
  - C++: `g++ -Wall -Wextra -Werror`
  - Go: `go vet`
- **Exit-Code** ≠ 0 bei jedem `FAIL`.
- **Validierung:** V-INT.
- **Commit:** `test(tests): finalize integration runner with idiomatic gates`.

#### Schritt 4.2 — Programmsuite vervollständigen

Jedes Programm besteht aus `project.lisp` und `expected.txt`. Die Datei
`expected.txt` wird **einmal** aus dem CL-Lauf erzeugt, von dir auf
Plausibilität geprüft und committet. Pro Programm ein Commit.

| Programm | Inhalt / was es prüft |
|---|---|
| `p01_hello` | `print-line`; Umlaute, CJK, Emoji; Escapes `"`, `\`, Tab, Newline (E1) |
| `p02_arith` | Ganzzahl-Operatoren, `truncate`/`floor`/`mod`/`rem` mit negativen Operanden, verschachtelte Präzedenz, `format-string "{:.6f}"`, Bit-Operatoren |
| `p03_control` | `cond`, `while`, `dotimes`, `dolist`, `break`/`continue`, Shadowing in verschachtelten `let` (E3), `if` als Wert (E9), leere Blöcke (E2) |
| `p04_collections` | `vec`, `push`, `aref`, `length`, `map-set`/`map-get`/`map-keys-sorted`, `clone`: Kopie ändern, Original bleibt; `move` (E5, E15) |
| `p05_modes` | Struct `point`, `:inout`-Mutation, `:sink`, `optional` plus `if-let`, Mutabilitäts-Inferenz (K1) |
| `p06_borrows` | `longest` mit `borrows-from`, `Parser<'a>` über `(view :string)` mit `next-token`, Slice-Iterator (K1b) |
| `p07_interfaces` | Interface `shape` mit Default-Methode, `circle`/`rect`, `(vec (box (dyn shape)))` (K3 Stufe 1) |
| `p08_inheritance` | `widget` → `button` → `fancy-button`, virtueller Aufruf aus der Basis, `call-super` über zwei Ebenen, Feld-Mutation (K3 Stufe 2) |
| `p09_multimodule` | Module `util`, `geometry` und `app`; private Helfer; Struct per Wert über Modulgrenzen (Include) und per `box` (Vorwärtsdeklaration) (K2) |
| `p10_closures` | Lambdas fangen die Schleifenvariable per Wert (E3), Lambda mit mehreren Statements (E10), `funcall` |
| `p11_names` | Bezeichner `type`, `class`, `match`, `fn`, `self-ref`, `list`, `point-3d`; Rollen-Naming (E4) |
| `p12_arg_order` | Aufrufe mit Seiteneffekt-Argumenten (Zähler); deterministische Ausgabe (E8) |

- **Validierung:** V-INT für alle Programme und alle Targets.
- **Commits:** je `test(tests): add integration program pNN_<name>`.

#### Schritt 4.3 — Determinismus und Idempotenz

- **Ablauf:** Alle Programme zweimal generieren.
- **Erwartung:**
  - Die Dateien sind bytegleich (`sha256sum`-Vergleich).
  - Beim zweiten Lauf melden alle Dateien `:unchanged` und die mtimes
    sind unverändert.
- **Validierung:** neues Kommando `./run-integration.sh --determinism`
  ist grün.
- **Commit:** `test(tests): verify deterministic and idempotent generation`.

#### Schritt 4.4 — ECL-Portabilität

- **Umfang:** `./run-tests.sh --ecl` lädt das System unter ECL und führt
  die Unit-Tests aus.
- **Wenn das nicht vollständig geht** (z. B. weil eine Bibliothek unter
  ECL nicht lädt): Ursache dokumentieren, mindestens das Laden des Systems
  muss grün sein.
- **Validierung:** V-ECL.
- **Commit:** `test(tests): run unit tests under ecl`.

#### Schritt 4.5 — CLI und Beispiel

- **`polyglot-gen.sh <projekt.lisp> --targets … --out …`**
  - ruft `src/driver/83-cli.lisp` auf
  - Hilfe bei `--help`
  - Exit ≠ 0 bei `dsl-error`, Ausgabe der Quellform
- **`examples/01_shapes/`**
  - Shapes/Widgets-Demo mit Interfaces, Vererbung und zwei Modulen
  - `gen.lisp` mit der Repo-üblichen Bootstrap-Präambel (siehe
    `example/00_test/gen.lisp`)
  - erzeugt `source01/{cl,python,cpp,rust,go}/`; die Ausgabe wird
    **committet**, damit man sie im Repo lesen kann
- **Validierung:**
  - `sbcl --non-interactive --load examples/01_shapes/gen.lisp` erzeugt die
    Dateien
  - ein zweiter Lauf lässt `git status` unverändert
  - die Ausgabe kompiliert und läuft in allen Targets
- **Commit:** `feat(driver): add polyglot-gen cli and shapes example`.

### Phase 5 — Dokumentation und Abschluss

#### Schritt 5.1 — README

- **Inhalt** von `README.md` (Deutsch):
  - Zweck
  - Schnellstart (drei Befehle)
  - DSL-Kurzreferenz mit Verweis auf `SUPPORTED_FORMS.md`
  - Architekturbild (Mermaid)
  - Tests ausführen
  - bekannte Grenzen
- **Validierung:** Die Mermaid-Blöcke sind syntaktisch plausibel, alle
  Befehle aus dem Schnellstart laufen.
- **Commit:** `docs(docs): add readme for polyglot generator`.

#### Schritt 5.2 — `walkthrough.md` schreiben

- **Vorlage:** `plan/20260929_01_compare/walkthrough.md` (Grundgerüst
  liegt bereit) nach den dortigen Regeln ausfüllen.
- **Quellen:** `worklog.md`, Commit-Historie
  (`git -c safe.directory='*' log --oneline -- example/13_polyglot_generator`)
  und die Testergebnisse.
- **Commit:** `docs(plan): add walkthrough for polyglot generator`.

#### Schritt 5.3 — Abschluss-Gate

1. Frischer Lauf aller Gates: V-SYN `--indent` über alle `.lisp`, V-UNIT,
   V-DOC, V-ECL, `./run-tests.sh --paren`, V-INT (alle Programme und
   Targets), `--determinism`.
2. `git -c safe.directory='*' status` zeigt keine eigenen ungestagten oder
   uncommitteten Dateien. Fremde Änderungen, die schon vorher existierten,
   sind unverändert.
3. Keine `*.bak-*`-Dateien mehr vorhanden, `build/` ist ignoriert.
4. Ergebnis in `worklog.md` festhalten und in den Walkthrough übernehmen.
5. **Nicht pushen.** Dem User die Commit-Liste melden und auf die
   Push-Freigabe warten.
