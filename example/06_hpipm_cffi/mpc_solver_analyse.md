# Sparse Solver-Bibliotheken für MPC-Controller

## Was MPC wirklich löst

Ein linearer MPC-Controller löst bei jedem Zeitschritt ein **Quadratisches Programm (QP)**:

```
minimize   ½ xᵀ P x + qᵀ x
subject to  l ≤ A x ≤ u
```

Die Besonderheit: Durch Ausrollen des Horizonts (N Schritte × nx Zustände × nu Eingaben)
entsteht **Block-Tridiagonalstruktur** – der Kern der Sparsität.

---

## Bibliotheks-Übersicht

### Tier 1 – Für MPC-QPs optimiert

| Bibliothek | Algorithmus | Stärke bei MPC | Lizenz | C-API |
|---|---|---|---|---|
| **OSQP** | ADMM (first-order) | Allgemein sparse, warm-starting | Apache 2.0 | ✅ sauber |
| **HPIPM** | IPM + Riccati-Rekursion | Explizit für OCP-Struktur | BSD 2 | ✅ regulär |
| **qpOASES** | Active Set | Warm-start, harte Echtzeit-Garantien | LGPL | ✅ C++ mit C-Wrapper |
| **ProxQP** | Proximal ALM | Neuester Stand, oft schnellster bei mittelgroßen MPC | BSD 2 | ✅ C++ mit C-API |

### Tier 2 – Sparse lineare Gleichungslöser (Unter-Schicht)

| Bibliothek | Was es löst | Typischer Einsatz | cl-cl-generator Eignung |
|---|---|---|---|
| **UMFPACK** (SuiteSparse) | Allg. sparse LU | Direkt-Löser, innen in OSQP | API sehr groß, regulär |
| **CHOLMOD** (SuiteSparse) | Sparse Cholesky (spd) | Direkt für pos.-def. QPs | API sehr groß, regulär |
| **PARDISO** (Intel oneMKL) | Sparse direkt, parallel | Große Systeme | Proprietär, reguläre API |
| **SuperLU** | Sparse LU | Allgemein | BSD, reguläre API |
| **MUMPS** | Sparse direkt, verteilt | Sehr große Systeme | LGPL |
| **MA57/MA27** (HSL) | Sparse sym. Systeme | In IPOPT verwendet | Akademische Lizenz |

### Tier 3 – Frameworks / Höhere Ebene

| Framework | Was es tut | Bemerkung |
|---|---|---|
| **acados** | Hochleistungs-NLP/MPC-Rahmen (nutzt HPIPM) | Zu groß/komplex für direkte Anbindung |
| **FORCES Pro** | Code-Generierung für eingebettete MPC | Kommerziell |
| **CasADi** | Symbolische Differentiation + QP-Backend | Python/C++, kein C-API |

---

## Detailvergleich: OSQP vs. HPIPM

| Merkmal | OSQP | HPIPM |
|---|---|---|
| **Algorithmus** | ADMM (first-order) | IPM + Riccati-Rekursion |
| **Sparsität** | Allgemein (CSC-Format) | Block-tridiagonal (OCP-spezifisch) |
| **Genauigkeit** | Mittel (~10⁻⁶) – oft ausreichend | Hoch (~10⁻¹²) konsistent |
| **Warm-Start** | ✅ sehr gut | ✅ gut |
| **Echtzeit** | ✅ vorhersagbares Zeitverhalten | ✅ konsistenter als OSQP |
| **C-API-Regularität** | ~15 Hauptfunktionen, sehr sauber | ~30 Funktionen, strukturiert |
| **Ohne Drittabhängigkeiten** | ✅ (nur eigene Mathe-Routinen) | ⚠️ nutzt BLASFEO intern |
| **Einbettbarkeit** | ✅ (auch µC via code-gen) | ✅ (acados nutzt es) |
| **cl-cl-generator Eignung** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ |

---

## Warum OSQP am besten zu cl-cl-generator passt

### 1. Reguläre, kleine C-API

Die gesamte öffentliche API besteht aus ~15 Funktionen mit vorhersagbaren Signaturen:

```c
// Alle Funktionen folgen dem Muster:
OSQPInt osqp_<verb>(OSQPSolver* solver, ...);
```

Das ist **exakt** das Pattern, das sich mit einem `loop` generieren lässt:

```lisp
,@(loop for (name ret-type params doc) in osqp-api-spec
        collect
        `(cffi:defcfun (,(format nil "osqp_~a" name)
                        ,(intern (format nil "OSQP-~a" (string-upcase name))))
             ,ret-type
           (comment ,doc)
           ,@params))
