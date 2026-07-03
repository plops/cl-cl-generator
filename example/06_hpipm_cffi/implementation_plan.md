# Implementation Plan: Lisp-mäßiges Interface für HPIPM CFFI (Unified in source01/)

Wir implementieren das Lisp-freundliche High-Level-Interface direkt integriert im Ordner `source01/`. Dabei teilen wir die Arbeit wie folgt auf:
1. **`gen01.lisp` erweitern**: Wir fügen die CFFI-Bindings für `get_status` und `get_iter` (ermittelt und verifiziert via DeepWiki für `giaf/hpipm`) hinzu und regenerieren `source01/`.
2. **`gen02.lisp` erstellen**: Dieser Generator erzeugt ausschließlich das High-Level-Interface und die neuen Demos und schreibt diese ebenfalls nach `source01/`. Gleichzeitig überschreibt `gen02.lisp` die Dateien `package.lisp` und `hpipm.asd` in `source01/`, um beide Welten (Low- und High-Level) nahtlos in einem System zu vereinen.

---

## Proposed Changes

### 1. Modifikationen an gen01 und Low-Level Regeneration
#### [MODIFY] gen01.lisp
- Hinzufügen von `get_status` CFFI-Bindings (`d_ocp_qp_ipm_get_status` / `s_ocp_qp_ipm_get_status`).
- Hinzufügen von `get_iter` CFFI-Bindings (`d_ocp_qp_ipm_get_iter` / `s_ocp_qp_ipm_get_iter`).
- Hinzufügen der Wrapper-Funktionen `get-status-val` und `get-iter-val`.
- Exportieren dieser Symbole in `package.lisp`.

### 2. High-Level Generator und neue Dateien
#### [NEW] gen02.lisp
Der Generator für die High-Level-Komponenten. Er generiert folgende Dateien in source01/:
- **`hpipm-high.lisp`**: Das Lisp-mäßige Interface (Struktur `mpc-solver`, Konstruktor/Destruktor, `with-mpc-solver`-Makro, Setter/Getter, `solve-mpc`).
- **`mpc-demo-high.lisp`**: Das MSD-Demo, umgeschrieben auf das High-Level-Interface.
- **`pendulum-demo-high.lisp`**: Das Pendel-Demo, umgeschrieben auf das High-Level-Interface.
- **`package.lisp` [Overwrite]**: Aktualisierte Exportliste, die alle Low-Level-Symbole sowie alle neuen High-Level-Symbole exportiert.
- **`hpipm.asd` [Overwrite]**: Aktualisiertes ASDF-System, das alle 8 Lisp-Dateien in der richtigen Abhängigkeitsreihenfolge lädt.

---

## Technical Design of the High-Level API (in `hpipm-high.lisp`)

### 1. Solver-Datenstruktur (`mpc-solver`)
Wir definieren eine Lisp-Struktur, die alle 5 HPIPM-Datenstrukturen und ihre Speicherallokationen kapselt:
```lisp
(defstruct mpc-solver
  precision    ; :double oder :single
  horizon      ; N
  nx           ; Liste der nx-Werte pro Stufe
  nu           ; Liste der nu-Werte pro Stufe
  dim-ptr      ; Foreign Pointer auf dim
  qp-ptr       ; Foreign Pointer auf qp
  sol-ptr      ; Foreign Pointer auf sol
  arg-ptr      ; Foreign Pointer auf arg
  ws-ptr       ; Foreign Pointer auf ws
  allocations) ; Liste aller allokierten backing-Pointern zur späteren Freigabe
```

### 2. Hilfsfunktion zur Allokierung aligned Structures
```lisp
(defun allocate-hpipm-struct (memsize-fn create-fn create-args)
  (let* ((mem-size (apply memsize-fn create-args))
         (backing (cffi:foreign-alloc :char :count (+ mem-size 64)))
         (aligned-backing (align-pointer backing 64))
         (ptr (cffi:foreign-alloc :char :count (+ +hpipm-struct-size+ 64)))
         (aligned-ptr (align-pointer ptr 64)))
    (apply create-fn (append create-args (list aligned-ptr aligned-backing)))
    (values aligned-ptr ptr backing)))
```

### 3. Konstruktor und Destruktor
- `(make-mpc-solver &key horizon nx nu nbu nbx ng (precision :double) (mode :balance))`
  - Automatische Expansion von Skalaren zu stufenweisen Listen.
  - Allokiert und und initialisiert nacheinander `dim`, `qp`, `sol`, `arg` und `ws`.
- `(free-mpc-solver solver)`
  - Gibt alle allokierten Zeiger in `allocations` via `cffi:foreign-free` frei.
- `(with-mpc-solver (solver-var &rest args) &body body)`
  - Makro zur automatischen Speicherbereinigung (`unwind-protect`).

### 4. Setter/Getter und Solver-Aufruf
- `(set-solver-stage-dynamics solver stage A B)` / `(set-solver-dynamics solver A B)`
- `(set-solver-stage-cost solver stage Q R &key S)` / `(set-solver-cost solver Q R &key terminal-q)`
- `(set-control-bounds solver index min max)`
- `(set-state-bounds solver stage indices min-values max-values)`
- `(solve-mpc solver x0)`
  - Setzt Startbedingung $x(0) = x_0$.
  - Löst das QP und fragt den Status (`get-status-val`) und die Iterationen (`get-iter-val`) ab.
  - Extrahiert und gibt Trajektorien zurück: `(values u-trajectory x-trajectory status iterations)`.

---

## Verification Plan

1. **`gen01.lisp` anpassen und ausführen**:
   ```bash
   sbcl --load gen01.lisp --eval '(quit)'
   ```
2. **`gen02.lisp` erstellen und ausführen**:
   ```bash
   sbcl --load gen02.lisp --eval '(quit)'
   ```
3. **Kompilierbarkeit des Gesamtsystems testen**:
   ```bash
   sbcl --eval '(push "/workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/" asdf:*central-registry*)' \
        --eval '(ql:quickload :hpipm)' \
        --eval '(quit)'
   ```
   Dies stellt sicher, dass alle 8 Dateien fehlerfrei geladen und kompiliert werden können.
