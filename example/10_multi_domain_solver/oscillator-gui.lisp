(in-package :cl-user)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (let ((current-dir (make-pathname :directory (pathname-directory *load-pathname*))))
    ;; Register the local directories in the ASDF central registry
    (push current-dir asdf:*central-registry*)
    (push (merge-pathnames "../07_pure_x11/source/" current-dir) asdf:*central-registry*)
    (ql:quickload '(:cl-cl-generator :pure-x11-gen))
    (load (merge-pathnames "package.lisp" current-dir))
    (load (merge-pathnames "compiler.lisp" current-dir))))

(in-package :multi-domain-solver)

;;; ============================================================================
;;; 1. Compile the Physical Netlist into Lisp Code
;;; ============================================================================

(eval-when (:compile-toplevel :load-toplevel :execute)
  (let ((current-dir (make-pathname :directory (pathname-directory *load-pathname*))))
    (format t "Compiling Mass-Spring-Damper netlist to Lisp solver...~%")
    (compile-netlist-to-file
      "oscillator-solver"
      '((capacitor m1 :nodes (1 0) :value 2.0d0)    ; Mass M = 2.0 kg
        (inductor k1 :nodes (1 0) :value 0.1d0)     ; Spring k = 10.0 N/m => L = 1/k = 0.1
        (resistor b1 :nodes (1 0) :value 2.0d0)     ; Damper b = 0.5 Ns/m => R = 1/b = 2.0 (G = 0.5)
        (current-source f1 :nodes (1 0) :value f-ext))
      :directory current-dir
      :dt 0.05d0)
    ;; Load the generated solver
    (load (merge-pathnames "oscillator-solver.lisp" current-dir))))

;;; ============================================================================
;;; 2. GUI Definition
;;; ============================================================================

