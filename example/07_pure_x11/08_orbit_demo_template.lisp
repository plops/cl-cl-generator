(in-package :cl-cl-generator/example-x11-gen)

(defparameter *orbit-demo-template-code*
  `(toplevel
     ,@(make-header-comments)
     (defpackage :pure-x11-gen/orbit-demo
       (:use :cl :pure-x11-gen)
       (:export #:run-orbit-demo))
     (in-package :pure-x11-gen/orbit-demo)

     (defvar *gc-sun* nil)
     (defvar *gc-earth* nil)
     (defvar *gc-mars* nil)
     (defvar *gc-spacecraft* nil)

     (defun init-orbit-gcs (win)
       (declare (ignore win))
       (setf *gc-sun* (next-resource-id)
             *gc-earth* (next-resource-id)
             *gc-mars* (next-resource-id)
             *gc-spacecraft* (next-resource-id))
       (create-gc *gc-sun* :foreground #x00ffcc00)
       (create-gc *gc-earth* :foreground #x003399ff)
       (create-gc *gc-mars* :foreground #x00ff3300)
       (create-gc *gc-spacecraft* :foreground #x0033cc33))

     (defstruct app-state
       (time 0.0)
       (animating-p t))

     (defparameter *orbit-trace-cache*
       (let ((a 1.262)
             (ecc 0.208))
         (loop for theta from 0.0 to (+ pi 0.05) by 0.05
               collect (let ((r (/ (* a (- 1 (* ecc ecc))) (+ 1 (* ecc (cos theta))))))
                         (list theta (list (* r (cos theta)) (* r (sin theta))))))))

     (defun update (state msg)
       (case (car msg)
         (:tick
          (if (app-state-animating-p state)
              (let ((new-time (+ (app-state-time state) 0.03)))
                (if (> new-time pi)
                    (make-app-state :time 0.0 :animating-p t)
                    (make-app-state :time new-time :animating-p t)))
              state))
         (:toggle-animation
          (make-app-state :time (app-state-time state)
                          :animating-p (not (app-state-animating-p state))))
         (:reset-animation
          (make-app-state :time 0.0
                          :animating-p t))
         (t state)))

     (defun get-planetary-shapes (t-val)
       (let* ((omega-e 1.0)
              (omega-m (/ 1.0 1.88))
              (mars-launch-phase (- pi (* omega-m pi)))
              (ex (cos (* omega-e t-val)))
              (ey (sin (* omega-e t-val)))
              (mx (* 1.524 (cos (+ mars-launch-phase (* omega-m t-val)))))
              (my (* 1.524 (sin (+ mars-launch-phase (* omega-m t-val)))))
              (a 1.262)
              (ecc 0.208)
              (r-space (/ (* a (- 1 (* ecc ecc))) (+ 1 (* ecc (cos t-val)))))
              (sx (* r-space (cos t-val)))
              (sy (* r-space (sin t-val)))
              (trace-points (loop for (th pt) in *orbit-trace-cache*
                                  while (<= th t-val)
                                  collect pt)))
         (list
           (list :disk 0.0 0.0 0.12 :color *gc-sun*)
           (list :circle 0.0 0.0 1.0 :color *gc-shadow*)
           (list :circle 0.0 0.0 1.524 :color *gc-shadow*)
           (list :disk ex ey 0.06 :color *gc-earth*)
           (list :disk mx my 0.05 :color *gc-mars*)
           (if trace-points
               (list :poly-line trace-points :color *gc-shadow*)
               nil)
           (list :disk sx sy 0.03 :color *gc-spacecraft*))))

     (raw "
(defun view (w h state)
  (let ((t-val (app-state-time state))
        (anim-p (app-state-animating-p state)))
    `(panel :name :root :x 0 :y 0 :w ,w :h ,h
       (vbox :name :main-vbox :x 10 :y 10 :w ,(- w 20) :h ,(- h 20) :padding 0 :spacing 10
         (label :name :title :text \"Earth-to-Mars Hohmann Transfer Simulation\"
                :glue (:natural 20 :stretch 0 :shrink 0))
         (canvas :name :planetary-system
                 :xmin -1.8 :xmax 1.8 :ymin -1.8 :ymax 1.8
                 :shapes ,(get-planetary-shapes t-val)
                 :glue (:natural 300 :stretch 1 :shrink 1))
         (hbox :name :controls :glue (:natural 30 :stretch 0 :shrink 0) :spacing 10
           (button :name :btn-play :text ,(if anim-p \"Pause\" \"Play\") :msg (:toggle-animation)
                   :glue (:natural 100 :stretch 1 :shrink 0))
           (button :name :btn-reset :text \"Reset\" :msg (:reset-animation)
                   :glue (:natural 100 :stretch 1 :shrink 0)))
         (label :name :status-text :text ,(format nil \"Spacecraft flight time: ~,2f years\" (/ t-val (* 2 pi)))
                :glue (:natural 20 :stretch 0 :shrink 0))))))
")

     (defun run-orbit-demo ()
       "Connect to X11 and run the planetary orbit trajectory visualization."
       (run-gui #'update #'view (make-app-state)
                :tick-interval 0.05
                :init-fn #'init-orbit-gcs))
     ))
