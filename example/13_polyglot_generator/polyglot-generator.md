


Die drei komplexesten Algorithmen im `polyglot-generator` (`example/13_polyglot_generator/`) sind meiner Einschätzung nach: die **Pass-Pipeline mit der Inheritance→Composition-Umschreibung**, die **Präzedenz-Engine für minimale Klammerung** und die **Resolve-/Mutability-/Borrow-Analyse**. Zusammen machen sie aus dem Generator einen echten Transpiler, der aus einer IR fünf Sprachen mit idiomatischer Ausgabe bedient.

---

## 1. Inheritance→Composition + Vtable + Re-Passes (`src/passes/35-vtable.lisp`, `36-composition*.lisp`)

Das ist der komplexeste Pass-Cluster: C++, Python und CL kennen Implementierungsvererbung nativ, Rust und Go nicht. Der `vtable`-Pass verknüpft jede Methode mit ihrem Überschriebenen (`ir-super-target`), prüft `virtual`/`override`-Konsistenz und baut pro Typ eine Vtable-Allel `name → implementing method` [1](#0-0) . Für Rust/Go läuft danach `composition` (Order 60), das Vererbung in ein `base`-Feld plus freie Funktionen wie `button_width(this: &dyn ButtonDyn)` umschreibt, gefolgt von den Re-Passes `re-resolve`, `re-vtable`, `re-mutability` (61–63), weil die Umschreibung die Typ- und Mutabilitätsinformation invalidiert [2](#0-1) . Ein Trick dabei: Go-Struct-Embedding würde Dispatch brechen, deshalb nutzt Go dieselbe Kompositionsform wie Rust — `widgetWidth(this)` statt Method-Set-Vererbung [3](#0-2) .

Das macht die Software zu dem, was sie ist: eine DSL mit `defclass (base)`/`virtual`/`call-super` wird auf Sprachen abgebildet, die diese Konzepte gar nicht haben — ohne dass die Backends selbst Vererbungslogik kennen.

## 2. Präzedenz-Engine (`src/printer/51-precedence.lisp`, Backend-Op-Tabellen)

Jedes Backend liefert eine Operator-Tabelle mit `level`, `assoc` und einer `:clarity`-Liste für erzwungene Klammern (z. B. `&&` in `||` wegen `-Wparentheses` in g++) [4](#0-3) . Die Engine druckt in zwei Modi: `:minimal` für die Ausgabe und `:full` (alles geklammert) als Test-Oracle; `--paren` generiert 400 Zufallsausdrücke und prüft beide Modi gegen alle fünf Backends — ein echter Differenzialtest [5](#0-4) . Dieser Algorithmus entscheidet, ob die Ausgabe `return (a && b) || !c;` als Linter-sauber durchgeht [6](#0-5) .

## 3. Resolve + Mutability + Borrow/Lifetime-Inferenz (`32-resolve*`, `34-mutability`)

`resolve` baut Scopes, typisiert jeden `expr`-Knoten (`ty=:UNKNOWN` → `ty=:F64` …) und erkennt Methodenaufrufe (`call-expr` → `method-call-expr`) [7](#0-6) . `mutability` markiert, welche Locals `let mut`/nicht-`const` sein müssen, leitet `iter-mode` (`:ref`/`:move`/`:mut`) für `for-each` ab und markiert `:inout`-Argumente [8](#0-7) . Oben drauf sitzt die Parameter-Modi-Logik (`:in`/`:inout`/`:sink` → `&T`/`&mut T`/`T`, `const T&`, `*T`) und die Lifetime-Erzeugung aus `borrows-from`-Regionen — bewusst **kein** eigener Borrow-Checker; rustc validiert das Ergebnis [9](#0-8) .

## Warum genau diese drei?

Die Pipeline-Architektur (`signatures → desugar → resolve → check → mutability → vtable → composition? → rename → lower? → order-args? → capability`) ist so gebaut, dass jeder Pass IR→IR nur eine Aufgabe hat und über **Capabilities** pro Backend ein-/ausgeschaltet wird [10](#0-9) . Die drei genannten sind die, die semantische Arbeit leisten: sie verleihen der IR Typen und Dispatch-Information (3), zerlegen Konzepte für Sprachen ohne sie (1) und sorgen dafür, dass das Drucken überhaupt korrekt und linter-sauber ist (2).

## Notes

- Ehrenwerte Erwähnungen: `order-args` (Order 85, nur für C++'s unspezifizierte Argumentauswertung — unreine Argumente werden in Temporaries gezogen) [11](#0-10) ; `desugar` mit Tail-Return-Einfügung [12](#0-11) ; die C++-Include-Analyse (Wert vs. Zeiger → `#include` vs. Forward-Deklaration) [13](#0-12) .
- Ich habe die Pass-Dateien selbst nur teilweise eingesehen; die Detaillogik von `36-composition-rewrite.lisp` und `51-precedence.lisp` liegt über die im Kontext gezeigten Snippets hinaus.