(defpackage :multi-domain-solver/gui
  (:use :cl :pure-x11-gen :multi-domain-solver)
  (:import-from :multi-domain-solver
                #:sim-state-time
                #:sim-state-I-K1
                #:sim-state-V-1
                #:make-sim-state
                #:step-simulation)
  (:export #:run-gui-demo))

(in-package :multi-domain-solver/gui)

(defvar *gc-spring* nil)
(defvar *gc-mass* nil)
(defvar *gc-damper* nil)
(defvar *gc-plot* nil)

(defun init-gui-gcs (win)
  (declare (ignore win))
  (setf *gc-spring* (next-resource-id)
        *gc-mass* (next-resource-id)
        *gc-damper* (next-resource-id)
        *gc-plot* (next-resource-id))
  (create-gc *gc-spring* :foreground #x00ff9900)   ; Orange for spring
  (create-gc *gc-mass* :foreground #x003366cc)     ; Blue for mass
  (create-gc *gc-damper* :foreground #x00999999)   ; Gray for damper
  (create-gc *gc-plot* :foreground #x0033cc33))    ; Green for plot

(defstruct app-state
  (sim-state nil)
  (history nil)
  (animating-p t)
  (force 0.0d0)
  (k 10.0d0))

(defun update-app (state msg)
  (case (car msg)
    (:tick
     (if (app-state-animating-p state)
         (let* ((sim (app-state-sim-state state))
                (dt 0.05d0)
                (next-sim (step-simulation sim dt (app-state-force state)))
                ;; In MNA: Spring current i_L represents force F = k * x => x = i_L / k
                ;; The inductor current variable is I-K1
                (il (sim-state-I-K1 next-sim))
                (x (/ il (app-state-k state)))
                (t-val (sim-state-time next-sim))
                ;; Record history
                (hist (cons (list t-val x) (app-state-history state)))
                (trimmed-hist (if (> (length hist) 150) (subseq hist 0 150) hist)))
           (make-app-state :sim-state next-sim
                           :history trimmed-hist
                           :animating-p t
                           :force 0.0d0 ; Reset impulse force
                           :k (app-state-k state)))
         state))
    (:kick
     (let ((curr (app-state-force state)))
       (make-app-state :sim-state (app-state-sim-state state)
                       :history (app-state-history state)
                       :animating-p (app-state-animating-p state)
                       :force (+ curr 40.0d0) ; Apply 40 N force impulse
                       :k (app-state-k state))))
    (:toggle-animation
     (make-app-state :sim-state (app-state-sim-state state)
                     :history (app-state-history state)
                     :animating-p (not (app-state-animating-p state))
                     :force (app-state-force state)
                     :k (app-state-k state)))
    (:reset
     (make-app-state :sim-state (make-sim-state)
                     :history nil
                     :animating-p t
                     :force 0.0d0
                     :k (app-state-k state)))
    (t state)))

(defun make-spring-points (x-start x-end y-val width num-turns)
  (let* ((dx (- x-end x-start))
         (step (/ dx (+ 2 (* 2 num-turns))))
         (points (list (list x-start y-val))))
    (push (list (+ x-start step) y-val) points)
    (loop for i from 0 below num-turns do
      (push (list (+ x-start (* step (+ 2 (* 2 i)))) (+ y-val width)) points)
      (push (list (+ x-start (* step (+ 3 (* 2 i)))) (- y-val width)) points))
    (push (list (- x-end step) y-val) points)
    (push (list x-end y-val) points)
    (nreverse points)))

(defun get-visualizer-shapes (state)
  (let* ((sim (app-state-sim-state state))
         (il (sim-state-I-K1 sim))
         (x (/ il (app-state-k state)))
         ;; Map simulation displacement to screen coordinates
         ;; Center is at 0.0, mass moves around it
         (mass-x (+ 0.3 x))
         (wall-x -1.5)
         (shapes nil))
    
    ;; 1. Draw wall
    (push (list :line wall-x -0.5 wall-x 0.9 :color *gc-shadow*) shapes)
    (loop for y from -0.5 to 0.9 by 0.15 do
      (push (list :line wall-x y (- wall-x 0.1) (- y 0.1) :color *gc-shadow*) shapes))
    
    ;; 2. Draw Spring (zigzag)
    (let ((spring-pts (make-spring-points wall-x (- mass-x 0.25) 0.5 0.1 8)))
      (push (list :poly-line spring-pts :color *gc-spring*) shapes))
    
    ;; 3. Draw Damper (piston)
    (let* ((mid-x (+ wall-x (* 0.5 (- mass-x wall-x 0.25))))
           (y-dmp 0.0))
      ;; Cylinder
      (push (list :line wall-x y-dmp mid-x y-dmp :color *gc-damper*) shapes)
      (push (list :line mid-x (+ y-dmp 0.08) mid-x (- y-dmp 0.08) :color *gc-damper*) shapes)
      (push (list :line (- mid-x 0.2) (+ y-dmp 0.08) mid-x (+ y-dmp 0.08) :color *gc-damper*) shapes)
      (push (list :line (- mid-x 0.2) (- y-dmp 0.08) mid-x (- y-dmp 0.08) :color *gc-damper*) shapes)
      ;; Piston rod & plate
      (push (list :line (- mass-x 0.25) y-dmp (- mid-x 0.1) y-dmp :color *gc-damper*) shapes)
      (push (list :line (- mid-x 0.1) (+ y-dmp 0.06) (- mid-x 0.1) (- y-dmp 0.06) :color *gc-damper*) shapes))
    
    ;; 4. Draw Mass block
    (push (list :disk mass-x 0.25 0.25 :color *gc-mass*) shapes)
    (push (list :text "MASS" (- mass-x 0.12) 0.25 :color *gc-light*) shapes)
    
    ;; 5. Draw force vector if active
    (when (> (app-state-force state) 0.0d0)
      (push (list :line (+ mass-x 0.3) 0.25 (+ mass-x 0.8) 0.25 :color *gc-spring*) shapes)
      (push (list :line (+ mass-x 0.8) 0.25 (+ mass-x 0.7) 0.3 :color *gc-spring*) shapes)
      (push (list :line (+ mass-x 0.8) 0.25 (+ mass-x 0.7) 0.2 :color *gc-spring*) shapes)
      (push (list :text "FORCE!" (+ mass-x 0.4) 0.35 :color *gc-spring*) shapes))
    
    ;; 6. Draw Rolling Plot (bottom half of canvas)
    (let ((hist (app-state-history state)))
      (when hist
        (let* ((t-end (caar hist))
               (t-start (car (car (last hist))))
               (t-range (max 1.0d0 (- t-end t-start)))
               (plot-pts
                 (loop for (pt-t pt-x) in hist
                       collect (let ((px (+ -1.8 (* 3.6 (/ (- pt-t t-start) t-range))))
                                     (py (+ -0.8 (* 0.4 pt-x))))
                                 (list px py)))))
          ;; Plot boundary frame
          (push (list :line -1.8 -0.4 1.8 -0.4 :color *gc-shadow*) shapes)
          (push (list :line -1.8 -1.2 1.8 -1.2 :color *gc-shadow*) shapes)
          (push (list :line -1.8 -0.4 -1.8 -1.2 :color *gc-shadow*) shapes)
          (push (list :line 1.8 -0.4 1.8 -1.2 :color *gc-shadow*) shapes)
          (push (list :text "Displacement x(t) vs Time" -1.7 -0.52 :color *gc-text*) shapes)
          ;; Draw the line trace
          (push (list :poly-line plot-pts :color *gc-plot*) shapes))))
    
    (nreverse shapes)))

(defun view-app (w h state)
  (let ((anim-p (app-state-animating-p state))
        (sim (app-state-sim-state state)))
    `(panel :name :root :x 0 :y 0 :w ,w :h ,h
       (vbox :name :main-vbox :x 10 :y 10 :w ,(- w 20) :h ,(- h 20) :padding 0 :spacing 10
         (label :name :title :text "Multi-Domain Lumped-Element Simulation (Mass-Spring-Damper)"
                :glue (:natural 20 :stretch 0 :shrink 0))
         (canvas :name :phys-canvas
                 :xmin -2.0 :xmax 2.0 :ymin -1.5 :ymax 1.5
                 :shapes ,(get-visualizer-shapes state)
                 :glue (:natural 320 :stretch 1 :shrink 1))
         (hbox :name :controls :glue (:natural 32 :stretch 0 :shrink 0) :spacing 10
           (button :name :btn-play :text ,(if anim-p "Pause" "Play") :msg (:toggle-animation)
                   :glue (:natural 100 :stretch 1 :shrink 0))
           (button :name :btn-kick :text "Apply Kick (Force)" :msg (:kick)
                   :glue (:natural 150 :stretch 1 :shrink 0))
           (button :name :btn-reset :text "Reset" :msg (:reset)
                   :glue (:natural 100 :stretch 1 :shrink 0)))
         (label :name :status-text
                :text ,(format nil "Time: ~,2f s  |  Displacement: ~,3f m  |  Velocity: ~,3f m/s"
                               (sim-state-time sim)
                               (/ (sim-state-I-K1 sim) (app-state-k state))
                               (sim-state-V-1 sim))
                :glue (:natural 20 :stretch 0 :shrink 0))))))

(defun run-gui-demo ()
  "Run the interactive physical simulation X11 GUI."
  (run-gui #'update-app #'view-app (make-app-state :sim-state (make-sim-state))
           :tick-interval 0.05
           :init-fn #'init-gui-gcs))
