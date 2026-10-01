## Kurzantwort

Die drei komplexesten und wichtigsten Algorithmen in SBCL sind:

1. **Der generelle Garbage Collector (GENCGC)** – Generationen-basierte Speicherbereinigung mit Card-Marking, Pinning und Scavenging in `src/runtime/gencgc.c`.
2. **Die Compiler-Pipeline (IR1→IR2→Maschinencode)** – mehrstufige Zwischenrepräsentation mit Typableitung und Constraint-Propagation, beginnend in `src/compiler/ir1tran.lisp`.
3. **Das CTYPE-Typsystem** – Typableitung, `subtypep`-Berechnung und Typschnittmengen, die sowohl Optimierung als auch Laufzeit-Typprüfung ermöglichen.

Hinzu kommen als erwähnenswerte Teilalgorithmen der Cheney-Copying-GC (`cheneygc.c`) und das Robinhood-Hashset (`hashset.lisp`).

---

## 1. Genereller Garbage Collector (`gencgc.c`)

GENCGC ist der Standard-GC für dynamischen Speicher und das Herzstück der Runtime. Kernalgorithmen:

- **Card-Marking / Write-Barrier**: Statt ganzer Seiten werden "Cards" (kleine Seitenabschnitte) als dirty markiert; beim GC werden nur markierte Cards älterer Generationen nach alt→jung-Zeigern durchsucht. Das macht partielle GCs billig. [1](#0-0) 
- **Scavenging**: `scavenge_root_gens` iteriert regionsweise über ältere Generationen und scannt nur markierte Bereiche; Code-Seiten werden danach wieder schreibgeschützt. [2](#0-1) 
- **Conservative Root Pinning**: `preserve_pointer` entscheidet für jedes Register/Stack-Wort, ob es ein möglicher Zeiger ist (`conservative_root_p`), pinnt exakte Objekte via `pin_object`, und verwaltet ambige Zeiger über eine Hopscotch-Hashtabelle (`pinned_objects`) mit 8-Subseiten-Granularität. [3](#0-2) 
- **Pinned-Object-Nachbearbeitung**: `scavenge_pinned_ranges` durchsucht gepinnte Objekte nach weiteren Zeigern — ein heikler Teil, da Seiten mit angepinnten Objekten nicht kompakt freigegeben werden können. [4](#0-3) 

**Beitrag zum Ziel:** Ermöglicht Lisp-typische hohe Allokationsraten mit kurzen GC-Pausen — junge Objekte werden fast umsonst eingesammelt, während konservative Wurzeln C-kompatible Aufrufe erlauben. Die Architektur-Übersicht ordnet GENCGC als Kern des dynamischen Speichers ein. [5](#0-4) 

## 2. Compiler-Pipeline (IR1 → IR2 → Codegen)

Der Python-Compiler von SBCL übersetzt über mehrere Zwischenrepräsentationen:

- **IR1-Translation** (`ir1tran.lisp`): Quellformen werden in einen Flow-Graph aus `node`/`combination`/`ref`-Objekten und `clambda`s konvertiert; `ir1-toplevel` erzeugt eine Toplevel-Lambda und bindet den gesamten Compiler-Zustand reentrant. [6](#0-5) 
- **Namensraum- & Inline-Auflösung**: `find-free-fun` / `fun-name-inline-expansion` lösen globale Funktionen auf, holen Inline-Expansionen und Funktionstypen — Grundlage für Inlining und Typspezialisierung. [7](#0-6) 
- Danach folgen IR1-Optimierung (Inlining, Konstantenfaltung, Typableitung), Constraint-Propagation, IR2-Translation und Register-Allokation/Codegen pro Zielarchitektur — laut Wiki-Diagramm `IR1 Translation → IR1 Optimization → Constraints → Type Analysis → IR2 → Code Generation`.

**Beitrag zum Ziel:** SBCLs Ruf als nativ kompilierende, schnelle CL-Implementierung beruht genau auf dieser Pipeline — sie erzeugt Maschinencode mit Lisp-spezifischen Optimierungen (Typinferenz ohne Deklarationen, automatisches Unboxing).

## 3. CTYPE-Typsystem

Das Typsystem (in `src/code/type*.lisp` und `src/compiler/ctype.lisp`, laut Wiki) modelliert CL-Typen als `ctype`-Hierarchie mit `type-class`-Methoden für `subtypep`, Negation und Schnittmengen. Der Compiler verwendet `derived-type` an jedem IR1-Knoten; `subtypep`/Intersect-Algorithmen treiben Typableitung und ermöglichen es, Typtests, Boxen und Checks zu eliminieren.

**Beitrag zum Ziel:** CL hat ein reichhaltiges, nicht entscheidbares Typsystem (Unions, Member-Typen, Arrays) — die `type-class`-Methodentabelle macht `typep`/`subtypep` erweiterbar und versorgt den Optimierer mit den Informationen, die zur Codequalität nötig sind.

## Weitere nennenswerte Algorithmen

- **Cheney-GC** (`src/runtime/cheneygc.c`): klassischer stop-and-copy Collector für nicht-generationale Builds. [8](#0-7) 
- **Robinhood-Hashset** (`src/code/hashset.lisp`): schwaches Hashset mit PSL-Vektor (probe sequence length) nach der Waterloo-Arbeit, mit atomar austauschbarem Storage für nebenläufige Leser. [9](#0-8) [10](#0-9) 
- **Pinning der Aufrufkette** (`src/runtime/pmrgc.c`): `pin_call_chain_and_boxed_registers` pinnt Code-Objekte entlang der Frame-Kette — eine exakte Alternative zum Scannen aller Stack-Wörter. [11](#0-10) 

## Notes

- Die Wiki-Seite (System Architecture Overview) bestätigt diese Gewichtung: Compiler-Pipeline, GENCGC und CTYPE sind die drei Hauptsubsysteme.
- `arm-assem.S` und `arm64-linux-os.c` sind plattformspezifischer Glue-Code (`call_into_lisp`, Thread-Init), keine eigenständigen Algorithmen. [12](#0-11) 
- Der ausführliche Kommentar in `gencgc.c:1676-1714` dokumentiert bewusst ein ungelöstes Problem bei `visit_freed_objects` — er ist Dokumentation, kein aktiver Code.

