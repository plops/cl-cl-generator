# Implementation Plan: Soft-Constraints & General Constraints im High-Level HPIPM Interface

Wir erweitern das Lisp-mäßige High-Level-Interface in [hpipm-high.lisp](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/hpipm-high.lisp) um die Unterstützung für fortgeschrittene HPIPM-Features und erstellen eine physikerfreundliche Dokumentation.

## Proposed Changes

### Generator-Skript
#### [MODIFY] [gen02.lisp](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/gen02.lisp)
- Erweiterung des Templates für `hpipm-high.lisp` (Struktur `mpc-solver` um Soft-Constraints-Verarbeitung erweitern, Implementierung der neuen Batch-Setter und Anpassung von `solve-mpc`).
- Erstellung eines neuen Demos `mpc-soft-demo.lisp`, welches die Funktionsweise von Soft-Constraints demonstriert.
- ASDF-System-Datei `hpipm.asd` aktualisieren, um `mpc-soft-demo` aufzunehmen.
- Export-Liste in `package.lisp` um die neuen Setter erweitern.

### Dokumentation
#### [NEW] [solver_guide_physics.md](file:///workspace/src/cl-cl-generator/example/06_hpipm_cffi/solver_guide_physics.md)
Eine ausführliche Dokumentation des Interfaces, geschrieben für Physiker. Sie verzichtet auf Control-Theory-Jargon und numerische Mathematik (wie ADMM/IPM, tridiagonale Sparsität, Workspace-Allokationen) und erklärt den Solver stattdessen aus der Sicht von physikalischer Zustandsmodellierung, Differentialgleichungen, Energiefunktionen (Kosten) und elastischen Grenzen (Soft-Constraints).

---

## Technical Design

### 1. Soft-Constraints Deklaration (in `make-mpc-solver`)
Der Benutzer kann beim Erstellen des Solvers Soft-Constraints übergeben:
```lisp
(make-mpc-solver
  :horizon N
  :nx nx
  :nu nu
  :soft-constraints '((:stage :all :type :state :index 2 :Z 1e4 :z 0.0)
                      (:stage :terminal :type :state :index 0 :Z 1e5 :z 0.0)))
```

#### Verarbeitung im Konstruktor:
1. **Shorthand-Expansion**: Symbolic Stages (`:all`, `:terminal`, `:path`) werden in konkrete Stufenindizes $k \in \{0 \dots N\}$ aufgelöst.
2. **Slack-Dimensionen (`ns`)**: Für jede Stufe $k$ entspricht `ns[k]` der Anzahl der dieser Stufe zugeordneten Soft-Constraints. Wir setzen diese Dimension in `dim-ptr` über `d-ocp-qp-dim-set-ns`.
3. **Problem-Daten (`qp`)**:
   - Für jede Stufe $k$ mit `ns[k] > 0`:
     - Wir erstellen das Index-Array `idxs`. Ein Constraint-Index wird wie folgt berechnet:
       - Für `:type :input`: `index`
       - Für `:type :state`: `nbu[k] + index`
       - Für `:type :general`: `nbu[k] + nbx[k] + index`
     - Wir erstellen die Strafterm-Vektoren `Zl`, `Zu` (quadratisch) und `zl`, `zu` (linear) der Länge `ns[k]`.
     - Wir allokieren `lls` und `lus` und setzen sie auf $0.0$, um die Nichtnegativität der Slacks zu garantieren.
     - Wir rufen die Setter `d-ocp-qp-set-idxs`, `d-ocp-qp-set-Zl`, `d-ocp-qp-set-Zu`, `d-ocp-qp-set-zl`, `d-ocp-qp-set-zu`, `d-ocp-qp-set-lls`, `d-ocp-qp-set-lus` auf.

### 2. General Constraints Setter
Wir stellen folgende High-Level-Funktionen bereit, um $lg \le C_k x_k + D_k u_k \le ug$ zu definieren:
- `(set-general-constraints solver stage C D lg ug)`
- `(set-solver-general-constraints solver C D lg ug)` (uniform über alle Stufen)

Falls `C` oder `D` `nil` sind, erzeugen wir automatisch eine Nullmatrix der passenden Größe ($n_g \times n_x$ bzw. $n_g \times n_u$).

### 3. Solver-Aufruf und Slack-Rückgabe (in `solve-mpc`)
`solve-mpc` gibt nun 6 Werte zurück:
```lisp
(values u-trajectory x-trajectory status iterations sl-trajectory su-trajectory)
```
- `sl-trajectory`: Vektor von double-Vektoren der Länge `ns[k]` für die optimalen unteren Slacks $s_l^*$ an jeder Stufe.
- `su-trajectory`: Vektor von double-Vektoren der Länge `ns[k]` für die optimalen oberen Slacks $s_u^*$ an jeder Stufe.

---

## Verification Plan

1. **Codegenerierung anstoßen**:
   ```bash
   sbcl --load gen02.lisp --eval '(quit)'
   ```
2. **Kompilierung & Laden im FFI-Mock-Modus verifizieren**:
   ```bash
   sbcl --eval '(ql:quickload :cffi)' \
        --eval '(setf (fdefinition (quote cffi:load-foreign-library)) (lambda (name &key &allow-other-keys) (declare (ignore name)) t))' \
        --eval '(push "/workspace/src/cl-cl-generator/example/06_hpipm_cffi/source01/" asdf:*central-registry*)' \
        --eval '(ql:quickload :hpipm)' \
        --eval '(quit)'
   ```
3. **Dokumentation prüfen**:
   Manuelle Sichtung von `solver_guide_physics.md` zur Sicherstellung der Verständlichkeit für Nicht-Experten.
