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


## Arbeitsweise (gilt ab Schritt 1.1)

- Neue Dateien werden als Ganzes geschrieben und **sofort** mit
  `tools/lisp-check.sh --tests --fix-indent <dateien>` geprüft (SBCL liest
  formweise und lädt das System mit `:force t`) und danach mit
  `./run-tests.sh`. Die Emacs-Einrückung wird per `--fix-indent`
  übernommen; die Unterschiede zu meiner Einrückung waren durchweg
  kosmetisch (Keyword-Argumente, `let`-Bindungen, `if`-Zweige).
- Gefundene Fehler durch das Gate bisher: ein nicht quotierter Plist-Wert
  im Makro `define-intrinsic` (Compile-Error „illegal function call“), eine
  Paketsperre (`find-method` ist ein CL-Symbol → `lookup-method`). Kein
  einziger Klammerfehler bisher.
- Werkzeugfehler: `--fix-indent` mit einem nicht expandierten Glob legte über
  Emacs eine Datei `32-*.lisp` an. Behoben: `lisp-check.sh` lehnt fehlende
  Dateien ab, `reindent.el` legt keine `~`-Backups mehr an.

## Schritte 1.1–1.11 (2026-09-29)

| Schritt | Commit | Checks |
|---|---|---|
| 1.1 Namen | 8adcbdb | 41 |
| 1.2 Knoten | 83ab920 | 41 |
| 1.3 Typen | 9696a1b | 74 |
| 1.4–1.6 Parser (ein Commit, Parser gegenseitig rekursiv) | c6a947a | 194 |
| 1.7 Items/Module (inkl. Tests zu 1.8) | a9be59e | 243 |
| 1.9 Intrinsics | 0d93610 | 274 |
| 1.10 Pipeline/desugar | c966152 | 294 |
| 1.11 resolve | a4ad62c | 310 |

Abweichungen/Entscheidungen:
- `let` wird als `block-stmt` mit `decl-stmt`s modelliert (einheitlich für
  Statement- und Wert-Position). Parallel-Let: nur Bezüge auf *frühere*
  Bindungen desselben `let` sind ein Fehler (Selbstbezug `(let ((x (+ x 1))))`
  ist erlaubt).
- Zusätzlicher Pass `:signatures` (Order 5): Methoden ohne `(values T)`
  erben den Ergebnistyp der Interface-/Basismethode. Nötig, weil das
  Beispiel in plan.md K3 `(defmethod area ((c circle :in)) …)` ohne
  `values` schreibt und desugar die Tail-Returns vor resolve einsetzt.
- Zusätzliche Intrinsics `to-float` und `int-to-string`, zusätzliche
  Surface-Form `(some x)` für `optional`-Werte (plan.md nennt nur `nil`).
- Namen: Nach dem Parsen tragen Typen die Form `(:named "name" item)`.


## Schritte 1.12–2.2 (2026-09-29)

| Schritt | Commit | Checks / Integration |
|---|---|---|
| 1.12 check | 785f77c | 341 |
| 1.13 mutability | 393370e | 355 |
| 1.14 vtable | 09d2674 | 369 |
| 1.15 rename | d6ba114 | 379 |
| 1.16 lower/order-args/capability | d1f82e0 | 400 |
| 1.17 printer | 0b953c1 | 439 |
| 1.18 driver (+ Backend-Protokoll vorgezogen), Phase-1-Gate inkl. ECL | c476a14 | 450 (SBCL und ECL) |
| 2.1 CL-Backend | 6d4dd7f | 463; p01/p02 cl PASS |
| 2.1 Runner + p01/p02 | 16e83bd | |
| 2.2 Python | cc7f9a9 | 476; p01/p02 cl+python PASS |

Abweichungen/Entscheidungen:
- E11 im Parser statt im lower-Pass (resolve prüft Aritäten vorher).
- Driver-Header: git-Blob-Hash der Quelldatei statt `rev-parse HEAD`
  (sonst wäre die committete Beispielausgabe nach jedem Commit veraltet).
- Formatter über stdin/stdout statt temporärer Datei.
- Zyklische Modulimporte sind ein dsl-error (Go verbietet sie; „gegenseitige
  Imports“ in R12 wird als „Importe zwischen Modulen“ gelesen).
