# Plan: HPIPM CFFI-Binding-Generator mit cl-cl-generator

## Ziel

Ein cl-cl-generator-Beispiel, das aus einer kompakten S-Expression-Spezifikation
vollständige CFFI-Bindings für die HPIPM C-Bibliothek generiert. Das Beispiel
demonstriert die Mächtigkeit des Generators bei hochrepetitiven APIs.

## Hintergrund

### Was ist HPIPM?

HPIPM (High-Performance Interior-Point Method) ist ein Open-Source QP-Solver
(GPL-3.0 + Classpath Exception) der speziell für Optimal-Control-Probleme (OCP)
entwickelt wurde. Er nutzt Riccati-Rekursion zur Ausnutzung der
Block-Tridiagonalstruktur von MPC-Problemen und erreicht O(N·(nx³+nu³))
Komplexität – linear im Horizont N.

### HPIPM OCP-QP-Formulierung

Das Problem das HPIPM löst:

```
minimize   Σ(k=0..N) [uₖ xₖ]ᵀ [Rₖ Sₖᵀ; Sₖ Qₖ] [uₖ; xₖ] + [rₖᵀ qₖᵀ] [uₖ; xₖ]

subject to  x_{k+1} = Aₖ xₖ + Bₖ uₖ + bₖ        (Dynamik)
            lbxₖ  ≤ xₖ ≤ ubxₖ                      (Box-Zustände)
            lbuₖ  ≤ uₖ ≤ ubuₖ                      (Box-Eingänge)
            lgₖ   ≤ Cₖ xₖ + Dₖ uₖ ≤ ugₖ           (Allgemeine Constraints)
            + optionale Soft-Constraints (Zl, Zu, zl, zu)
```

### Warum HPIPM als cl-cl-generator Beispiel?

Die HPIPM C-API ist **extrem regulär**: Dutzende Funktionen folgen identischen
Namensmustern. Genau dieses Muster ist der ideale Anwendungsfall für
`cl-cl-generator` mit `,@(loop ...)`.

---

## HPIPM C-API Details (aus DeepWiki & Quellcode)

### Namenskonvention

Alle Funktionen folgen dem Muster:
```
d_ocp_qp_<objekt>_<verb>[_<suffix>]
```

### Memory-Management-Pattern

HPIPM nutzt ein **explizites 2-Schritt-Pattern**:

```c
// 1. Speicherbedarf berechnen
hpipm_size_t size = d_ocp_qp_dim_memsize(N);

// 2. User allokiert selbst (64-Byte-Alignment für Cache-Linien)
void *mem = malloc(size);

// 3. Struct deklarieren
struct d_ocp_qp_dim dim;

// 4. Create initialisiert den Struct im vorallokierten Speicher
d_ocp_qp_dim_create(N, &dim, mem);
```

Dieses Pattern wiederholt sich für **jeden** der 5 Struct-Typen → perfekter
Loop-Kandidat im Generator.

### 5 Haupt-Structs

| Struct | Header | Zweck |
|---|---|---|
| `d_ocp_qp_dim` | `hpipm_d_ocp_qp_dim.h` | Dimensionen (nx, nu, nb, ng pro Stufe) |
| `d_ocp_qp` | `hpipm_d_ocp_qp.h` | QP-Daten (A, B, Q, R, S, q, r, …) |
| `d_ocp_qp_sol` | `hpipm_d_ocp_qp_sol.h` | Lösung (x, u, pi, lam, …) |
| `d_ocp_qp_ipm_arg` | `hpipm_d_ocp_qp_ipm.h` | Solver-Einstellungen (mu0, alpha_min, toleranzen, …) |
| `d_ocp_qp_ipm_ws` | `hpipm_d_ocp_qp_ipm.h` | Solver-Workspace (opak) |

#### Struct-Felder (aus DeepWiki)

**d_ocp_qp_dim:**
- `nx`, `nu`, `nb`, `nbx`, `nbu`, `ng`, `ns`, `nbxe`, `nbue`, `nge` (int-Pointer je Stufe)
- `N` (int, Horizontlänge)
- `memsize` (hpipm_size_t)

