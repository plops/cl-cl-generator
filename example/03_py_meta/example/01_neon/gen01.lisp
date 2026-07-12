(eval-when (:compile-toplevel :execute :load-toplevel)
  (push "/workspace/src/cl-cl-generator/example/03_py_meta/" asdf:*central-registry*)
  (ql:quickload :cl-py-generator-example))

(defpackage :cl-py-generator/example-neon
  (:use :cl :cl-py-generator))

(in-package :cl-py-generator/example-neon)

(defparameter *output-dir* "/workspace/src/cl-cl-generator/example/03_py_meta/example/01_neon/source01/")

;; =========================================================================
;; 1. Define S-Expression Code for solver.py
;; =========================================================================
(defparameter *solver-code*
  `(progn
     (import jax
             (jnp jax.numpy)
             (jsp jax.scipy.special)
             jaxopt)

     (setf C_LIGHT 137.035999)

     (def safe_I_k (k a)
       (setf k_safe (jnp.where (> k -1.0) k 1.0)
             val (* 0.5
                    (jnp.power a (* -0.5 (+ k_safe 1.0)))
                    (jnp.exp (jsp.gammaln (* 0.5 (+ k_safe 1.0))))))
       (return (jnp.where (> k -1.0) val 0.0)))

     (def compute_matrices (exponents l kappa Z &key (c C_LIGHT) (mu 1.0))
       (setf N (len exponents)
             alpha (jnp.array exponents)
             I_norm ((jax.vmap (lambda (a) (safe_I_k (+ (* 2 l) 2) (* 2.0 a)))) alpha)
             C (/ 1.0 (jnp.sqrt I_norm))
             alpha_grid (+ (aref alpha (slice nil nil) None)
                           (aref alpha None (slice nil nil)))
             I_grid ((jax.vmap (jax.vmap (lambda (a) (safe_I_k (+ (* 2 l) 2) a)))) alpha_grid)
             S_LL (* (aref C (slice nil nil) None)
                     (aref C None (slice nil nil))
                     I_grid)
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
             I_2l1 ((jax.vmap (jax.vmap (lambda (a) (safe_I_k (+ (* 2 l) 1) a)))) alpha_grid)
             V_LL (* -1.0 Z
                     (aref C (slice nil nil) None)
                     (aref C None (slice nil nil))
                     I_2l1)
             I_2l_minus_1 ((jax.vmap (jax.vmap (lambda (a) (safe_I_k (- (* 2 l) 1) a)))) alpha_grid)
             I_2l3 ((jax.vmap (jax.vmap (lambda (a) (safe_I_k (+ (* 2 l) 3) a)))) alpha_grid)
             term_v1 (* A A I_2l_minus_1)
             term_v2 (* A (+ (aref B (slice nil nil) None) (aref B None (slice nil nil))) I_2l1)
             term_v3 (* (aref B (slice nil nil) None) (aref B None (slice nil nil)) I_2l3)
             V_SS (* -1.0 Z
                     (/ (* (aref C (slice nil nil) None) (aref C None (slice nil nil)))
                        (* 4.0 (** c 2)))
                     (+ term_v1 term_v2 term_v3))
             H (jnp.block (list (list (+ V_LL (* mu (** c 2) S_LL)) (* 2.0 (** c 2) S_SS))
                                (list (* 2.0 (** c 2) S_SS) (- V_SS (* mu (** c 2) S_SS)))))
             S_overlap (jnp.block (list (list S_LL (jnp.zeros (tuple N N)))
                                        (list (jnp.zeros (tuple N N)) S_SS))))
       (return (tuple H S_overlap S_LL S_SS V_LL V_SS)))

     (def compute_G_generic (alpha_a l_a alpha_b l_b alpha_c l_c alpha_d l_d)
       (setf C_a (/ 1.0 (jnp.sqrt ((jax.vmap (lambda (a) (safe_I_k (+ (* 2 l_a) 2) (* 2.0 a)))) alpha_a)))
             C_b (/ 1.0 (jnp.sqrt ((jax.vmap (lambda (a) (safe_I_k (+ (* 2 l_b) 2) (* 2.0 a)))) alpha_b)))
             C_c (/ 1.0 (jnp.sqrt ((jax.vmap (lambda (a) (safe_I_k (+ (* 2 l_c) 2) (* 2.0 a)))) alpha_c)))
             C_d (/ 1.0 (jnp.sqrt ((jax.vmap (lambda (a) (safe_I_k (+ (* 2 l_d) 2) (* 2.0 a)))) alpha_d)))
             a_grid (aref alpha_a (slice nil nil) None None None)
             b_grid (aref alpha_b None (slice nil nil) None None)
             c_grid (aref alpha_c None None (slice nil nil) None)
             d_grid (aref alpha_d None None None (slice nil nil))
             p (+ a_grid b_grid)
             q (+ c_grid d_grid)
             prim (/ (* 2.0 (** jnp.pi 2.5))
                     (* p q (jnp.sqrt (+ p q))))
             G (* (aref C_a (slice nil nil) None None None)
                  (aref C_b None (slice nil nil) None None)
                  (aref C_c None None (slice nil nil) None)
                  (aref C_d None None None (slice nil nil))
                  (/ 1.0 (* 16.0 (** jnp.pi 2)))
                  prim))
       (return G))

     (def initial_state_energy (params nuclear_mass)
       (setf log_alpha_s (jnp.linspace (jnp.log 0.1) (jnp.log 100.0) 4)
             log_alpha_p (jnp.linspace (jnp.log 0.1) (jnp.log 50.0) 4)
             x_2p (aref params (string "x_2p"))
             x_5s (aref params (string "x_5s"))
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

       (setf (ntuple _ _ S_5s_LL S_5s_SS V_5s_LL V_5s_SS) (compute_matrices alpha_s 0 -1 10.0 :mu mu)
             Ns (len alpha_s)
             S_5s_locked (+ S_5s_LL S_5s_SS)
             c_5s (/ x_5s (jnp.sqrt (jnp.dot x_5s (jnp.dot S_5s_locked x_5s))))
             H_5s_locked (+ V_5s_LL V_5s_SS (* (- 4.0 (* 2.0 mu)) (** C_LIGHT 2) S_5s_SS))
             E_5s (/ (jnp.dot c_5s (jnp.dot H_5s_locked c_5s)) (jnp.dot c_5s (jnp.dot S_5s_locked c_5s))))

       (setf G_2p_2p (compute_G_generic alpha_p 1 alpha_p 1 alpha_p 1 alpha_p 1)
             G_2p_5s_coul (compute_G_generic alpha_p 1 alpha_p 1 alpha_s 0 alpha_s 0)
             G_2p_5s_exch (compute_G_generic alpha_p 1 alpha_s 0 alpha_p 1 alpha_s 0)
             J_2p_2p (jnp.einsum (string "i,j,k,l,ijkl->") c_2p c_2p c_2p c_2p G_2p_2p)
             K_2p_2p J_2p_2p
             J_2p_5s (jnp.einsum (string "i,j,k,l,ijkl->") c_2p c_2p c_5s c_5s G_2p_5s_coul)
             K_2p_5s (jnp.einsum (string "i,j,k,l,ijkl->") c_2p c_5s c_2p c_5s G_2p_5s_exch)
             E_elec (+ (* 5.0 E_2p) E_5s (* 10.0 J_2p_2p) (* -4.0 K_2p_2p) (* 5.0 J_2p_5s) (* -2.5 K_2p_5s))
             H_SO (jnp.array (list (list (- E_elec (* 0.5 zeta_2p)) (* (/ 1.0 (jnp.sqrt 2.0)) zeta_2p))
                                   (list (* (/ 1.0 (jnp.sqrt 2.0)) zeta_2p) E_elec)))
             eigvals (jnp.linalg.eigh H_SO))
       (return (aref (aref eigvals 0) 0)))

     (def final_state_energy (params nuclear_mass)
       (setf log_alpha_s (jnp.linspace (jnp.log 0.1) (jnp.log 100.0) 4)
             log_alpha_p (jnp.linspace (jnp.log 0.1) (jnp.log 50.0) 4)
             x_2p (aref params (string "x_2p"))
             x_3p (aref params (string "x_3p"))
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

       (setf (ntuple _ _ S_3p_LL S_3p_SS_1 V_3p_LL_1 V_3p_SS_1) (compute_matrices alpha_p 1 1 10.0 :mu mu)
             (ntuple _ _ _ S_3p_SS_2 V_3p_LL_2 V_3p_SS_2) (compute_matrices alpha_p 1 -2 10.0 :mu mu)
             S_3p_locked_avg (+ S_3p_LL (* (/ 1.0 3.0) S_3p_SS_1) (* (/ 2.0 3.0) S_3p_SS_2))
             c_3p (/ x_3p (jnp.sqrt (jnp.dot x_3p (jnp.dot S_3p_locked_avg x_3p))))

             H_3p_locked_1 (+ V_3p_LL_1 V_3p_SS_1 (* (- 4.0 (* 2.0 mu)) (** C_LIGHT 2) S_3p_SS_1))
             S_3p_locked_1 (+ S_3p_LL S_3p_SS_1)
             E_3p_1 (/ (jnp.dot c_3p (jnp.dot H_3p_locked_1 c_3p)) (jnp.dot c_3p (jnp.dot S_3p_locked_1 c_3p)))
             
             H_3p_locked_2 (+ V_3p_LL_2 V_3p_SS_2 (* (- 4.0 (* 2.0 mu)) (** C_LIGHT 2) S_3p_SS_2))
             S_3p_locked_2 (+ S_3p_LL S_3p_SS_2)
             E_3p_2 (/ (jnp.dot c_3p (jnp.dot H_3p_locked_2 c_3p)) (jnp.dot c_3p (jnp.dot S_3p_locked_2 c_3p)))
             
             E_3p (+ (* (/ 1.0 3.0) E_3p_1) (* (/ 2.0 3.0) E_3p_2))
             zeta_3p (* (/ 2.0 3.0) (- E_3p_2 E_3p_1)))

       (setf G_2p_2p (compute_G_generic alpha_p 1 alpha_p 1 alpha_p 1 alpha_p 1)
             G_2p_3p_coul G_2p_2p
             J_2p_2p (jnp.einsum (string "i,j,k,l,ijkl->") c_2p c_2p c_2p c_2p G_2p_2p)
             K_2p_2p J_2p_2p
             J_2p_3p (jnp.einsum (string "i,j,k,l,ijkl->") c_2p c_2p c_3p c_3p G_2p_3p_coul)
             K_2p_3p (jnp.einsum (string "i,j,k,l,ijkl->") c_2p c_3p c_2p c_3p G_2p_2p)
             E_elec (+ (* 5.0 E_2p) E_3p (* 10.0 J_2p_2p) (* -4.0 K_2p_2p) (* 5.0 J_2p_3p) (* -2.5 K_2p_3p))
             H_SO (jnp.array (list (list (- E_elec (* 0.5 zeta_2p)) (* 0.5 zeta_3p))
                                   (list (* 0.5 zeta_3p) (+ E_elec (* 0.5 zeta_2p)))))
             eigvals (jnp.linalg.eigh H_SO))
       (return (aref (aref eigvals 0) 0)))

     (def nominal_frequency_wrapper (nuclear_mass)
       (setf init_params_initial (dict* x_2p (jnp.ones 4)
                                        x_5s (jnp.ones 4))
             init_params_final (dict* x_2p (jnp.ones 4)
                                      x_3p (jnp.ones 4))
             solver_initial (jaxopt.LBFGS :fun initial_state_energy :maxiter 150 :tol 1e-10 :implicit_diff True)
             res_initial (solver_initial.run init_params_initial nuclear_mass)
             E_initial (initial_state_energy res_initial.params nuclear_mass)
             
             solver_final (jaxopt.LBFGS :fun final_state_energy :maxiter 150 :tol 1e-10 :implicit_diff True)
             res_final (solver_final.run init_params_final nuclear_mass)
             E_final (final_state_energy res_final.params nuclear_mass)
             
             delta_E (- E_initial E_final)
             HARTREE_TO_THZ 1.0
             nu_0 (* delta_E HARTREE_TO_THZ))
       (return nu_0))))

;; =========================================================================
;; 2. Define S-Expression Code for test_solver.py
;; =========================================================================
(defparameter *test-code*
  `(progn
     (import pytest
             jax
             (jnp jax.numpy)
             (jsp jax.scipy.special)
             jaxopt)
     (import-from solver compute_matrices compute_G_generic nominal_frequency_wrapper C_LIGHT safe_I_k)

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
       (assert (< (abs (- grad_val fd_slope)) 1e-5)))))

