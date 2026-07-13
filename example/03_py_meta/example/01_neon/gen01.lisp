(eval-when (:compile-toplevel :execute :load-toplevel)
  ;; Füge den Pfad zum cl-cl-generator in die ASDF-Registrierung ein, damit Quicklisp das Paket finden kann.
  (push "/workspace/src/cl-cl-generator/example/03_py_meta/" asdf:*central-registry*)
  ;; Lade das cl-py-generator-example-Paket mit Quicklisp.
  (ql:quickload :cl-py-generator-example))

;; Definiere das Lisp-Paket für dieses Beispiel.
(defpackage :cl-py-generator/example-neon
  (:use :cl :cl-py-generator))

(in-package :cl-py-generator/example-neon)

;; Ausgabeverzeichnis, in dem die generierten Python-Dateien gespeichert werden.
(defparameter *output-dir* "/workspace/src/cl-cl-generator/example/03_py_meta/example/01_neon/source01/")

;; =========================================================================
;; 1. Definiere den S-Expression Code für solver.py
;; =========================================================================
(defparameter *solver-code*
  `(progn
     ;; Importiere die benötigten Python-Bibliotheken:
     ;; - jax: Google-Bibliothek für automatische Differenzierung und GPU/TPU-Beschleunigung.
     ;; - jnp (jax.numpy): JAX-Variante von NumPy, die auf Beschleunigern läuft und differenzierbar ist.
     ;; - jsp (jax.scipy.special): Spezielle mathematische Funktionen (wie log-Gamma) in JAX.
     ;; - jaxopt: Bibliothek für hardwarebeschleunigte und differenzierbare Optimierungsalgorithmen.
     (import jax
             (jnp jax.numpy)
             (jsp jax.scipy.special)
             jaxopt)
     (jax.config.update (string "jax_enable_x64") True)

     ;; Die Lichtgeschwindigkeit in atomaren Einheiten (Hartree-Einheiten): c ≈ 137.035999
     ;; Sie entspricht dem Kehrwert der Feinstrukturkonstante alpha (1/alpha).
     (setf C_LIGHT 137.035999)

     ;; safe_I_k berechnet das analytische radiale Integral über eine Gauß-Funktion:
     ;;   I_k(a) = \int_0^\infty r^k \exp(-a \cdot r^2) dr = 0.5 \cdot a^{-(k+1)/2} \cdot \Gamma((k+1)/2)
     ;; Um numerischen Überlauf bei großen Gamma-Werten zu verhindern, wird die Log-Gamma-Funktion
     ;; (jsp.gammaln) verwendet und das Ergebnis erst danach exponentiiert (jnp.exp).
     ;; jnp.where verhindert Divisionen durch Null oder negative Argumente bei der Gammafunktion.
     (def safe_I_k (k a)
       (setf k_safe (jnp.where (> k -1.0) k 1.0)
             val (* 0.5
                    (jnp.power a (* -0.5 (+ k_safe 1.0)))
                    (jnp.exp (jsp.gammaln (* 0.5 (+ k_safe 1.0))))))
       (return (jnp.where (> k -1.0) val 0.0)))

     ;; compute_matrices berechnet die relativistischen Einteilchen-Matrizen (Hamiltonian und Overlap)
     ;; für einen bestimmten Bahndrehimpuls (l), Quantenzahl kappa und Kernladung Z.
     ;; Es implementiert die "Kinetic Balance" (kinetische Bilanz) zwischen großen und kleinen Komponenten
     ;; der Dirac-Spinoren, um einen variationellen Kollaps in den Dirac-See (negative Energiezustände) zu verhindern.
     (def compute_matrices (exponents l kappa Z &key (c C_LIGHT) (mu 1.0))
       (setf N (len exponents)
             alpha (jnp.array exponents)
             
             ;; I_norm berechnet die Normierungsintegrale für die GTO-Basisfunktionen.
             I_norm ((jax.vmap (lambda (a) (safe_I_k (+ (* 2 l) 2) (* 2.0 a)))) alpha)
             ;; Normierungskoeffizienten C_i so, dass das Integral über das Quadrat der Basisfunktion 1 ergibt.
             C (/ 1.0 (jnp.sqrt I_norm))
             
             ;; Berechne die Summe der Exponenten alpha_i + alpha_j für alle Paare im Gitter (Grid)
             ;; jnp.array[:, None] + jnp.array[None, :] erzeugt eine N x N Matrix der Exponentensummen.
             alpha_grid (+ (aref alpha (slice nil nil) None)
                           (aref alpha None (slice nil nil)))
                           
             ;; Überlappungs-Integral der großen Komponente (Large-Large, S_LL)
             I_grid ((jax.vmap (jax.vmap (lambda (a) (safe_I_k (+ (* 2 l) 2) a)))) alpha_grid)
             S_LL (* (aref C (slice nil nil) None)
                     (aref C None (slice nil nil))
                     I_grid)
                     
             ;; Kinetische Bilanz (Kinetic Balance) verknüpft die kleine Komponente f_i(r) mit der großen g_i(r):
             ;;   f_i(r) = 1/(2c) * (d/dr + kappa/r) g_i(r)
             ;; Die folgenden Terme term1, term2, term3 berechnen die Matrixelemente des Überlapps der kleinen
             ;; Komponente (Small-Small, S_SS) unter Verwendung dieser Ableitungsbeziehung.
             A (+ l 1 kappa)
             B (* -2.0 alpha)
             I_2l ((jax.vmap (jax.vmap (lambda (a) (safe_I_k (* 2 l) a)))) alpha_grid)
             I_2l2 ((jax.vmap (jax.vmap (lambda (a) (safe_I_k (+ (* 2 l) 2) a)))) alpha_grid)
             I_2l4 ((jax.vmap (jax.vmap (lambda (a) (safe_I_k (+ (* 2 l) 4) a)))) alpha_grid)
             term1 (* A A I_2l)
             term2 (* A (+ (aref B (slice nil nil) None) (aref B None (slice nil nil))) I_2l2)
             term3 (* (aref B (slice nil nil) None) (aref B None (slice nil nil)) I_2l4)
             S_SS (* (/ (* (aref C (slice nil nil) None) (aref C None (slice nil nil)))
                        (* 4.0 (** c 2)))
                     (+ term1 term2 term3))
                     
             ;; Elektrostatische potentielle Energie der großen Komponente (V_LL)
             ;; Berechnet das Integral des Coulomb-Potentials V(r) = -Z/r zwischen großen Komponenten.
             I_2l1 ((jax.vmap (jax.vmap (lambda (a) (safe_I_k (+ (* 2 l) 1) a)))) alpha_grid)
             V_LL (* -1.0 Z
                     (aref C (slice nil nil) None)
                     (aref C None (slice nil nil))
                     I_2l1)
                     
             ;; Elektrostatische potentielle Energie der kleinen Komponente (V_SS)
             ;; Berechnet das Integral des Coulomb-Potentials V(r) = -Z/r zwischen kleinen Komponenten.
             I_2l_minus_1 ((jax.vmap (jax.vmap (lambda (a) (safe_I_k (- (* 2 l) 1) a)))) alpha_grid)
             I_2l3 ((jax.vmap (jax.vmap (lambda (a) (safe_I_k (+ (* 2 l) 3) a)))) alpha_grid)
             term_v1 (* A A I_2l_minus_1)
             term_v2 (* A (+ (aref B (slice nil nil) None) (aref B None (slice nil nil))) I_2l1)
             term_v3 (* (aref B (slice nil nil) None) (aref B None (slice nil nil)) I_2l3)
             V_SS (* -1.0 Z
                     (/ (* (aref C (slice nil nil) None) (aref C None (slice nil nil)))
                        (* 4.0 (** c 2)))
                     (+ term_v1 term_v2 term_v3))
                     
             ;; Setze die Dirac-Hamilton-Matrix H aus den Blöcken zusammen (2N x 2N Matrix):
             ;;   H = [ V_LL + mu*c^2*S_LL,         2*c^2*S_SS       ]
             ;;       [     2*c^2*S_SS,     V_SS - mu*c^2*S_SS       ]
             ;; Wobei mu die reduzierte Masse für die Kernbewegung darstellt.
             H (jnp.block (list (list (+ V_LL (* mu (** c 2) S_LL)) (* 2.0 (** c 2) S_SS))
                                (list (* 2.0 (** c 2) S_SS) (- V_SS (* mu (** c 2) S_SS)))))
                                
             ;; Setze die Gesamt-Überlappungsmatrix S_overlap aus S_LL und S_SS zusammen (Blockdiagonale).
             S_overlap (jnp.block (list (list S_LL (jnp.zeros (tuple N N)))
                                         (list (jnp.zeros (tuple N N)) S_SS))))
        (return (tuple H S_overlap S_LL S_SS V_LL V_SS)))

     ;; compute_G_generic berechnet die relativistischen Zweielektronen-Wechselwirkungsintegrale (Coulomb & Austausch)
     ;; für vier Wellenfunktions-Zentren (hier vereinfacht auf ein gemeinsames Zentrum für ein einzelnes Atom).
     ;; Das Integral lautet: G = \iint \phi_a(r_1) \phi_b(r_1) \frac{1}{|r_1 - r_2|} \phi_c(r_2) \phi_d(r_2) d^3r_1 d^3r_2
     ;; Durch das Gauß-Produkt-Theorem wird das Produkt zweier Gauß-Kurven mit Exponenten a und b wieder als eine
     ;; Gauß-Kurve mit Exponent p = a+b dargestellt. Die Integration über 1/|r_1 - r_2| wird analytisch durchgeführt.
     (def compute_G_generic (alpha_a l_a alpha_b l_b alpha_c l_c alpha_d l_d)
       (setf C_a (/ 1.0 (jnp.sqrt ((jax.vmap (lambda (a) (safe_I_k (+ (* 2 l_a) 2) (* 2.0 a)))) alpha_a)))
             C_b (/ 1.0 (jnp.sqrt ((jax.vmap (lambda (a) (safe_I_k (+ (* 2 l_b) 2) (* 2.0 a)))) alpha_b)))
             C_c (/ 1.0 (jnp.sqrt ((jax.vmap (lambda (a) (safe_I_k (+ (* 2 l_c) 2) (* 2.0 a)))) alpha_c)))
             C_d (/ 1.0 (jnp.sqrt ((jax.vmap (lambda (a) (safe_I_k (+ (* 2 l_d) 2) (* 2.0 a)))) alpha_d)))
             
             ;; Erzeuge ein 4D-Gitter (Tensor-Produkt) der Exponenten für alle Kombinationen der 4 Indizes.
             ;; aref [:, None, None, None] expandiert die Dimensionen für effizientes Broadcasting in NumPy/JAX.
             a_grid (aref alpha_a (slice nil nil) None None None)
             b_grid (aref alpha_b None (slice nil nil) None None)
             c_grid (aref alpha_c None None (slice nil nil) None)
             d_grid (aref alpha_d None None None (slice nil nil))
             
             p (+ a_grid b_grid)
             q (+ c_grid d_grid)
             
             ;; Analytischer Kern des Coulomb-Integrals zwischen zwei Gauß-Ladungsverteilungen.
             prim (/ (* 2.0 (** jnp.pi 2.5))
                     (* p q (jnp.sqrt (+ p q))))
                     
             G (* (aref C_a (slice nil nil) None None None)
                  (aref C_b None (slice nil nil) None None)
                  (aref C_c None None (slice nil nil) None)
                  (aref C_d None None None (slice nil nil))
                  (/ 1.0 (* 16.0 (** jnp.pi 2)))
                  prim))
       (return G))

     ;; initial_state_energy berechnet die Gesamtenergie des Anfangszustands (2p^5 5s) von Neon.
     ;; Da Neon ein 10-Elektronen-System ist, modellieren wir:
     ;; - Rumpf- und Valenzzustände im s-Kanal (1s^2, 2s^2, 5s^1) -> total 5 Elektronen im s-Kanal
     ;; - Valenzzustände im p-Kanal (2p^5) -> total 5 Elektronen im p-Kanal
     (def initial_state_energy (params nuclear_mass)
       (setf log_alpha_s (jnp.linspace (jnp.log 0.01) (jnp.log 500.0) 8)
             log_alpha_p (jnp.linspace (jnp.log 0.05) (jnp.log 100.0) 6)
             X_s (aref params (string "X_s"))
             x_2p (aref params (string "x_2p"))
             alpha_s (jnp.exp log_alpha_s)
             alpha_p (jnp.exp log_alpha_p)
             
             M_au (* nuclear_mass 1822.888)
             mu (/ M_au (+ 1.0 M_au)))

       (setf (ntuple _ _ S_LL S_SS_1 V_LL_1 V_SS_1) (compute_matrices alpha_p 1 1 10.0 :mu mu)
             (ntuple _ _ _ S_SS_2 V_LL_2 V_SS_2) (compute_matrices alpha_p 1 -2 10.0 :mu mu)
             Np (len alpha_p)
             
             S_locked_avg (+ S_LL (* (/ 1.0 3.0) S_SS_1) (* (/ 2.0 3.0) S_SS_2))
             c_2p (/ x_2p (jnp.sqrt (jnp.dot x_2p (jnp.dot S_locked_avg x_2p))))

             H_locked_1 (+ V_LL_1 V_SS_1 (* (- 4.0 (* 2.0 mu)) (** C_LIGHT 2) S_SS_1))
             S_locked_1 (+ S_LL S_SS_1)
             E_2p_1 (/ (jnp.dot c_2p (jnp.dot H_locked_1 c_2p)) (jnp.dot c_2p (jnp.dot S_locked_1 c_2p)))
             
             H_locked_2 (+ V_LL_2 V_SS_2 (* (- 4.0 (* 2.0 mu)) (** C_LIGHT 2) S_SS_2))
             S_locked_2 (+ S_LL S_SS_2)
             E_2p_2 (/ (jnp.dot c_2p (jnp.dot H_locked_2 c_2p)) (jnp.dot c_2p (jnp.dot S_locked_2 c_2p)))
             
             E_2p (+ (* (/ 1.0 3.0) E_2p_1) (* (/ 2.0 3.0) E_2p_2))
             zeta_2p (* (/ 2.0 3.0) (- E_2p_2 E_2p_1)))

       (setf (ntuple _ _ S_s_LL S_s_SS V_s_LL V_s_SS) (compute_matrices alpha_s 0 -1 10.0 :mu mu)
             Ns (len alpha_s)
             S_s (+ S_s_LL S_s_SS)
             H_s (+ V_s_LL V_s_SS (* (- 4.0 (* 2.0 mu)) (** C_LIGHT 2) S_s_SS))
             
             ;; Loewdin-Symmetrische-Orthogonalisierung zur Orthonormalisierung der s-Orbitale:
             ;; Im s-Kanal müssen 3 Orbitale (1s, 2s, 5s) strikt orthogonal zueinander sein:
             ;;   <c_a | S_s | c_b> = delta_{ab}
             ;; Wir berechnen die Metrik-Matrix M_s = X_s^T * S_s * X_s, diagonalisieren sie zu V * Lambda * V^T,
             ;; und bestimmen den glatten Transformationsoperator M_s^(-1/2) = V * Lambda^(-1/2) * V^T.
             ;; Dies garantiert Stetigkeit der Gradienten ohne die Vorzeichensprünge einer QR-Zerlegung.
             M_s (jnp.dot (jnp.transpose X_s) (jnp.dot S_s X_s))
             (ntuple vals_s vecs_s) (jnp.linalg.eigh M_s)
             M_s_inv_sqrt (jnp.dot vecs_s (jnp.dot (jnp.diag (/ 1.0 (jnp.sqrt vals_s))) (jnp.transpose vecs_s)))
             C_s (jnp.dot X_s M_s_inv_sqrt)
             c_1s (aref C_s (slice nil nil) 0)
             c_2s (aref C_s (slice nil nil) 1)
             c_5s (aref C_s (slice nil nil) 2)
             
             E_1s (jnp.dot c_1s (jnp.dot H_s c_1s))
             E_2s (jnp.dot c_2s (jnp.dot H_s c_2s))
             E_5s (jnp.dot c_5s (jnp.dot H_s c_5s)))

       (setf G_s (compute_G_generic alpha_s 0 alpha_s 0 alpha_s 0 alpha_s 0)
             G_p (compute_G_generic alpha_p 1 alpha_p 1 alpha_p 1 alpha_p 1)
             G_ps_coul (compute_G_generic alpha_p 1 alpha_p 1 alpha_s 0 alpha_s 0)
             G_ps_exch (compute_G_generic alpha_p 1 alpha_s 0 alpha_p 1 alpha_s 0)
             
             J_1s_1s (jnp.einsum (string "i,j,k,l,ijkl->") c_1s c_1s c_1s c_1s G_s)
             J_2s_2s (jnp.einsum (string "i,j,k,l,ijkl->") c_2s c_2s c_2s c_2s G_s)
             J_1s_2s (jnp.einsum (string "i,j,k,l,ijkl->") c_1s c_1s c_2s c_2s G_s)
             K_1s_2s (jnp.einsum (string "i,j,k,l,ijkl->") c_1s c_2s c_1s c_2s G_s)
             J_1s_5s (jnp.einsum (string "i,j,k,l,ijkl->") c_1s c_1s c_5s c_5s G_s)
             K_1s_5s (jnp.einsum (string "i,j,k,l,ijkl->") c_1s c_5s c_1s c_5s G_s)
             J_2s_5s (jnp.einsum (string "i,j,k,l,ijkl->") c_2s c_2s c_5s c_5s G_s)
             K_2s_5s (jnp.einsum (string "i,j,k,l,ijkl->") c_2s c_5s c_2s c_5s G_s)
             
             J_2p_2p (jnp.einsum (string "i,j,k,l,ijkl->") c_2p c_2p c_2p c_2p G_p)
             K_2p_2p J_2p_2p
             
             J_2p_1s (jnp.einsum (string "i,j,k,l,ijkl->") c_2p c_2p c_1s c_1s G_ps_coul)
             K_2p_1s (jnp.einsum (string "i,j,k,l,ijkl->") c_2p c_1s c_2p c_1s G_ps_exch)
             J_2p_2s (jnp.einsum (string "i,j,k,l,ijkl->") c_2p c_2p c_2s c_2s G_ps_coul)
             K_2p_2s (jnp.einsum (string "i,j,k,l,ijkl->") c_2p c_2s c_2p c_2s G_ps_exch)
             J_2p_5s (jnp.einsum (string "i,j,k,l,ijkl->") c_2p c_2p c_5s c_5s G_ps_coul)
             K_2p_5s (jnp.einsum (string "i,j,k,l,ijkl->") c_2p c_5s c_2p c_5s G_ps_exch)
             
             E_ee (+ J_1s_1s
                     J_2s_2s
                     (* 10.0 J_2p_2p)
                     (* -4.0 K_2p_2p)
                     (* 4.0 J_1s_2s)
                     (* -2.0 K_1s_2s)
                     (* 2.0 J_1s_5s)
                     (* -1.0 K_1s_5s)
                     (* 2.0 J_2s_5s)
                     (* -1.0 K_2s_5s)
                     (* 10.0 J_2p_1s)
                     (* -5.0 K_2p_1s)
                     (* 10.0 J_2p_2s)
                     (* -5.0 K_2p_2s)
                     (* 5.0 J_2p_5s)
                     (* -2.5 K_2p_5s))
             
             E_elec (+ (* 2.0 E_1s) (* 2.0 E_2s) (* 5.0 E_2p) E_5s E_ee)
             
             H_SO (jnp.array (list (list (- E_elec (* 0.5 zeta_2p)) (* (/ 1.0 (jnp.sqrt 2.0)) zeta_2p))
                                   (list (* (/ 1.0 (jnp.sqrt 2.0)) zeta_2p) E_elec)))
                                   
             eigvals (jnp.linalg.eigh H_SO)
             
             ;; Euklidischer Regularisierungsterm: Stabilisiert den LBFGS-Suchschritt,
             ;; indem er die Norm der Parameter-Spalten nahe 1.0 hält. 
             ;; Dies hat KEINE Massenabhängigkeit und verändert den physikalischen Massengradienten nicht,
             ;; da der Wert im Optimum exakt Null ist.
             norm_penalty (* 1.0 (+ (** (- (jnp.dot (aref X_s (slice nil nil) 0) (aref X_s (slice nil nil) 0)) 1.0) 2)
                                    (** (- (jnp.dot (aref X_s (slice nil nil) 1) (aref X_s (slice nil nil) 1)) 1.0) 2)
                                    (** (- (jnp.dot (aref X_s (slice nil nil) 2) (aref X_s (slice nil nil) 2)) 1.0) 2)
                                    (** (- (jnp.dot x_2p x_2p) 1.0) 2))))
       ;; Gib den niedrigsten Eigenwert der SO-Matrix plus den Regularisierungsterm zurück.
       (return (+ (aref (aref eigvals 0) 0) norm_penalty)))

     ;; final_state_energy berechnet die Gesamtenergie des Endzustands (2p^5 3p) von Neon.
     ;; Im Endzustand modellieren wir:
     ;; - Rumpfzustände im s-Kanal (1s^2, 2s^2) -> total 4 Elektronen im s-Kanal
     ;; - Rumpf- und Valenzzustände im p-Kanal (2p^5, 3p^1) -> total 6 Elektronen im p-Kanal
     (def final_state_energy (params nuclear_mass)
       (setf log_alpha_s (jnp.linspace (jnp.log 0.01) (jnp.log 500.0) 8)
             log_alpha_p (jnp.linspace (jnp.log 0.05) (jnp.log 100.0) 6)
             X_s (aref params (string "X_s"))
             X_p (aref params (string "X_p"))
             alpha_s (jnp.exp log_alpha_s)
             alpha_p (jnp.exp log_alpha_p)
             M_au (* nuclear_mass 1822.888)
             mu (/ M_au (+ 1.0 M_au)))

       (setf (ntuple _ _ S_s_LL S_s_SS V_s_LL V_s_SS) (compute_matrices alpha_s 0 -1 10.0 :mu mu)
             S_s (+ S_s_LL S_s_SS)
             H_s (+ V_s_LL V_s_SS (* (- 4.0 (* 2.0 mu)) (** C_LIGHT 2) S_s_SS))
             
             ;; Loewdin-Verfahren für den s-Kanal (2 Dimensionen: 1s, 2s):
             ;; Löst das verallgemeinerte Orthonormalisierungsproblem stetig und differenzierbar.
             M_s (jnp.dot (jnp.transpose X_s) (jnp.dot S_s X_s))
             (ntuple vals_s vecs_s) (jnp.linalg.eigh M_s)
             M_s_inv_sqrt (jnp.dot vecs_s (jnp.dot (jnp.diag (/ 1.0 (jnp.sqrt vals_s))) (jnp.transpose vecs_s)))
             C_s (jnp.dot X_s M_s_inv_sqrt)
             c_1s (aref C_s (slice nil nil) 0)
             c_2s (aref C_s (slice nil nil) 1)
             
             E_1s (jnp.dot c_1s (jnp.dot H_s c_1s))
             E_2s (jnp.dot c_2s (jnp.dot H_s c_2s)))

       (setf (ntuple _ _ S_LL S_SS_1 V_LL_1 V_SS_1) (compute_matrices alpha_p 1 1 10.0 :mu mu)
             (ntuple _ _ _ S_SS_2 V_LL_2 V_SS_2) (compute_matrices alpha_p 1 -2 10.0 :mu mu)
             Np (len alpha_p)
             S_locked_avg (+ S_LL (* (/ 1.0 3.0) S_SS_1) (* (/ 2.0 3.0) S_SS_2))
             
             ;; Loewdin-Verfahren für den p-Kanal (2 Dimensionen: 2p, 3p) unter Verwendung der Locked-Mittelwert-Metrik:
             M_p (jnp.dot (jnp.transpose X_p) (jnp.dot S_locked_avg X_p))
             (ntuple vals_p vecs_p) (jnp.linalg.eigh M_p)
             M_p_inv_sqrt (jnp.dot vecs_p (jnp.dot (jnp.diag (/ 1.0 (jnp.sqrt vals_p))) (jnp.transpose vecs_p)))
             C_p (jnp.dot X_p M_p_inv_sqrt)
             c_2p (aref C_p (slice nil nil) 0)
             c_3p (aref C_p (slice nil nil) 1)

             H_locked_1 (+ V_LL_1 V_SS_1 (* (- 4.0 (* 2.0 mu)) (** C_LIGHT 2) S_SS_1))
             S_locked_1 (+ S_LL S_SS_1)
             E_2p_1 (/ (jnp.dot c_2p (jnp.dot H_locked_1 c_2p)) (jnp.dot c_2p (jnp.dot S_locked_1 c_2p)))
             E_3p_1 (/ (jnp.dot c_3p (jnp.dot H_locked_1 c_3p)) (jnp.dot c_3p (jnp.dot S_locked_1 c_3p)))
             
             H_locked_2 (+ V_LL_2 V_SS_2 (* (- 4.0 (* 2.0 mu)) (** C_LIGHT 2) S_SS_2))
             S_locked_2 (+ S_LL S_SS_2)
             E_2p_2 (/ (jnp.dot c_2p (jnp.dot H_locked_2 c_2p)) (jnp.dot c_2p (jnp.dot S_locked_2 c_2p)))
             E_3p_2 (/ (jnp.dot c_3p (jnp.dot H_locked_2 c_3p)) (jnp.dot c_3p (jnp.dot S_locked_2 c_3p)))
             
             E_2p (+ (* (/ 1.0 3.0) E_2p_1) (* (/ 2.0 3.0) E_2p_2))
             E_3p (+ (* (/ 1.0 3.0) E_3p_1) (* (/ 2.0 3.0) E_3p_2))
             zeta_2p (* (/ 2.0 3.0) (- E_2p_2 E_2p_1))
             zeta_3p (* (/ 2.0 3.0) (- E_3p_2 E_3p_1)))

       (setf G_s (compute_G_generic alpha_s 0 alpha_s 0 alpha_s 0 alpha_s 0)
             G_p (compute_G_generic alpha_p 1 alpha_p 1 alpha_p 1 alpha_p 1)
             G_ps_coul (compute_G_generic alpha_p 1 alpha_p 1 alpha_s 0 alpha_s 0)
             G_ps_exch (compute_G_generic alpha_p 1 alpha_s 0 alpha_p 1 alpha_s 0)
             
             J_1s_1s (jnp.einsum (string "i,j,k,l,ijkl->") c_1s c_1s c_1s c_1s G_s)
             J_2s_2s (jnp.einsum (string "i,j,k,l,ijkl->") c_2s c_2s c_2s c_2s G_s)
             J_1s_2s (jnp.einsum (string "i,j,k,l,ijkl->") c_1s c_1s c_2s c_2s G_s)
             K_1s_2s (jnp.einsum (string "i,j,k,l,ijkl->") c_1s c_2s c_1s c_2s G_s)
             J_1s_3p (jnp.einsum (string "i,j,k,l,ijkl->") c_3p c_3p c_1s c_1s G_ps_coul)
             K_1s_3p (jnp.einsum (string "i,j,k,l,ijkl->") c_3p c_1s c_3p c_1s G_ps_exch)
             J_2s_3p (jnp.einsum (string "i,j,k,l,ijkl->") c_3p c_3p c_2s c_2s G_ps_coul)
             K_2s_3p (jnp.einsum (string "i,j,k,l,ijkl->") c_3p c_2s c_3p c_2s G_ps_exch)
             
             J_2p_2p (jnp.einsum (string "i,j,k,l,ijkl->") c_2p c_2p c_2p c_2p G_p)
             K_2p_2p J_2p_2p
             
             J_2p_1s (jnp.einsum (string "i,j,k,l,ijkl->") c_2p c_2p c_1s c_1s G_ps_coul)
             K_2p_1s (jnp.einsum (string "i,j,k,l,ijkl->") c_2p c_1s c_2p c_1s G_ps_exch)
             J_2p_2s (jnp.einsum (string "i,j,k,l,ijkl->") c_2p c_2p c_2s c_2s G_ps_coul)
             K_2p_2s (jnp.einsum (string "i,j,k,l,ijkl->") c_2p c_2s c_2p c_2s G_ps_exch)
             J_2p_3p (jnp.einsum (string "i,j,k,l,ijkl->") c_2p c_2p c_3p c_3p G_p)
             K_2p_3p (jnp.einsum (string "i,j,k,l,ijkl->") c_2p c_3p c_2p c_3p G_p)
             
             E_ee (+ J_1s_1s
                     J_2s_2s
                     (* 10.0 J_2p_2p)
                     (* -4.0 K_2p_2p)
                     (* 4.0 J_1s_2s)
                     (* -2.0 K_1s_2s)
                     (* 2.0 J_1s_3p)
                     (* -1.0 K_1s_3p)
                     (* 2.0 J_2s_3p)
                     (* -1.0 K_2s_3p)
                     (* 10.0 J_2p_1s)
                     (* -5.0 K_2p_1s)
                     (* 10.0 J_2p_2s)
                     (* -5.0 K_2p_2s)
                     (* 5.0 J_2p_3p)
                     (* -2.5 K_2p_3p))
             
             E_elec (+ (* 2.0 E_1s) (* 2.0 E_2s) (* 5.0 E_2p) E_3p E_ee)
             
             H_SO (jnp.array (list (list (- E_elec (* 0.5 zeta_2p)) (* 0.5 zeta_3p))
                                   (list (* 0.5 zeta_3p) (+ E_elec (* 0.5 zeta_2p)))))
             
             eigvals (jnp.linalg.eigh H_SO)
             
             ;; Euklidische Regularisierung für den Endzustand:
             ;; Stellt sicher, dass die Transformations-Spalten nahe an der Einheitsnorm bleiben.
             norm_penalty (* 1.0 (+ (** (- (jnp.dot (aref X_s (slice nil nil) 0) (aref X_s (slice nil nil) 0)) 1.0) 2)
                                    (** (- (jnp.dot (aref X_s (slice nil nil) 1) (aref X_s (slice nil nil) 1)) 1.0) 2)
                                    (** (- (jnp.dot (aref X_p (slice nil nil) 0) (aref X_p (slice nil nil) 0)) 1.0) 2)
                                    (** (- (jnp.dot (aref X_p (slice nil nil) 1) (aref X_p (slice nil nil) 1)) 1.0) 2))))
       (return (+ (aref (aref eigvals 0) 0) norm_penalty)))

     (def get_initial_guesses (nuclear_mass)
        (setf log_alpha_s (jnp.linspace (jnp.log 0.01) (jnp.log 500.0) 8)
              log_alpha_p (jnp.linspace (jnp.log 0.05) (jnp.log 100.0) 6)
              alpha_s (jnp.exp log_alpha_s)
              alpha_p (jnp.exp log_alpha_p)
              M_au (* nuclear_mass 1822.888)
              mu (/ M_au (+ 1.0 M_au)))

        (setf (ntuple _ _ S_s_LL S_s_SS V_s_LL V_s_SS) (compute_matrices alpha_s 0 -1 10.0 :mu mu)
              S_s (+ S_s_LL S_s_SS)
              H_s (+ V_s_LL V_s_SS (* (- 4.0 (* 2.0 mu)) (** C_LIGHT 2) S_s_SS))
              (ntuple S_s_val S_s_vec) (jnp.linalg.eigh S_s)
              S_s_inv_sqrt (jnp.dot S_s_vec (jnp.dot (jnp.diag (/ 1.0 (jnp.sqrt S_s_val))) (jnp.transpose S_s_vec)))
              H_s_std (jnp.dot S_s_inv_sqrt (jnp.dot H_s S_s_inv_sqrt))
              (ntuple _ eigvecs_s_std) (jnp.linalg.eigh H_s_std)
              c_eig_s (jnp.dot S_s_inv_sqrt eigvecs_s_std)
              x_1s_init (aref c_eig_s (slice nil nil) 0)
              x_2s_init (aref c_eig_s (slice nil nil) 1)
              x_5s_init (aref c_eig_s (slice nil nil) 4))

        (setf (ntuple _ _ S_p_LL S_p_SS_1 V_p_LL_1 V_p_SS_1) (compute_matrices alpha_p 1 1 10.0 :mu mu)
              (ntuple _ _ _ S_p_SS_2 V_p_LL_2 V_p_SS_2) (compute_matrices alpha_p 1 -2 10.0 :mu mu)
              S_p_locked_avg (+ S_p_LL (* (/ 1.0 3.0) S_p_SS_1) (* (/ 2.0 3.0) S_p_SS_2))
              H_p_locked_1 (+ V_p_LL_1 V_p_SS_1 (* (- 4.0 (* 2.0 mu)) (** C_LIGHT 2) S_p_SS_1))
              H_p_locked_2 (+ V_p_LL_2 V_p_SS_2 (* (- 4.0 (* 2.0 mu)) (** C_LIGHT 2) S_p_SS_2))
              H_p (+ (* (/ 1.0 3.0) H_p_locked_1) (* (/ 2.0 3.0) H_p_locked_2))
              (ntuple S_p_val S_p_vec) (jnp.linalg.eigh S_p_locked_avg)
              S_p_inv_sqrt (jnp.dot S_p_vec (jnp.dot (jnp.diag (/ 1.0 (jnp.sqrt S_p_val))) (jnp.transpose S_p_vec)))
              H_p_std (jnp.dot S_p_inv_sqrt (jnp.dot H_p S_p_inv_sqrt))
              (ntuple _ eigvecs_p_std) (jnp.linalg.eigh H_p_std)
              c_eig_p (jnp.dot S_p_inv_sqrt eigvecs_p_std)
              x_2p_init (aref c_eig_p (slice nil nil) 0)
              x_3p_init (aref c_eig_p (slice nil nil) 1))

        (return (tuple x_1s_init x_2s_init x_5s_init x_2p_init x_3p_init)))

     (def get_physical_coefficients (params nuclear_mass is_initial)
       (setf log_alpha_s (jnp.linspace (jnp.log 0.01) (jnp.log 500.0) 8)
             log_alpha_p (jnp.linspace (jnp.log 0.05) (jnp.log 100.0) 6)
             alpha_s (jnp.exp log_alpha_s)
             alpha_p (jnp.exp log_alpha_p)
             M_au (* nuclear_mass 1822.888)
             mu (/ M_au (+ 1.0 M_au)))

       (setf (ntuple _ _ S_s_LL S_s_SS _ _) (compute_matrices alpha_s 0 -1 10.0 :mu mu)
             S_s (+ S_s_LL S_s_SS)
             X_s (aref params (string "X_s"))
             
             M_s (jnp.dot (jnp.transpose X_s) (jnp.dot S_s X_s))
             (ntuple vals_s vecs_s) (jnp.linalg.eigh M_s)
             M_s_inv_sqrt (jnp.dot vecs_s (jnp.dot (jnp.diag (/ 1.0 (jnp.sqrt vals_s))) (jnp.transpose vecs_s)))
             C_s (jnp.dot X_s M_s_inv_sqrt)
             c_1s (aref C_s (slice nil nil) 0)
             c_2s (aref C_s (slice nil nil) 1))

       (setf (ntuple _ _ S_LL S_SS_1 _ _) (compute_matrices alpha_p 1 1 10.0 :mu mu)
             (ntuple _ _ _ S_SS_2 _ _) (compute_matrices alpha_p 1 -2 10.0 :mu mu)
             S_locked_avg (+ S_LL (* (/ 1.0 3.0) S_SS_1) (* (/ 2.0 3.0) S_SS_2)))

       (if is_initial
           (progn
             (setf x_2p (aref params (string "x_2p"))
                   c_2p (/ x_2p (jnp.sqrt (jnp.dot x_2p (jnp.dot S_locked_avg x_2p))))
                   c_5s (aref C_s (slice nil nil) 2))
             (return (tuple c_1s c_2s c_5s c_2p)))
           (progn
             (setf X_p (aref params (string "X_p"))
                   ;; Loewdin-Verfahren für den p-Kanal (2 Dimensionen: 2p, 3p) unter Verwendung der Locked-Mittelwert-Metrik:
              M_p (jnp.dot (jnp.transpose X_p) (jnp.dot S_locked_avg X_p))
                   (ntuple vals_p vecs_p) (jnp.linalg.eigh M_p)
                   M_p_inv_sqrt (jnp.dot vecs_p (jnp.dot (jnp.diag (/ 1.0 (jnp.sqrt vals_p))) (jnp.transpose vecs_p)))
                   C_p (jnp.dot X_p M_p_inv_sqrt)
                   c_2p (aref C_p (slice nil nil) 0)
                   c_3p (aref C_p (slice nil nil) 1))
             (return (tuple c_1s c_2s c_2p c_3p)))))

     (def nominal_frequency_wrapper (nuclear_mass)
       (setf (ntuple x_1s_init x_2s_init x_5s_init x_2p_init x_3p_init) (get_initial_guesses nuclear_mass)
             
             X_s_init_initial (jnp.stack (list x_1s_init x_2s_init x_5s_init) :axis 1)
             init_params_initial (dict* X_s X_s_init_initial
                                        x_2p x_2p_init)
                                        
             X_s_init_final (jnp.stack (list x_1s_init x_2s_init) :axis 1)
             X_p_init_final (jnp.stack (list x_2p_init x_3p_init) :axis 1)
             init_params_final (dict* X_s X_s_init_final
                                      X_p X_p_init_final)
                                       
             solver_initial (jaxopt.LBFGS :fun initial_state_energy :maxiter 800 :tol 1e-12 :implicit_diff True)
             res_initial (solver_initial.run init_params_initial nuclear_mass)
             E_initial (initial_state_energy res_initial.params nuclear_mass)
             
             solver_final (jaxopt.LBFGS :fun final_state_energy :maxiter 800 :tol 1e-12 :implicit_diff True)
             res_final (solver_final.run init_params_final nuclear_mass)
             E_final (final_state_energy res_final.params nuclear_mass)
             
             delta_E (- E_initial E_final)
             HARTREE_TO_THZ 6.5796839e6
             nu_0 (* delta_E HARTREE_TO_THZ))
       (return nu_0))))

;; =========================================================================
;; 2. Definiere den S-Expression Code für test_solver.py
;; =========================================================================
(defparameter *test-code*
  `(progn
     (import pytest
             jax
             (jnp jax.numpy)
             (jsp jax.scipy.special)
             jaxopt)
     (jax.config.update (string "jax_enable_x64") True)
     (import-from solver compute_matrices compute_G_generic nominal_frequency_wrapper C_LIGHT safe_I_k get_initial_guesses get_physical_coefficients)

     (def test_overlap_normalization ()
       (setf alpha (jnp.array (list 1.0))
             (ntuple H S _ _ _ _) (compute_matrices alpha 0 -1 1.0)
             overlap (aref S 0 0))
       (assert (jnp.allclose overlap 1.0 :atol 1e-6)))

     (def test_hydrogen_atom ()
       (def hydrogen_energy (params)
         (setf log_alpha (aref params (string "log_alpha"))
               x (aref params (string "x"))
               alpha (jnp.exp log_alpha)
               (ntuple _ _ S_LL S_SS V_LL V_SS) (compute_matrices alpha 0 -1 1.0)
               S_locked (+ S_LL S_SS)
               c (/ x (jnp.sqrt (jnp.dot x (jnp.dot S_locked x))))
               H_locked (+ V_LL V_SS (* 2.0 (** C_LIGHT 2) S_SS)))
         (return (/ (jnp.dot c (jnp.dot H_locked c)) (jnp.dot c (jnp.dot S_locked c)))))
       
       (setf init_params (dict* log_alpha (jnp.linspace (jnp.log 0.1) (jnp.log 10.0) 6)
                                x (jnp.ones 6))
             solver (jaxopt.LBFGS :fun hydrogen_energy :maxiter 100 :tol 1e-6)
             res (solver.run init_params)
             E_opt (hydrogen_energy res.params))
       (assert (< (abs (+ E_opt 0.5)) 1e-3)))

     (def test_coulomb_symmetries_and_decay ()
       (setf alpha_a 0.5
             alpha_b 1.2
             alpha_c 0.8
             alpha_d 1.5)
             
       (def primitive_coulomb_integral_R (alpha_a alpha_b alpha_c alpha_d R)
         (setf p (+ alpha_a alpha_b)
               q (+ alpha_c alpha_d)
               gamma (/ (* p q) (+ p q))
               val_R (* (/ (** jnp.pi 3) (jnp.power (* p q) 1.5))
                        (/ (jax.scipy.special.erf (* (jnp.sqrt gamma) R)) (jnp.maximum R 1e-15)))
               val_0 (/ (* 2.0 (jnp.power jnp.pi 2.5))
                        (* p q (jnp.sqrt (+ p q)))))
         (return (jnp.where (> R 1e-10) val_R val_0)))
       
       (setf R 2.0
             val1 (primitive_coulomb_integral_R alpha_a alpha_b alpha_c alpha_d R)
             val2 (primitive_coulomb_integral_R alpha_b alpha_a alpha_c alpha_d R)
             val3 (primitive_coulomb_integral_R alpha_a alpha_b alpha_d alpha_c R)
             val4 (primitive_coulomb_integral_R alpha_c alpha_d alpha_a alpha_b R))
       (assert (jnp.allclose val1 val2))
       (assert (jnp.allclose val1 val3))
       (assert (jnp.allclose val1 val4))
       
       (setf R1 10.0
             R2 20.0
             val_R1 (primitive_coulomb_integral_R alpha_a alpha_b alpha_c alpha_d R1)
             val_R2 (primitive_coulomb_integral_R alpha_a alpha_b alpha_c alpha_d R2))
       (assert (jnp.allclose (* R1 val_R1) (* R2 val_R2) :rtol 1e-3)))

     (def test_kinetic_balance_enforcer ()
       (setf exponents (list 0.5 1.0 2.0)
             (ntuple H S _ _ _ _) (compute_matrices exponents 0 -1 0.0)
             (ntuple S_val S_vec) (jnp.linalg.eigh S)
             S_inv_sqrt (jnp.dot S_vec (jnp.dot (jnp.diag (/ 1.0 (jnp.sqrt S_val))) (jnp.transpose S_vec)))
             H_std (jnp.dot S_inv_sqrt (jnp.dot H S_inv_sqrt))
             (ntuple eigvals_sorted _) (jnp.linalg.eigh H_std)
             c C_LIGHT
             pos_e (aref eigvals_sorted (slice 3 nil))
             neg_e (aref eigvals_sorted (slice nil 3))
             gap (- (aref pos_e 0) (aref neg_e -1)))
       (assert (> gap (* 1.9 (** c 2)))))

     (def test_isotope_shift_cross_check ()
       (setf grad_fn (jax.grad nominal_frequency_wrapper)
             grad_val (grad_fn 21.0)
             fd_slope (/ (- (nominal_frequency_wrapper 22.0) (nominal_frequency_wrapper 20.0)) 2.0))
       (assert (jnp.allclose grad_val fd_slope :rtol 5e-3 :atol 5e-3)))))