- ruff 0.16.9 hat einen stark erweiterten Standardregelsatz (I001, SIM102,
  SIM201, B023, E731, …). Konsequenzen: isort-Sektionen, `def` statt
  Lambda-Zuweisung, desugar vereinfacht `(not (= a b))` und verschachtelte
  `if` ohne `else` für alle Backends.
- Gate-Fund: ein echter Klammerfehler (eine `)` zu viel, zweimal) in
  `src/backend/cl/items.lisp`; SBCL meldete „unmatched close parenthesis“
  mit Formnummer, Emacs-Reindent zeigte die Stelle.
- LOOP-Schlüsselwörter (`for`, `from`, `below`, `across`, `while`) müssen im
  Scratch-Paket interniert werden, sonst druckt emit-cl `polyglot::for`
  (vom Spec-Test gefunden).


## Schritte 2.3–2.8 (2026-09-29)

| Schritt | Commit | Ergebnis |
|---|---|---|
| 2.3 C++ Kern + Split | d311121 | 489 checks; p01/p02 cl,python,cpp PASS; cmake -G Ninja einmalig OK |
| 2.4 C++ Mehrmodul | e0c9756 | 504 checks; p09 PASS (Include vs. Vorwärtsdeklaration) |
| 2.5 C++ Structs/Interfaces/Vererbung/Views | cc65c8e | 519 checks; 21/21 PASS (7 Programme × 3) |
| 2.6 Rust Kern | 7a4cdfa | 537 checks; 24/24 PASS |
| 2.7 Rust Traits/Lifetimes | 1ea3519 | (derselbe Lauf) |
| 2.8 Composition | 35c5f28 | 551 checks; 28/28 PASS (7 × cl,python,cpp,rust) |

Abweichungen/Entscheidungen:
- Das Entry-Modul hat in C++ keinen Namespace (`main` muss global sein)
  und nur dann einen Header, wenn es öffentliche Items hat.
- p09 hat vier Module (util, geometry, report, app), damit Include und
  Vorwärtsdeklaration getrennt sichtbar sind.
- Neu im Kern: `(box T)` darf an `:in`-Parameter vom Typ T übergeben werden;
  Intrinsics `string-find`/`string-slice` (ASCII-Byte-Offsets) für p06;
  E5 erlaubt das Ablegen einer Stelle in einen geliehenen Typ.
- p07 nutzt 3 statt 3.14159: `clippy::approx_constant` ist deny-by-default.
- Rust: 2.6 und 2.7 entstanden zusammen; Commit 7a4cdfa referenziert in der
  .asd bereits `rust/items`/`lifetimes`, die erst in 1ea3519 folgen (ein
  Zwischenstand, der nicht lädt).
- Composition: freie Funktionen nehmen `&dyn CDyn` statt eines generischen
  `T: CDyn + ?Sized` (Trait-Upcasting ist stabil). `&mut Box<dyn T>` wird
  nicht automatisch zu `&mut dyn T` (Unsizing hat Vorrang) → `.as_mut()`.
  Accessoren werden nur erzeugt, wenn sie gebraucht werden (sonst
  dead_code-Warnungen).
- ASDF meldet Style-Warnings als `WARNING` („Lisp compilation had
  style-warnings“); das Gate wertet das als Fehler (gut: hält den Code
  warnungsfrei). Die `artifact`-Struktur muss vor den Backends geladen
  werden (sonst Style-Warning zu nicht inlinebaren Accessoren).


## Schritte 2.9–3.3 (2026-09-29)

| Schritt | Commit | Ergebnis |
|---|---|---|
| 2.9 Go | b52b216 | 569 checks; 35/35 PASS; **keine Kernänderung** (nur neue Dateien in `src/backend/go/` plus `.asd`) |
| 2.10 Intrinsics/Prelude, p04, Phase-2-Gate | 0843ad2 | 696 checks (SBCL und ECL); 40/40 PASS |
| 3.1 Spec-Tabelle + SUPPORTED_FORMS.md | b56825d | 815 checks; 43 Spec-Einträge in 13 Tags (der Commit-Body nennt fälschlich 51, das war die Zahl der Tabellenzeilen) |
| 3.2 Zufalls-Präzedenztests | cb3deb8 | 5 Backends × 2 Modi × 401 Werte PASS |
| 3.3 Abdeckungs-Audit | (dieser Schritt) | 821 checks |