;; =========================================================================
;; 3. Define S-Expression Code for plot.py
;; =========================================================================
(defparameter *plot-code*
  `(progn
     (import matplotlib
             (plt matplotlib.pyplot)
             jax
             (jnp jax.numpy)
             jaxopt)
     (import-from solver initial_state_energy final_state_energy compute_matrices safe_I_k C_LIGHT)

     (def run_optimization_history (fun init_params nuclear_mass max_steps)
       (setf solver (jaxopt.LBFGS :fun fun :maxiter 1 :tol 1e-6)
             state (solver.init_state init_params nuclear_mass)
             params init_params
             history (list))
       (for (i (range max_steps))
            (setf (ntuple params state) (solver.update params state nuclear_mass))
            (history.append state.value))
       (return (tuple params history)))

     (def generate_radial_wavefunctions (params l kappa name)
       (setf limit 50.0)
       (if (in (string "s") name)
           (setf limit 100.0))
       (setf log_alpha (jnp.linspace (jnp.log 0.1) (jnp.log limit) 4)
             alpha (jnp.exp log_alpha)
             x (aref params (+ (string "x_") name))
             (ntuple _ _ S_LL S_SS _ _) (compute_matrices alpha l kappa 10.0)
             S_locked (+ S_LL S_SS)
             c (/ x (jnp.sqrt (jnp.dot x (jnp.dot S_locked x))))
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
       (setf init_params_initial (dict* x_2p (jnp.ones 4)
                                        x_5s (jnp.ones 4))
             init_params_final (dict* x_2p (jnp.ones 4)
                                      x_3p (jnp.ones 4)))
       
       (setf (ntuple params_initial hist_initial) (run_optimization_history initial_state_energy init_params_initial 20.18 50)
             (ntuple params_final hist_final) (run_optimization_history final_state_energy init_params_final 20.18 50))

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
       (setf (ntuple r_5s P_5s Q_5s) (generate_radial_wavefunctions params_initial 0 -1 (string "5s"))
             (ntuple r_3p P_3p Q_3p) (generate_radial_wavefunctions params_final 1 -2 (string "3p")))
       (plt.plot r_5s P_5s :label (string "5s Large P(r)") :linestyle (string "-"))
       (plt.plot r_5s Q_5s :label (string "5s Small Q(r)") :linestyle (string "--"))
       (plt.plot r_3p P_3p :label (string "3p Large P(r)") :linestyle (string "-"))
       (plt.plot r_3p Q_3p :label (string "3p Small Q(r)") :linestyle (string "--"))
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
;; 4. Transpile and Write Files to source01/
;; =========================================================================
(write-source "solver" *solver-code* *output-dir*)
(write-source "test_solver" *test-code* *output-dir*)
(write-source "plot" *plot-code* *output-dir*)

(format t "Successfully generated Neon Transition Solver Python files!~%")