**d_ocp_qp:**
- `dim` → Pointer auf d_ocp_qp_dim
- `BAbt` → blasfeo_dmat Array (Dynamik: A, B, b zusammengepackt)
- `RSQrq` → blasfeo_dmat Array (Kosten: R, S, Q, r, q zusammengepackt)
- `DCt` → blasfeo_dmat Array (Constraints: D, C zusammengepackt)
- `b`, `rqz`, `d`, `d_mask`, `m`, `Z` → blasfeo_dvec Arrays
- `idxb`, `idxs_rev`, `idxe` → int** (Indizes)
- `diag_H_flag` → int* (Flag: diagonaler Hessian)

**d_ocp_qp_sol:**
- `dim` → Pointer auf d_ocp_qp_dim
- `ux` → blasfeo_dvec Array (Primal: u und x zusammengepackt)
- `pi` → blasfeo_dvec Array (Dual: Dynamik-Multiplikatoren)
- `lam` → blasfeo_dvec Array (Dual: Ungleichungs-Multiplikatoren)
- `t` → blasfeo_dvec Array (Slack-Variablen)

**d_ocp_qp_ipm_arg:**
- `mu0`, `alpha_min` (double)
- `res_g_max`, `res_b_max`, `res_d_max`, `res_m_max` (double, Toleranzen)
- `iter_max`, `stat_max` (int)
- `warm_start`, `pred_corr`, `square_root_alg`, `lq_fact` (int, Flags)
- `reg_prim` (double, Primal-Regularisierung)
- `lam_min`, `t_min`, `tau_min` (double)

### Vollständige Feldnamen-Listen

#### d_ocp_qp_dim_set – 9 Felder
```
nx  nu  nbx  nbu  ng  ns  nbxe  nbue  nge
```

#### d_ocp_qp_set – ~48 Felder
**Matrizen:**
```
A  B  Q  S  R  C  D
```

**Vektoren:**
```
b  q  r
lb  lb_mask  lbu  lbu_mask  lbx  lbx_mask
ub  ub_mask  ubu  ubu_mask  ubx  ubx_mask
lg  lg_mask  ug  ug_mask
Zl  Zu  zl  zu  lls  lls_mask  lus  lus_mask
```

**Indizes/Flags:**
```
idxb  idxbx  idxbu  idxs  idxs_rev  idxe  idxbue  idxbxe  idxge
Jbx  Jbu  Jsbu  Jsbx  Jsg  Jbue  Jbxe  Jge
diag_H_flag
```

Aliase: `lu`=`lbu`, `lx`=`lbx`, `uu`=`ubu`, `ux`=`ubx`, `Jx`=`Jbx`, `Ju`=`Jbu`, `Jsx`=`Jsbx`, `Jsu`=`Jsbu`

#### d_ocp_qp_sol_get – ~12 Felder
```
u  x  sl  su  pi
lam_lb  lam_lbu  lam_lbx  lam_ub  lam_ubu  lam_ubx  lam_lg  lam_ug
```

### Lifecycle-Funktionen (pro Struct-Typ)

Jeder der 5 Struct-Typen hat das gleiche Pattern:

| Funktion | Signatur-Pattern |
|---|---|
| `_memsize` | `hpipm_size_t d_ocp_qp_<obj>_memsize(<deps>)` |
| `_create` | `void d_ocp_qp_<obj>_create(<deps>, struct d_ocp_qp_<obj> *obj, void *mem)` |
| `_set_default` | `void d_ocp_qp_ipm_arg_set_default(enum hpipm_mode mode, struct d_ocp_qp_ipm_arg *arg)` |
| `_set` | `void d_ocp_qp_<obj>_set(char *field, int stage, <value>, struct d_ocp_qp_<obj> *obj)` |
| `_get` | `void d_ocp_qp_<obj>_get(char *field, int stage, <value>, struct d_ocp_qp_<obj> *obj)` |

