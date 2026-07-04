(in-package :cl-user)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (let ((current-dir (make-pathname :directory (pathname-directory *load-pathname*))))
    ;; Register the local directories in the ASDF central registry
    (push current-dir asdf:*central-registry*)
    (push (merge-pathnames "../07_pure_x11/source/" current-dir) asdf:*central-registry*)
    (ql:quickload '(:cl-cl-generator :pure-x11-gen))
    (load (merge-pathnames "package.lisp" current-dir))
    (load (merge-pathnames "generate-diode-solver.lisp" current-dir))))

(in-package :multi-domain-solver)

;; Compile the diode netlist to code
(eval-when (:compile-toplevel :load-toplevel :execute)
  (let ((current-dir (make-pathname :directory (pathname-directory *load-pathname*))))
    (format t "Generating electro-thermal diode solver...~%")
    (generate-diode-solver-file "diode-solver" :directory current-dir)
    (format t "Loading generated diode solver...~%")
    (load (merge-pathnames "diode-solver.lisp" current-dir))))

;; Define the GUI package
(defpackage :multi-domain-solver/diode-gui
  (:use :cl :pure-x11-gen :multi-domain-solver)
  (:import-from :multi-domain-solver
                #:sim-state-time
                #:sim-state-v-s
                #:sim-state-v-d
                #:sim-state-i-d
                #:sim-state-temp
                #:sim-state-p-d
                #:make-sim-state
                #:step-simulation)
  (:export #:run-diode-gui-demo))

(in-package :multi-domain-solver/diode-gui)

(defvar *gc-voltage* nil)
(defvar *gc-diode-volt* nil)
(defvar *gc-current* nil)
(defvar *gc-temp* nil)
(defvar *gc-heat-aura* nil)
(defvar *gc-heatsink* nil)

(defun init-diode-gcs (win)
  (declare (ignore win))
  (setf *gc-voltage* (next-resource-id)
        *gc-diode-volt* (next-resource-id)
        *gc-current* (next-resource-id)
        *gc-temp* (next-resource-id)
        *gc-heat-aura* (next-resource-id)
        *gc-heatsink* (next-resource-id))
  (create-gc *gc-voltage* :foreground #x0033cc33)     ; Green for source voltage
  (create-gc *gc-diode-volt* :foreground #x00ff9900)  ; Orange for diode voltage
  (create-gc *gc-current* :foreground #x003366cc)     ; Blue for diode current
  (create-gc *gc-temp* :foreground #x00cc3333)        ; Red for temperature
  (create-gc *gc-heat-aura* :foreground #x00ff5555)    ; Light red/orange for heat aura
  (create-gc *gc-heatsink* :foreground #x00777777))   ; Dark gray for heatsink

(defstruct app-state
  (sim-state nil)
  (history nil)
  (animating-p t)
  (amplitude 5.0d0)
  (frequency 2.0d0))

(defun update-app (state msg)
  (case (car msg)
    (:tick
     (if (app-state-animating-p state)
         (let* ((sim (app-state-sim-state state))
                ;; Timestep of 0.5 ms
                (dt 5d-4)
                (next-sim sim))
           ;; Run 100 simulation steps per GUI tick to simulate 0.05 seconds of physical time
           (dotimes (i 100)
             (let* ((t-curr (sim-state-time next-sim))
                    (v-s-val (* (app-state-amplitude state) (sin (* 2.0d0 pi (app-state-frequency state) t-curr)))))
               (step-simulation next-sim dt v-s-val)))
           ;; Extract new values
           (let* ((t-val (sim-state-time next-sim))
                  (vs (sim-state-v-s next-sim))
                  (vd (sim-state-v-d next-sim))
                  (id (sim-state-i-d next-sim))
                  (temp (sim-state-temp next-sim))
                  (pd (sim-state-p-d next-sim))
                  (hist (cons (list t-val vs vd id temp pd) (app-state-history state)))
                  (trimmed-hist (if (> (length hist) 150) (subseq hist 0 150) hist)))
             (make-app-state :sim-state next-sim
                             :history trimmed-hist
                             :animating-p t
                             :amplitude (app-state-amplitude state)
                             :frequency (app-state-frequency state))))
         state))
    (:toggle-animation
     (make-app-state :sim-state (app-state-sim-state state)
                     :history (app-state-history state)
                     :animating-p (not (app-state-animating-p state))
                     :amplitude (app-state-amplitude state)
                     :frequency (app-state-frequency state)))
    (:reset
     (make-app-state :sim-state (make-sim-state)
                     :history nil
                     :animating-p t
                     :amplitude (app-state-amplitude state)
                     :frequency (app-state-frequency state)))
    (t state)))

(defun get-visualizer-shapes (state)
  (let* ((sim (app-state-sim-state state))
         (temp (sim-state-temp sim))
         (shapes nil))
    
    ;; -------------------------------------------------------------
    ;; 1. Draw Schematic
    ;; -------------------------------------------------------------
    
    ;; AC Source Circle
    (push (list :circle -1.5 0.55 0.15 :color *gc-text*) shapes)
    (push (list :line -1.6 0.55 -1.55 0.58 :color *gc-text*) shapes)
    (push (list :line -1.55 0.58 -1.45 0.52 :color *gc-text*) shapes)
    (push (list :line -1.45 0.52 -1.4 0.55 :color *gc-text*) shapes)
    (push (list :text "Vs (AC)" -1.9 0.75 :color *gc-text*) shapes)
    
    ;; Wires around source
    (push (list :line -1.5 0.7 -1.5 0.8 :color *gc-text*) shapes)
    (push (list :line -1.5 0.4 -1.5 0.3 :color *gc-text*) shapes)
    
    ;; Resistor Box (from -0.9, 0.7 to -0.3, 0.9)
    (push (list :line -0.9 0.7 -0.3 0.7 :color *gc-text*) shapes)
    (push (list :line -0.3 0.7 -0.3 0.9 :color *gc-text*) shapes)
    (push (list :line -0.3 0.9 -0.9 0.9 :color *gc-text*) shapes)
    (push (list :line -0.9 0.9 -0.9 0.7 :color *gc-text*) shapes)
    (push (list :text "Rs = 100 Ohm" -0.75 1.0 :color *gc-text*) shapes)
    
    ;; Wires to resistor
    (push (list :line -1.5 0.8 -0.9 0.8 :color *gc-text*) shapes)
    (push (list :line -0.3 0.8 0.5 0.8 :color *gc-text*) shapes)
    
    ;; Diode (Vertical from 0.5, 0.8 to 0.5, 0.3)
    (push (list :line 0.5 0.8 0.5 0.7 :color *gc-text*) shapes)
    
    ;; Diode Triangle (pointing down)
    (push (list :line 0.4 0.7 0.6 0.7 :color *gc-text*) shapes)
    (push (list :line 0.4 0.7 0.5 0.58 :color *gc-text*) shapes)
    (push (list :line 0.6 0.7 0.5 0.58 :color *gc-text*) shapes)
    ;; Diode Bar
    (push (list :line 0.4 0.58 0.6 0.58 :color *gc-text*) shapes)
    ;; Wire below diode
    (push (list :line 0.5 0.58 0.5 0.3 :color *gc-text*) shapes)
    (push (list :text "D1 (1N4148)" 0.7 0.68 :color *gc-text*) shapes)
    
    ;; Ground Line and symbol
    (push (list :line -1.5 0.3 0.5 0.3 :color *gc-text*) shapes)
    (push (list :line 0.0 0.3 0.0 0.22 :color *gc-text*) shapes)
    (push (list :line -0.1 0.22 0.1 0.22 :color *gc-text*) shapes)
    (push (list :line -0.06 0.18 0.06 0.18 :color *gc-text*) shapes)
    (push (list :line -0.02 0.14 0.02 0.14 :color *gc-text*) shapes)
    
    ;; Dynamic Heat Aura (red disk behind/around diode whose size reflects temperature rise)
    (let* ((temp-rise (- temp 298.15d0))
           (aura-r (max 0.0d0 (* 0.006d0 temp-rise))))
      (when (> aura-r 0.0d0)
        (push (list :circle 0.5 0.64 aura-r :color *gc-heat-aura*) shapes)
        (when (> aura-r 0.05d0)
          (push (list :circle 0.5 0.64 (- aura-r 0.04d0) :color *gc-heat-aura*) shapes))))
    
    ;; Heatsink (Thermal Domain representation)
    (push (list :line 1.2 0.7 1.2 0.65 :color *gc-temp*) shapes) ; thermal connection path
    ;; Heatsink block base
    (push (list :line 1.0 0.5 1.5 0.5 :color *gc-heatsink*) shapes)
    (push (list :line 1.0 0.5 1.0 0.65 :color *gc-heatsink*) shapes)
    (push (list :line 1.5 0.5 1.5 0.65 :color *gc-heatsink*) shapes)
    (push (list :line 1.0 0.65 1.5 0.65 :color *gc-heatsink*) shapes)
    ;; Heatsink Fins
    (loop for fx from 1.05 to 1.45 by 0.08 do
      (push (list :line fx 0.65 fx 0.75 :color *gc-heatsink*) shapes))
    (push (list :text "Kuehlkoerper" 0.95 0.42 :color *gc-text*) shapes)
    (push (list :text (format nil "T_j: ~,1f C" (- temp 298.15d0)) 1.0 0.8 :color *gc-temp*) shapes)
    
    ;; -------------------------------------------------------------
    ;; 2. Draw Rolling Plots (bottom area: y from -1.3 to -0.2)
    ;; -------------------------------------------------------------
    (let ((hist (app-state-history state)))
      (when hist
        (let* ((t-end (caar hist))
               (t-start (car (car (last hist))))
               (t-range (max 0.1d0 (- t-end t-start)))
               (v-pts-vs nil)
               (v-pts-vd nil)
               (i-pts nil)
               (t-pts nil))
          
          (dolist (pt hist)
            (let* ((pt-t (first pt))
                   (pt-vs (second pt))
                   (pt-vd (third pt))
                   (pt-id (fourth pt))
                   (pt-temp (fifth pt))
                   (t-ratio (/ (- pt-t t-start) t-range)))
              
              ;; Plot 1: Voltages (Vs and Vd)
              (let ((px (+ -1.8 (* 1.1 t-ratio))))
                (push (list px (+ -0.75 (* 0.45 (/ pt-vs 6.0d0)))) v-pts-vs)
                (push (list px (+ -0.75 (* 0.45 (/ pt-vd 6.0d0)))) v-pts-vd))
              
              ;; Plot 2: Current (Id)
              (let ((px (+ -0.55 (* 1.1 t-ratio))))
                (push (list px (+ -1.2 (* 0.9 (/ (* 1000.0d0 pt-id) 50.0d0)))) i-pts))
              
              ;; Plot 3: Temperature (Temp)
              (let ((px (+ 0.7 (* 1.1 t-ratio))))
                (push (list px (+ -1.2 (* 0.9 (/ (- pt-temp 298.15d0) 25.0d0)))) t-pts))))
          
          ;; Draw Plot 1: Voltages
          (push (list :line -1.8 -0.3 -0.7 -0.3 :color *gc-shadow*) shapes)
          (push (list :line -1.8 -1.2 -0.7 -1.2 :color *gc-shadow*) shapes)
          (push (list :line -1.8 -0.3 -1.8 -1.2 :color *gc-shadow*) shapes)
          (push (list :line -0.7 -0.3 -0.7 -1.2 :color *gc-shadow*) shapes)
          (push (list :line -1.8 -0.75 -0.7 -0.75 :color *gc-shadow*) shapes) ; zero line
          (push (list :text "Spannung Vs, Vd (V)" -1.75 -0.22 :color *gc-text*) shapes)
          (push (list :poly-line (nreverse v-pts-vs) :color *gc-voltage*) shapes)
          (push (list :poly-line (nreverse v-pts-vd) :color *gc-diode-volt*) shapes)
          
          ;; Draw Plot 2: Current
          (push (list :line -0.55 -0.3 0.55 -0.3 :color *gc-shadow*) shapes)
          (push (list :line -0.55 -1.2 0.55 -1.2 :color *gc-shadow*) shapes)
          (push (list :line -0.55 -0.3 -0.55 -1.2 :color *gc-shadow*) shapes)
          (push (list :line 0.55 -0.3 0.55 -1.2 :color *gc-shadow*) shapes)
          (push (list :text "Diodenstrom (mA)" -0.5 -0.22 :color *gc-text*) shapes)
          (push (list :poly-line (nreverse i-pts) :color *gc-current*) shapes)
          
          ;; Draw Plot 3: Temperature
          (push (list :line 0.7 -0.3 1.8 -0.3 :color *gc-shadow*) shapes)
          (push (list :line 0.7 -1.2 1.8 -1.2 :color *gc-shadow*) shapes)
          (push (list :line 0.7 -0.3 0.7 -1.2 :color *gc-shadow*) shapes)
          (push (list :line 1.8 -0.3 1.8 -1.2 :color *gc-shadow*) shapes)
          (push (list :text "Temperaturerhoehung (C)" 0.75 -0.22 :color *gc-text*) shapes)
          (push (list :poly-line (nreverse t-pts) :color *gc-temp*) shapes)
          )))
    
    (nreverse shapes)))

(defun view-app (w h state)
  (let ((anim-p (app-state-animating-p state))
        (sim (app-state-sim-state state)))
    `(panel :name :root :x 0 :y 0 :w ,w :h ,h
       (vbox :name :main-vbox :x 10 :y 10 :w ,(- w 20) :h ,(- h 20) :padding 0 :spacing 10
         (label :name :title :text "Thermo-Elektrische Diodensimulation (Selbsterwaermung)"
                :glue (:natural 20 :stretch 0 :shrink 0))
         (canvas :name :phys-canvas
                 :xmin -2.0 :xmax 2.0 :ymin -1.5 :ymax 1.5
                 :shapes ,(get-visualizer-shapes state)
                 :glue (:natural 400 :stretch 1 :shrink 1))
         (hbox :name :controls :glue (:natural 32 :stretch 0 :shrink 0) :spacing 10
           (button :name :btn-play :text ,(if anim-p "Pause" "Play") :msg (:toggle-animation)
                   :glue (:natural 100 :stretch 1 :shrink 0))
           (button :name :btn-reset :text "Reset" :msg (:reset)
                   :glue (:natural 100 :stretch 1 :shrink 0)))
         (label :name :status-text
                :text ,(format nil "Zeit: ~,3f s | V_src: ~,2f V | V_dio: ~,2f V | I_dio: ~,2f mA | T_junc: ~,1f C"
                               (sim-state-time sim)
                               (sim-state-v-s sim)
                               (sim-state-v-d sim)
                               (* 1000.0d0 (sim-state-i-d sim))
                               (- (sim-state-temp sim) 298.15d0))
                :glue (:natural 20 :stretch 0 :shrink 0))))))

(defun run-diode-gui-demo ()
  "Run the interactive thermo-electrical diode simulation X11 GUI."
  (run-gui #'update-app #'view-app (make-app-state :sim-state (make-sim-state))
           :tick-interval 0.05
           :init-fn #'init-diode-gcs))
