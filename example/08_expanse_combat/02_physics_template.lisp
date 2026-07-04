;;;; 02_physics_template.lisp — Relative orbit & weapons physics template for example 08

(in-package :cl-cl-generator/example-expanse-gen)

(defparameter *physics-template-code*
  `(toplevel
     ,@(make-header-comments)
     (defpackage :expanse-combat/physics
       (:use :cl)
       (:export #:compute-cw-matrices-2d
                #:propagate-state-2d
                #:mat-vec-mult-2d
                #:update-torpedoes
                #:update-slugs
                #:check-collision
                #:update-pdc-defense))
     (in-package :expanse-combat/physics)

     ;; --- Matrix Vector Multiplication Helper ---
     (defun mat-vec-mult-2d (a x)
       (let* ((n (array-dimension a 0))
              (m (array-dimension a 1))
              (y (make-array n :element-type 'double-float :initial-element 0.0d0)))
         (dotimes (i n)
           (let ((sum 0.0d0))
             (dotimes (j m)
               (incf sum (* (aref a i j) (coerce (elt x j) 'double-float))))
             (setf (aref y i) sum)))
         y))

     ;; --- State Propagation Helper ---
     (defun propagate-state-2d (ad bd x u)
       (let ((x-next (mat-vec-mult-2d ad x))
             (bu (mat-vec-mult-2d bd u)))
         (dotimes (i (length x-next))
           (incf (aref x-next i) (aref bu i)))
         x-next))

     ;; --- Analytical Clohessy-Wiltshire (CW) 2D Discretization ---
     (defun compute-cw-matrices-2d (n dt)
       (let* ((nt (* n dt))
              (c (cos nt))
              (s (sin nt))
              (ad (make-array '(4 4) :element-type 'double-float :initial-element 0.0d0))
              (bd (make-array '(4 2) :element-type 'double-float :initial-element 0.0d0)))
         (declare (type double-float n dt nt c s))
         ;; Ad Matrix: radial/along-track position & velocity mapping
         (setf (aref ad 0 0) (- 4.0d0 (* 3.0d0 c)))
         (setf (aref ad 0 2) (/ s n))
         (setf (aref ad 0 3) (/ (* 2.0d0 (- 1.0d0 c)) n))
         
         (setf (aref ad 1 0) (* 6.0d0 (- s nt)))
         (setf (aref ad 1 1) 1.0d0)
         (setf (aref ad 1 2) (/ (* -2.0d0 (- 1.0d0 c)) n))
         (setf (aref ad 1 3) (/ (- (* 4.0d0 s) (* 3.0d0 nt)) n))
         
         (setf (aref ad 2 0) (* 3.0d0 n s))
         (setf (aref ad 2 2) c)
         (setf (aref ad 2 3) (* 2.0d0 s))
         
         (setf (aref ad 3 0) (* -6.0d0 n (- 1.0d0 c)))
         (setf (aref ad 3 2) (* -2.0d0 s))
         (setf (aref ad 3 3) (- (* 4.0d0 c) 3.0d0))
         
         ;; Bd Matrix: mapping inputs (thrust ux, uy) to state rates
         (let ((n2 (* n n)))
           (setf (aref bd 0 0) (/ (- 1.0d0 c) n2))
           (setf (aref bd 0 1) (/ (* 2.0d0 (- nt s)) n2))
           
           (setf (aref bd 1 0) (/ (* -2.0d0 (- nt s)) n2))
           (setf (aref bd 1 1) (/ (- (* 4.0d0 (- 1.0d0 c)) (* 1.5d0 nt nt)) n2))
           
           (setf (aref bd 2 0) (/ s n))
           (setf (aref bd 2 1) (/ (* 2.0d0 (- 1.0d0 c)) n))
           
           (setf (aref bd 3 0) (/ (* -2.0d0 (- 1.0d0 c)) n))
           (setf (aref bd 3 1) (/ (- (* 4.0d0 s) (* 3.0d0 nt)) n)))
         (values ad bd)))

     ;; --- Steerable Torpedo Propagation ---
     (defun update-torpedoes (torpedoes target-pos ad bd dt)
       "Propagates torpedoes using proportional navigation or orbit drift."
       (loop for torp in torpedoes
             collect
             (let* ((tx (first torp)) (ty (second torp))
                    (tvx (third torp)) (tvy (fourth torp))
                    (fuel (fifth torp)))
               (if (> fuel 0.0)
                   (let* ((dx (- (aref target-pos 0) tx))
                          (dy (- (aref target-pos 1) ty))
                          (dist (sqrt (+ (* dx dx) (* dy dy))))
                          ;; Proportional navigation thrust acceleration
                          (acc 25.0d0)
                          (ux (if (> dist 0.1) (* acc (/ dx dist)) 0.0d0))
                          (uy (if (> dist 0.1) (* acc (/ dy dist)) 0.0d0))
                          (next-state (propagate-state-2d ad bd (vector tx ty tvx tvy) (vector ux uy))))
                     (list (aref next-state 0) (aref next-state 1)
                           (aref next-state 2) (aref next-state 3)
                           (- fuel dt)))
                   ;; Out of fuel: Drift passively along LEO orbit
                   (let ((next-state (propagate-state-2d ad bd (vector tx ty tvx tvy) #(0.0d0 0.0d0))))
                     (list (aref next-state 0) (aref next-state 1)
                           (aref next-state 2) (aref next-state 3)
                           0.0d0))))))

     ;; --- Railgun Slugs Passive Propagation ---
     (defun update-slugs (slugs ad bd dt)
       "Railgun slugs follow unguided orbital paths using passive drift."
       (loop for slug in slugs
             collect
             (let* ((sx (first slug)) (sy (second slug))
                    (svx (third slug)) (svy (fourth slug))
                    (next-state (propagate-state-2d ad bd (vector sx sy svx svy) #(0.0d0 0.0d0))))
               (list (aref next-state 0) (aref next-state 1)
                     (aref next-state 2) (aref next-state 3)))))

     ;; --- Collision Detection Helper ---
     (defun check-collision (pos-a pos-b radius)
       (let* ((dx (- (aref pos-a 0) (aref pos-b 0)))
              (dy (- (aref pos-a 1) (aref pos-b 1)))
              (dist (sqrt (+ (* dx dx) (* dy dy)))))
         (< dist radius)))

     ;; --- Point Defense Cannon (PDC) Automatic Targeting & Defense ---
     (defun update-pdc-defense (ship-pos torpedoes pdc-range dt)
       "Identify closest torpedo within range, spawn a PDC bullet/trail, and destroy the torpedo on hit."
       (let ((closest-torp nil)
             (min-dist 100000.0d0)
             (remaining-torpedoes nil)
             (bullet-trail nil))
         (dolist (torp torpedoes)
           (let* ((tx (first torp)) (ty (second torp))
                  (dx (- (aref ship-pos 0) tx))
                  (dy (- (aref ship-pos 1) ty))
                  (dist (sqrt (+ (* dx dx) (* dy dy)))))
             (if (and (< dist pdc-range) (< dist min-dist))
                 (setf min-dist dist
                       closest-torp torp)
                 (push torp remaining-torpedoes))))
         (if closest-torp
             ;; Spawn trail to the target and remove it (destroying the torpedo)
             (progn
               (setf bullet-trail (list (aref ship-pos 0) (aref ship-pos 1)
                                        (first closest-torp) (second closest-torp)))
               (values remaining-torpedoes bullet-trail))
             (values torpedoes nil))))
     ))