**Solver-Aufruf:**
```c
void d_ocp_qp_ipm_solve(
    struct d_ocp_qp *qp,
    struct d_ocp_qp_sol *qp_sol,
    struct d_ocp_qp_ipm_arg *arg,
    struct d_ocp_qp_ipm_ws *ws);
```

**Bulk-Setter (Alternative):**
```c
void d_ocp_qp_dim_set_all(
    int *nx, int *nu, int *nbx, int *nbu, int *ng, int *ns,
    struct d_ocp_qp_dim *dim);

void d_ocp_qp_set_all(
    double **A, double **B, double **b,
    double **Q, double **S, double **R, double **q, double **r,
    int **idxbx, double **lbx, double **ubx,
    int **idxbu, double **lbu, double **ubu,
    double **C, double **D, double **lg, double **ug,
    double **Zl, double **Zu, double **zl, double **zu,
    int **idxs, int **idxs_rev, double **ls, double **us,
    struct d_ocp_qp *qp);
```

### Zusammenfassung: Reguläre Funktionen

| Gruppe | Anzahl | Pattern |
|---|---|---|
| Dim-Setters | 9 | `d_ocp_qp_dim_set("field", stage, val, dim)` |
| QP-Setters | ~48 | `d_ocp_qp_set("field", stage, ptr, qp)` |
| Sol-Getters | ~12 | `d_ocp_qp_sol_get("field", stage, ptr, sol)` |
| Lifecycle (5 Typen × ~4 Fkt.) | ~20 | `d_ocp_qp_<obj>_{memsize,create,set,get}` |
| Bulk-Setters | 2 | `d_ocp_qp_dim_set_all`, `d_ocp_qp_set_all` |
| Solver | 1 | `d_ocp_qp_ipm_solve` |
| **Gesamt** | **~92** | Fast alle aus Datentabellen per Loop generierbar |

---

## Vorgehensplan

### Phase 1: Generator-Kern (`gen.lisp`)

Datei: `example/06_hpipm_cffi/gen.lisp`

Der Generator enthält:

1. **API-Spezifikation als S-Expression-Datentabellen**:
   ```lisp
   (defparameter *dim-fields*
     '(("nx"   :int "Anzahl Zustaende pro Stufe")
       ("nu"   :int "Anzahl Eingaenge pro Stufe")
       ("nbx"  :int "Anzahl Box-Constraints auf Zustaende")
       ("nbu"  :int "Anzahl Box-Constraints auf Eingaenge")
       ("ng"   :int "Anzahl allgemeine Constraints")
       ("ns"   :int "Anzahl Soft-Constraint-Slacks")
       ("nbxe" :int "Zustandsgrenzen die Gleichheiten sind")
       ("nbue" :int "Eingangsgrenzen die Gleichheiten sind")
       ("nge"  :int "Allgemeine Constraints die Gleichheiten sind")))

   (defparameter *qp-fields*
     '(;; Matrizen
       ("A" :pointer "Dynamik-Matrix Ak (Zustand->Zustand)")
       ("B" :pointer "Dynamik-Matrix Bk (Eingang->Zustand)")
       ("Q" :pointer "Kosten-Hessian Qk (Zustand)")
       ("R" :pointer "Kosten-Hessian Rk (Eingang)")
       ("S" :pointer "Kosten-Kreuzterm Sk (Zustand×Eingang)")
       ("C" :pointer "Allg. Constraint-Matrix Ck (Zustand)")
       ("D" :pointer "Allg. Constraint-Matrix Dk (Eingang)")
       ;; Vektoren
       ("b" :pointer "Dynamik-Offset bk")
       ("q" :pointer "Kosten-Gradient qk (Zustand)")
       ("r" :pointer "Kosten-Gradient rk (Eingang)")
       ("lbx" :pointer "Untere Schranke Zustaende")
       ("ubx" :pointer "Obere Schranke Zustaende")
       ("lbu" :pointer "Untere Schranke Eingaenge")
       ("ubu" :pointer "Obere Schranke Eingaenge")
       ("lg"  :pointer "Untere Schranke allg. Constraints")
       ("ug"  :pointer "Obere Schranke allg. Constraints")
       ;; Indizes
       ("idxbx" :pointer "Indizes der Box-Zustandsgrenzen")
       ("idxbu" :pointer "Indizes der Box-Eingangsgrenzen")
       ;; Soft Constraints
       ("Zl" :pointer "Soft-Constraint Hessian (untere)")
       ("Zu" :pointer "Soft-Constraint Hessian (obere)")
       ("zl" :pointer "Soft-Constraint Gradient (untere)")
       ("zu" :pointer "Soft-Constraint Gradient (obere)")
       ...))

   (defparameter *sol-fields*
     '(("u"       :pointer "Optimale Eingaenge")
       ("x"       :pointer "Optimale Zustaende")
       ("pi"      :pointer "Duale Variablen (Dynamik)")
       ("sl"      :pointer "Slack-Variablen (untere)")
       ("su"      :pointer "Slack-Variablen (obere)")
       ("lam_lb"  :pointer "Lagrange-Mult. (Box untere)")
       ("lam_ub"  :pointer "Lagrange-Mult. (Box obere)")
       ("lam_lbu" :pointer "Lagrange-Mult. (Eingang untere)")
       ("lam_ubu" :pointer "Lagrange-Mult. (Eingang obere)")
       ("lam_lbx" :pointer "Lagrange-Mult. (Zustand untere)")
       ("lam_ubx" :pointer "Lagrange-Mult. (Zustand obere)")
       ("lam_lg"  :pointer "Lagrange-Mult. (allg. untere)")
       ("lam_ug"  :pointer "Lagrange-Mult. (allg. obere)")))
   ```