Gate-Funde in dieser Phase: ein zweiter echter Klammerfehler (`go/config.lisp`,
eine `)` zu viel beim Schließen der Operator-Liste), vom Reader gemeldet
(„unmatched close parenthesis“, Form #9). Der Spec-Ausbau fand fünf Fehler
(extern im rename-Pass, CL-Extern-Paket, Rust-Methodenname, `**x`,
K1b-Check bei benannten Regionen), die Zufallstests einen (Rust E0689 bei
Receivern nur aus Literalen).

Go-spezifische Entscheidungen: Shadowing `:rename` statt `:block` (ein
gespliceter letzter Block könnte sonst dieselbe Variable im selben Scope
neu deklarieren); `go 1.23` statt 1.22 (slices.Sorted/maps.Keys); Pointer-
Receiver für alle Methoden, sobald eine mutiert oder der Typ ein Interface
implementiert; Interface-Default-Methoden als freie Funktionen plus
Delegation.

### Abdeckungs-Audit (Schritt 3.3)

Conditions:
- `dsl-error`: praktisch jede Testdatei (z. B. test-check, test-resolve).
- `unsupported-construct`: test-declare (&optional), test-items (Mehrfach-
  vererbung), test-desugar (target-case ohne Zweig), test-lower
  (capability), test-signatures (:sink in Komposition), Spec (Python/CL
  :inout-Skalare, fremde Erweiterungsformen).
- `dsl-warning`: test-lower (E11), test-driver (fehlender Formatter).

Check-Regeln (je positiv und negativ in test-check): E5, E5 für :sink,
E7, E14 und format-string, E1, fehlende Returns, :in-Parameter nur lesbar,
K1b (mehrdeutig, unbekannter Parameter), zusätzlich Parallel-Let
(test-stmt).

Passes mit Negativtest: signatures (Zyklus), desugar (target-case), resolve
(unbekannte Namen, Typfehler, Importe), check (s. o.), mutability
(Zuweisung an Schleifenvariable), vtable (override-Fehler, fehlende
Implementierung, abstrakte Klasse), composition (:sink), rename
(Kollisionen), lower (and/or, while-Test), order-args (kein Fehlerfall;
positiv/negativ als „hebt nur bei >1 unreinem Argument“), capability (vier
Fälle).

Quelldatei -> Testdatei:

| src | Tests |
|---|---|
| 00-package, 01-syntax, 02-conditions | test-syntax |
| 03-names | test-names |
| ir/10-node, 11-types | test-node, test-types |
| ir/12-expr, 13-stmt, 14-items | test-expr, test-stmt, test-items |
| frontend/20-registry | test-macros |
| frontend/21-expr*, 22-stmt*, 23-declare, 24-*, 25-intrinsics | test-expr, test-stmt, test-declare, test-items, test-intrinsics |
| passes/30-pipeline, 31-desugar, 31-signatures | test-desugar, test-signatures |
| passes/32-resolve* | test-resolve |
| passes/33-check* | test-check |
| passes/34-mutability, 35-vtable, 36-composition* | test-mutability, test-vtable, test-composition |
| passes/37-rename*, 38-lower*, 39-order-args, 40-capability | test-rename, test-lower |
| printer/50–52 | test-printer |
| driver/80–82, backend/60-protocol | test-driver |
| backend/61-text, cl/*, python/*, cpp/*, rust/*, go/* | tests/spec (43 Einträge × 5), test-backends, test-cpp-split, tests/paren, Integration |

Abweichung: Die Backend-Dateien haben keine eigene Testdatei pro Datei;
sie werden über die Spec-Tabelle (ein Eintrag prüft jeweils alle Backends),
test-backends, test-cpp-split, die Zufallstests und die Integrations-
programme abgedeckt. Eine Datei pro Backend-Datei hätte dieselben Fälle nur
dupliziert.


Korrektur zu Schritt 3.1: Der Commit-Body von b56825d nennt 51 Spec-
Einträge; tatsächlich sind es 43 Einträge in 13 Tags.

## Phase 4

### Schritt 4.1 – Integrationsprogramme und Runner (accd805, 7adf6bb, 60e5688, c927af0, 2044e97, 393d343)

Runner mit `--help` und Fehlermeldung bei unbekanntem Programm (accd805).
7adf6bb behebt beim Ausbau gefundene Fehler; danach kamen p03, p10, p11 und
p12 hinzu. Die neuen Programme deckten auf:
- CL: Schleifenvariablen, die von Closures eingefangen werden, brauchen eine
  Neubindung pro Iteration.
- CL: Ein leerer LOOP-Rumpf braucht `(values)`.
- C++: Das Include `<vector>` fehlte.
- Rust: `clippy::useless_vec`.
- Go: Lokale Variablen überschatten unter `:rename` Modul-Items.
Ergebnis: 12 Programme × 5 Ziele = 60 PASS.

### Schritt 4.3 – Determinismus (8f09767)

`./run-integration.sh --determinism` erzeugt zweimal und vergleicht
byteweise: 152 Dateien, 0 Abweichungen.

### Schritt 4.4 – ECL und `--all` (d12fc48, 7b96062)

821 Checks laufen unter ECL 24.5.10 in 28,7 s. 7b96062 macht
SUPPORTED_FORMS.md unabhängig von der Ladehistorie; Ursache war eine
nichtdeterministische Reihenfolge in `dsl-string`.

### Schritt 4.5 – CLI und Beispiel (f6f266a, fb2e0b9)

`polyglot-gen.sh` plus `examples/01_shapes`. Ein zweiter Lauf schreibt 0
Dateien und `git status` bleibt sauber. fb2e0b9 ergänzt die Liste reservierter
Python-Namen um häufige Builtins (`sum` → `sum_`) und nimmt eine versehentlich
eingecheckte `.pyc`-Datei aus dem Index.

## Phase 5

### Schritt 5.1 – README (dcf2420)

Die Mermaid-Diagramme wurden mit mermaid-cli gerendert. Chromium brauchte dafür
zusätzliche apt-Pakete (libnss3 u. a.).

## Aufwand

Der Hauptteil der Umsetzung (Phasen 0–4 und Schritt 5.1) kostete laut Kiro-CLI
ca. 640 Credits: `Credits: 640.55 • Time: 125m 21s`. Zum selben Zeitpunkt zeigte
`/usage` für den Plan KIRO PRO+ 1601,23 von 2000 Credits verbraucht (80,1 %,
Reset am 2026-10-01).


## Nachtrag — cl-change-case (36442ac)

Hinweis des Nutzers: `src/03-names.lisp` implementierte die Bibliothek
`rudolfochrist/cl-change-case` (Quicklisp, `cl-change-case-20250622-git`) nach.
Die Umwandlungen delegieren jetzt an `snake-case`, `constant-case` und
`camel-case :merge-numbers t` (Pascal: `upper-case-first` davon). Eigener Code
bleibt nur für zwei Dinge:
- Validierung: Die Bibliothek entfernt ungültige Zeichen stillschweigend.
- Namen mit gemischter Schreibweise (`Point`, `HTTPServer`) bleiben unverändert.

Wichtig ist `:merge-numbers`. Ohne die Option wird `point-3d` zu `point_3d` bzw.
`Point_3d`.

Beleg: Alle 152 erzeugten Quelldateien der Integrationsprogramme sind vor und
nach der Änderung byteweise gleich. `tools/lisp-check.sh` lädt die
Abhängigkeiten jetzt aus der `.asd`. Die fest codierte Liste hätte die neue
Abhängigkeit nicht gekannt: READ ERROR „Package CL-CHANGE-CASE does not exist“.

Umgebung: Zwischendurch wurde der Container zurückgesetzt. `/tmp` war leer, und
ecl, clang-format, golang-go und emacs-nox fehlten wieder. Eine Neuinstallation
per apt stellte dieselben Versionen her. Das stützt den Dockerfile-Vorschlag im
Walkthrough.