```

### 2. Klare Struct-Hierarchie

Nur 5 Haupt-Structs, alle flat oder mit einfachen Pointer-Feldern:

```
OSQPSolver
├── OSQPSettings  (alle skalare Felder: float/int)
├── OSQPSolution  (float*-Arrays)
├── OSQPInfo      (Status + Timings)
└── OSQPWorkspace (opak – nur Pointer nötig)
```

Jeder Struct-Typ lässt sich als Datentabelle beschreiben und per Loop in `cffi:defcstruct` umwandeln.

### 3. Kein Header-Parser nötig

Im Gegensatz zu SuiteSparse (>200 Funktionen, komplexe Makros) ist das OSQP-API
klein genug, um es als S-Expression-Spec manuell zu beschreiben – und dann
**für alle Zukunft aus dieser einen Beschreibung zu regenerieren**.

---

## Skizze: cl-cl-generator für OSQP-Bindings

```lisp
;;; gen-osqp-cffi.lisp – Generiert osqp-cffi.lisp

(defparameter *osqp-structs*
  '((osqp-settings
     ((rho           :double "ADMM step ρ")
      (sigma         :double "Regularisierung σ")
      (max-iter      :int    "Max. Iterationen")
      (eps-abs       :double "Absolute Toleranz")
      (eps-rel       :double "Relative Toleranz")
      (verbose       :bool   "Ausgabe an/aus")
      (warm-starting :bool   "Warm-start aktivieren")))
    (osqp-solution
     ((x             :pointer "Primal-Lösung")
      (y             :pointer "Dual-Lösung (Lagrange)")))
    (osqp-info
     ((status     (:array :char 32) "Status-String")
      (status-val :int              "Numerischer Status")
      (obj-val    :double           "Zielfunktionswert")
      (run-time   :double           "Laufzeit gesamt [s]")
      (setup-time :double           "Setup-Zeit [s]")
      (solve-time :double           "Solve-Zeit [s]")))))

(defparameter *osqp-functions*
  '((setup   :int  ((solverp :pointer) (data :pointer) (settings :pointer))
             "Solver initialisieren + Matrizen faktorisieren")
    (solve   :int  ((solver :pointer))
             "QP lösen")
    (cleanup :int  ((solver :pointer))
             "Speicher freigeben")
    (warm-start :int ((solver :pointer) (x :pointer) (y :pointer))
                "Warm-Start mit bekannter Lösung")
    (update-lin-cost :int ((solver :pointer) (q :pointer))
                     "Linearen Kostenvektor q aktualisieren")
    (update-bounds   :int ((solver :pointer) (l :pointer) (u :pointer))
                     "Schranken l/u aktualisieren")))

(write-source "osqp-cffi"
  `(toplevel
     (in-package :osqp-bindings)

     (comment "Automatisch generiert von gen-osqp-cffi.lisp – nicht manuell bearbeiten")

     (cffi:load-foreign-library '(:default "libosqp"))

     ,@(loop for (struct-name fields) in *osqp-structs*
             collect
             `(cffi:defcstruct ,struct-name
                ,@(loop for (field type doc) in fields
                        collect
                        `(comment ,doc)
                        collect
                        `(,field ,type))))

     ,@(loop for (name ret-type params doc) in *osqp-functions*
             collect
             `(comment ,doc)
             collect
             `(cffi:defcfun (,(format nil "osqp_~a" (string-downcase name))
                             ,(intern (format nil "OSQP-~a" name)))
                  ,ret-type
                ,@params))))
  #P"source/")
```

---

## Empfehlung

> [!IMPORTANT]
> **Primär: OSQP** – ideale Balance aus Einfachheit der C-API, Lizenz, Performance und
> Eignung für cl-cl-generator. Die API ist klein genug für manuell gepflegte S-Expression-Spec,
> aber groß genug um den Mehrwert des Generators zu demonstrieren.

> [!TIP]
> **Sekundär: HPIPM** – wenn strukturierte OCP-Probleme (Robotik, Fahrdynamik) mit
> Block-Tridiagonal-Struktur gelöst werden sollen. Die etwas komplexere API demonstriert
> stärker die Fähigkeit des Generators, mehrere ähnliche Funktionen (z. B. `hpipm_ocp_qp_set_*`)
> per Loop zu generieren. HPIPM hat ~80 `_set_*`-Funktionen – **das ist der ideale Loop-Kandidat.**

### Stufenplan

```
1. cl-osqp-cffi  (OSQP-Bindings via cl-cl-generator, ~1 Tag)
     └─ Basis: libosqp.so, ~15 Funktionen, 5 Structs
     
2. cl-mpc-utils  (MPC-Matrizen-Builder in Lisp: Q, R, A_bar, B_bar)
     └─ Generiert: Kostenfunktion + Constraint-Matrizen für Horizont N
     
3. cl-hpipm-cffi (optional, für strukturierte OCP-Probleme)
     └─ Basis: ~80 hpipm_ocp_qp_set_*-Funktionen → idealer Loop-Demo
```