2. **Lifecycle-Spezifikation als S-Expression**:
   ```lisp
   (defparameter *hpipm-objects*
     '((dim     "ocp_qp_dim"     ((:memsize (N :int))
                                   (:create  (N :int) (dim :pointer) (mem :pointer))))
       (qp      "ocp_qp"         ((:memsize (dim :pointer))
                                   (:create  (dim :pointer) (qp :pointer) (mem :pointer))))
       (sol     "ocp_qp_sol"     ((:memsize (dim :pointer))
                                   (:create  (dim :pointer) (sol :pointer) (mem :pointer))))
       (ipm-arg "ocp_qp_ipm_arg" ((:memsize (dim :pointer))
                                   (:create  (dim :pointer) (arg :pointer) (mem :pointer))))
       (ipm-ws  "ocp_qp_ipm_ws"  ((:memsize (dim :pointer) (arg :pointer))
                                   (:create  (dim :pointer) (arg :pointer) (ws :pointer) (mem :pointer))))))
   ```

3. **Loop-basierte Code-Generierung**:
   ```lisp
   ;; Dimension-Setter: 9 Funktionen aus einer Tabelle
   ,@(loop for (field type doc) in *dim-fields*
           collect `(comment ,doc)
           collect `(defun ,(intern (format nil "HPIPM-DIM-SET-~a"
                                           (string-upcase field)))
                        (stage value dim)
                     (d-ocp-qp-dim-set ,field stage value dim)))

   ;; QP-Data-Setter: ~25 Funktionen aus einer Tabelle
   ,@(loop for (field type doc) in *qp-fields*
           collect `(comment ,doc)
           collect `(defun ,(intern (format nil "HPIPM-QP-SET-~a"
                                           (string-upcase field)))
                        (stage value qp)
                     (d-ocp-qp-set ,field stage value qp)))

   ;; Solution-Getter: ~12 Funktionen aus einer Tabelle
   ,@(loop for (field type doc) in *sol-fields*
           collect ...)

   ;; Lifecycle: 5 × {memsize, create} = 10 Funktionen aus einer Tabelle
   ,@(loop for (name c-name funcs) in *hpipm-objects*
           append (loop for (verb . params) in funcs
                        collect ...))
   ```

