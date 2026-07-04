(in-package :cl-cl-generator/example-x11-gen)

(defparameter *widgets-builtin-template-code*
  `(toplevel
     ,@(make-header-comments)
     (in-package :pure-x11-gen)

     (register-widget "PANEL"
       (lambda (w-struct focused pressed hovered)
         (let ((x (widget-x w-struct))
               (y (widget-y w-struct))
               (w (widget-w w-struct))
               (h (widget-h w-struct)))
           (poly-fill-rectangle (list (list x y w h)) :gc *gc-face*)
           (draw-bevel x y w h :style :raised)
           (render-layout-children (widget-children w-struct) focused pressed hovered))))

     (register-widget "HBOX"
       (lambda (w-struct focused pressed hovered)
         (render-layout-children (widget-children w-struct) focused pressed hovered)))

     (register-widget "VBOX"
       (lambda (w-struct focused pressed hovered)
         (render-layout-children (widget-children w-struct) focused pressed hovered)))

     (register-widget "LABEL"
       (lambda (w-struct focused pressed hovered)
         (let* ((props (widget-props w-struct))
                (text (getf props :text ""))
                (x (widget-x w-struct))
                (y (widget-y w-struct)))
           (imagetext8 text :x x :y y :gc *gc-text*))))

     (register-widget "BUTTON"
       (lambda (w-struct focused pressed hovered)
         (let* ((x (widget-x w-struct))
                (y (widget-y w-struct))
                (w (widget-w w-struct))
                (h (widget-h w-struct))
                (name (widget-name w-struct))
                (props (widget-props w-struct))
                (text (getf props :text ""))
                (is-pressed-p (eq name pressed))
                (text-x (+ x (floor (- w (* 6 (length text))) 2)))
                (text-y (+ y (floor h 2) 4)))
           (poly-fill-rectangle (list (list x y w h)) :gc *gc-face*)
           (if is-pressed-p
               (progn
                 (draw-bevel x y w h :style :sunken)
                 (imagetext8 text :x (1+ text-x) :y (1+ text-y) :gc *gc-text*))
               (progn
                 (draw-bevel x y w h :style :raised)
                 (imagetext8 text :x text-x :y text-y :gc *gc-text*))))))

     (register-widget "CHECKBOX"
       (lambda (w-struct focused pressed hovered)
         (let* ((x (widget-x w-struct))
                (y (widget-y w-struct))
                (w (widget-w w-struct))
                (h (widget-h w-struct))
                (name (widget-name w-struct))
                (props (widget-props w-struct))
                (label (getf props :label ""))
                (checked-p (getf props :checked-p))
                (is-focused-p (eq name focused))
                (bx (+ x 2))
                (by (+ y (floor (- h 14) 2)))
                (text-x (+ x 22))
                (text-y (+ y (floor h 2) 4)))
           (poly-fill-rectangle (list (list (+ bx 2) (+ by 2) 10 10)) :gc *gc-light*)
           (draw-bevel bx by 14 14 :style :sunken :bevel-width 2)
           (when checked-p
             (imagetext8 "X" :x (+ bx 4) :y (+ by 11) :gc *gc-text*))
           (imagetext8 label :x text-x :y text-y :gc *gc-text*)
           (when is-focused-p
             (poly-rectangle (list (list (1- text-x) (- text-y 12) (+ (* 6 (length label)) 2) 16)) :gc *gc-text*)))))

     (register-widget "TEXT-INPUT"
       (lambda (w-struct focused pressed hovered)
         (let* ((x (widget-x w-struct))
                (y (widget-y w-struct))
                (w (widget-w w-struct))
                (h (widget-h w-struct))
                (name (widget-name w-struct))
                (props (widget-props w-struct))
                (text (getf props :text ""))
                (cursor-pos (getf props :cursor-pos 0))
                (is-focused-p (eq name focused))
                (text-x (+ x 6))
                (text-y (+ y (floor h 2) 4)))
           (poly-fill-rectangle (list (list (+ x 2) (+ y 2) (- w 4) (- h 4))) :gc *gc-light*)
           (draw-bevel x y w h :style :sunken :bevel-width 2)
           (imagetext8 text :x text-x :y text-y :gc *gc-text*)
           (when is-focused-p
             (let ((cx (+ text-x (* 6 cursor-pos))))
               (draw-line cx (+ y 4) cx (+ y h -4) :gc *gc-text*))))))
     ))
