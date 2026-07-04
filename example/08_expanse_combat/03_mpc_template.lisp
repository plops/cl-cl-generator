;;;; 03_mpc_template.lisp — 2D HPIPM MPC solver configuration template for example 08

(in-package :cl-cl-generator/example-expanse-gen)

(defparameter *mpc-template-code*
  `(toplevel
     ,@(make-header-comments)
     (defpackage :expanse-combat/mpc
       (:use :cl :hpipm)
       (:export #:init-mpc-solver
                #:solve-mpc-control))
     (in-package :expanse-combat/mpc)

     (defun init-mpc-solver (horizon ad bd q-mat r-mat u-limit &key soft-specs)
       "Create and initialize a 2D MPC solver (nx=4, nu=2) with cost, dynamics, and bounds."
       (let* ((nx 4)
              (nu 2)
              (nbu 2)
              (nbx 0)
              ;; We allocate 4 general constraints per stage: 
              ;; index 0,1 for railgun lines, index 2,3 for torpedo/ship safety circles
              (ng 4)
              (solver (make-mpc-solver :horizon horizon
                                       :nx nx
                                       :nu nu
                                       :nbu nbu
                                       :nbx nbx
                                       :ng ng
                                       :precision :double
                                       :soft-constraints soft-specs))
              (q-term (make-array '(4 4) :element-type 'double-float :initial-element 0.0d0)))
         ;; Terminal cost is 10x the state running cost to ensure terminal convergence
         (dotimes (i 4)
           (dotimes (j 4)
             (setf (aref q-term i j) (* 10.0d0 (aref q-mat i j)))))
         
         ;; Setup solver parameters
         (set-solver-dynamics solver ad bd)
         (set-solver-cost solver q-mat r-mat :terminal-q q-term)
         (set-control-bounds-all-stages solver '(0 1)
                                         (list (- u-limit) (- u-limit))
                                         (list u-limit u-limit))
         solver))

     (defun solve-mpc-control (solver ship-pos target-pos obstacles u-limit current-state)
       "Solve the MPC problem to find the optimal next step inputs. Update dynamic general constraints first."
       (let* ((horizon (mpc-solver-horizon solver))
              (c-mat (make-array '(4 4) :element-type 'double-float :initial-element 0.0d0))
              (d-mat (make-array '(4 2) :element-type 'double-float :initial-element 0.0d0))
              ;; Upper and lower bounds for general constraints
              (lg (make-list 4 :initial-element -100000.0d0))
              (ug (make-list 4 :initial-element 100000.0d0))
              (ship-x (aref current-state 0))
              (ship-y (aref current-state 1)))
         
         ;; Reset control bounds to dynamic limits
         (set-control-bounds-all-stages solver '(0 1)
                                         (list (- u-limit) (- u-limit))
                                         (list u-limit u-limit))

         ;; Set dynamic constraints at each stage of the horizon
         (dotimes (k horizon)
           (let ((c-k (make-array '(4 4) :element-type 'double-float :initial-element 0.0d0))
                 (lg-k (make-array 4 :element-type 'double-float :initial-element -100000.0d0))
                 (ug-k (make-array 4 :element-type 'double-float :initial-element 100000.0d0)))
             
             ;; Populate constraints from obstacles
             (let ((idx 0))
               (dolist (obs obstacles)
                 (when (< idx 2)
                   (let* ((ox (first obs))
                          (oy (second obs))
                          ;; Direction vector from obstacle to current ship position
                          (dx (- ship-x ox))
                          (dy (- ship-y oy))
                          (dist (sqrt (+ (* dx dx) (* dy dy))))
                          (r (third obs))) ;; Avoidance radius
                     (if (> dist 0.01d0)
                         (let ((nx (/ dx dist))
                               (ny (/ dy dist)))
                           ;; Linearized half-space constraint: nx*x + ny*y >= nx*ox + ny*oy + r
                           (setf (aref c-k (* idx 2) 0) nx
                                 (aref c-k (* idx 2) 1) ny)
                           (setf (aref lg-k (* idx 2)) (+ (* nx ox) (* ny oy) r)))
                         ;; Default case if directly overlapping
                         (setf (aref lg-k (* idx 2)) -100000.0d0))))
                 (incf idx)))
             (set-general-constraints solver k c-k d-mat (coerce lg-k 'list) (coerce ug-k 'list))))

         ;; Set terminal constraints for stage N
         (let ((c-n (make-array '(4 4) :element-type 'double-float :initial-element 0.0d0))
               (lg-n (make-array 4 :element-type 'double-float :initial-element -100000.0d0))
               (ug-n (make-array 4 :element-type 'double-float :initial-element 100000.0d0)))
           (set-general-constraints solver horizon c-n nil (coerce lg-n 'list) (coerce ug-n 'list)))

         ;; Solve the optimal control QP
         (sb-int:with-float-traps-masked (:divide-by-zero :invalid :overflow :underflow :inexact)
           (multiple-value-bind (u-traj x-pred status iterations) (solve-mpc solver current-state)
             (values u-traj x-pred status iterations)))))
     ))