### Phase 2: Generierter Code (`source01/`)

Die generierten Dateien in `source01/`:

| Datei | Inhalt | Geschätzte Größe |
|---|---|---|
| `package.lisp` | Package-Definition `:hpipm` | ~15 Zeilen |
| `hpipm-cffi.lisp` | Low-level CFFI-Bindings (defcfun) für double+single | ~400 Zeilen |
| `hpipm-wrappers.lisp` | Typsichere Lisp-Wrapper mit Docstrings | ~600 Zeilen |
| `hpipm.asd` | ASDF-Systemdefinition | ~20 Zeilen |

**Verhältnis**: ~200 Zeilen Generator → ~1035 Zeilen generierter Code (5:1 Kompression)

### Phase 3: MPC-Anwendungsbeispiel

Datei: `source01/mpc-demo.lisp` (ebenfalls generiert)

Eine MPC-Demo die:
1. Ein lineares System definiert (Masse-Feder-Dämpfer: nx=4, nu=1)
2. Diskretisierung per Euler (Abtastzeit dt)
3. Die QP-Kosten- und Constraint-Matrizen per Horizont N aufstellt
4. HPIPM aufruft (dim → qp → sol → ipm_arg → ipm_ws → solve)
5. Die optimalen Eingänge u* und Zustände x* zurückgibt

---

## Dateistruktur

```
example/06_hpipm_cffi/
├── plan.md              ← dieses Dokument
├── gen.lisp             ← Generator (liest API-Spec, schreibt source01/)
├── source01/
│   ├── hpipm.asd        ← generiert
│   ├── package.lisp     ← generiert
│   ├── hpipm-cffi.lisp  ← generiert (~184 defcfun, double+single)
│   ├── hpipm-wrappers.lisp ← generiert (typsichere Lisp-Wrapper)
│   └── mpc-demo.lisp   ← generiert (Masse-Feder-Dämpfer MPC-Beispiel)
└── README.md            ← Beschreibung + Anleitung
```

## Was dieses Beispiel demonstriert

1. **Massive Loop-Generierung**: ~184 CFFI-Funktionen (double+single) aus ~4 Datentabellen
2. **Kommentar-Integration**: Jede generierte Funktion hat Dokumentation aus der Spec
3. **Konsistenz-Garantie**: Änderungen an der API-Spec regenerieren alle Bindings
4. **mtime-Caching**: `write-source` überschreibt nur bei echten Änderungen
5. **Memory-Management-Wrapper**: Lisp-Wrapper die das malloc/memsize/create-Pattern kapseln
6. **Cross-Domain**: Lisp-Generator → CFFI-Bindings → C-Bibliothek → Echtzeit-Kontrolle

## Abhängigkeiten

- BLASFEO (HPIPM-Unterbau, BSD-2-Clause): `libblasfeo.so`
- HPIPM (GPL-3.0 + Classpath Exception): `libhpipm.so`
- CFFI (Common Lisp FFI)
- cl-cl-generator

## Entscheidungen (geklärt)

1. ✅ **Single-Precision-Varianten** (`s_ocp_qp_*`) werden mitgeneriert.
   Der Generator iteriert über `'(("d" :double) ("s" :single-float))` und
   erzeugt beide Varianten aus derselben Spec. → ~184 Funktionen gesamt.
   Demonstriert die Loop-Mächtigkeit besonders eindrücklich.

2. ✅ **MPC-Beispiel** (Masse-Feder-Dämpfer, nx=4, nu=1) wird als
   generierter Lisp-Code mitgeliefert. Zeigt den vollständigen Workflow:
   Systemdefinition → QP-Aufstellung → HPIPM-Aufruf → Lösung extrahieren.

3. ✅ **Opake Pointer** für BLASFEO-Structs. HPIPMs `_set`/`_get`-Funktionen
   akzeptieren reguläre `double*`-Arrays und packen intern in BLASFEO-Format
   (`blasfeo_pack_dmat`). Keine BLASFEO-Bindings nötig.