;; =========================================================================
;; 3. Definiere den S-Expression Code für plot.py
;; =========================================================================
(defparameter *plot-code*
  `(progn
     (import matplotlib
             (plt matplotlib.pyplot)
             jax
             (jnp jax.numpy)
             jaxopt)
     (jax.config.update (string "jax_enable_x64") True)
     (import-from solver initial_state_energy final_state_energy compute_matrices safe_I_k C_LIGHT get_initial_guesses get_physical_coefficients)

     (def run_optimization_history (fun init_params nuclear_mass max_steps)
       (setf solver (jaxopt.LBFGS :fun fun :maxiter 1 :tol 1e-12)
             state (solver.init_state init_params nuclear_mass)
             params init_params
             history (list))
       (for (i (range max_steps))
            (setf (ntuple params state) (solver.update params state nuclear_mass))
            (history.append state.value))
       (return (tuple params history)))

     (def generate_radial_wavefunctions (c l kappa is_s)
       (if is_s
           (setf log_alpha (jnp.linspace (jnp.log 0.01) (jnp.log 500.0) 8))
           (setf log_alpha (jnp.linspace (jnp.log 0.05) (jnp.log 100.0) 6)))
       (setf alpha (jnp.exp log_alpha)
             Np (len alpha)
             C_coeffs (list))
       (for (i (range Np))
            (setf val ((jax.vmap (lambda (a) (safe_I_k (+ (* 2 l) 2) (* 2.0 a)))) (jnp.array (list (aref alpha i))))
                  Ci (/ 1.0 (jnp.sqrt (aref val 0))))
            (C_coeffs.append Ci))
            
       (setf r (jnp.linspace 0.01 5.0 500)
             P (jnp.zeros_like r)
             Q (jnp.zeros_like r)
             A (+ l 1 kappa))
       (for (i (range Np))
            (setf g_i (* (aref C_coeffs i) (jnp.power r (+ l 1)) (jnp.exp (* -1.0 (aref alpha i) (** r 2))))
                  B_i (* -2.0 (aref alpha i))
                  f_i (* (/ (aref C_coeffs i) (* 2.0 C_LIGHT))
                         (+ (* A (jnp.power r l)) (* B_i (jnp.power r (+ l 2))))
                         (jnp.exp (* -1.0 (aref alpha i) (** r 2))))
                  P (+ P (* (aref c i) g_i))
                  Q (+ Q (* (aref c i) f_i))))
       (return (tuple r P Q)))

     (def main ()
       (setf (ntuple x_1s_init x_2s_init x_5s_init x_2p_init x_3p_init) (get_initial_guesses 20.18)
             
             X_s_init_initial (jnp.stack (list x_1s_init x_2s_init x_5s_init) :axis 1)
             init_params_initial (dict* X_s X_s_init_initial
                                        x_2p x_2p_init)
                                        
             X_s_init_final (jnp.stack (list x_1s_init x_2s_init) :axis 1)
             X_p_init_final (jnp.stack (list x_2p_init x_3p_init) :axis 1)
             init_params_final (dict* X_s X_s_init_final
                                      X_p X_p_init_final))
       
       (setf (ntuple params_initial hist_initial) (run_optimization_history initial_state_energy init_params_initial 20.18 800)
             (ntuple params_final hist_final) (run_optimization_history final_state_energy init_params_final 20.18 800)
             
             (ntuple c_1s_init c_2s_init c_5s_init c_2p_init_state) (get_physical_coefficients params_initial 20.18 True)
             (ntuple c_1s_final c_2s_final c_2p_final_state c_3p_final) (get_physical_coefficients params_final 20.18 False))

       (plt.figure :figsize (tuple 12 5))
       (plt.subplot 1 2 1)
       (plt.plot hist_initial :label (string "Initial State (5s)"))
       (plt.plot hist_final :label (string "Final State (3p)"))
       (plt.xlabel (string "Iteration"))
       (plt.ylabel (string "Energy (Hartree)"))
       (plt.title (string "Optimization Convergence Curve"))
       (plt.legend)
       (plt.grid True)

       (plt.subplot 1 2 2)
       (setf (ntuple r_1s P_1s Q_1s) (generate_radial_wavefunctions c_1s_init 0 -1 True)
             (ntuple r_2s P_2s Q_2s) (generate_radial_wavefunctions c_2s_init 0 -1 True)
             (ntuple r_5s P_5s Q_5s) (generate_radial_wavefunctions c_5s_init 0 -1 True)
             (ntuple r_2p P_2p Q_2p) (generate_radial_wavefunctions c_2p_final_state 1 -2 False)
             (ntuple r_3p P_3p Q_3p) (generate_radial_wavefunctions c_3p_final 1 -2 False))
       (plt.plot r_1s P_1s :label (string "1s Large P(r)") :linestyle (string "-"))
       (plt.plot r_2s P_2s :label (string "2s Large P(r)") :linestyle (string "-"))
       (plt.plot r_5s P_5s :label (string "5s Large P(r)") :linestyle (string "-"))
       (plt.plot r_2p P_2p :label (string "2p Large P(r)") :linestyle (string "-"))
       (plt.plot r_3p P_3p :label (string "3p Large P(r)") :linestyle (string "-"))
       (plt.xlabel (string "Radius r (a.u.)"))
       (plt.ylabel (string "Wavefunction Amplitude"))
       (plt.title (string "Radial Wavefunctions"))
       (plt.legend)
       (plt.grid True)

       (plt.tight_layout)
       (plt.savefig (string "/workspace/src/cl-cl-generator/example/03_py_meta/example/01_neon/source01/neon_transition_plots.png"))
       (plt.close))

     (if (== __name__ (string "__main__"))
         (main))))

;; =========================================================================
;; 4. Transpiliere und schreibe Dateien nach source01/
;; =========================================================================
(write-source "solver" *solver-code* *output-dir*)
(write-source "test_solver" *test-code* *output-dir*)
(write-source "plot" *plot-code* *output-dir*)

(format t "Successfully generated Neon Transition Solver Python files!~%")
