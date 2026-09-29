;;;; project.lisp --- shapes and widgets: interfaces with default methods,
;;;; implementation inheritance with call-super, two modules

(in-package :polyglot-user)
(in-dsl)

(defmodule shapes (:export shape circle rect total-area)
           (definterface shape
               "Something with an area."
             (defmethod area ((s :in)) (declare (values :f64)))
             (defmethod label ((s :in)) (declare (values :string)))
             (defmethod describe ((s :in))
               (declare (values :string))
               (format-string "{} with area {:.2f}" (label s) (area s))))

           (defstruct circle (:implements shape) (r :f64 1d0)
                      (defmethod area ((c :in)) (* 3d0 (dot c r) (dot c r)))
                      (defmethod label ((c :in)) "circle"))

           (defstruct rect (:implements shape) (w :f64 1d0) (h :f64 1d0)
                      (defmethod area ((r :in)) (* (dot r w) (dot r h)))
                      (defmethod label ((r :in)) "rect"))

           (defun total-area (items)
             "Sum of the areas of all shapes."
             (declare (type (vec (box (dyn shape))) items) (values :f64))
             (let ((sum 0d0))
               (dolist (s items)
                 (incf sum (area s)))
               sum)))

(defmodule app (:import shapes)
           (defclass widget () (x :f64 0d0) (y :f64 0d0)
                     (defmethod width ((w :in)) (declare (values :f64) (virtual)) 1d0)
                     (defmethod kind ((w :in)) (declare (values :string) (virtual)) "widget")
                     (defmethod render ((w :in))
                       (declare (values :string))
                       (format-string "{} at ({:.1f}, {:.1f}) width {:.1f}" (kind w) (dot w x) (dot w y) (width w)))
                     (defmethod move-to ((w :inout) nx ny)
                       (declare (type :f64 nx ny))
                       (setf (dot w x) nx (dot w y) ny)))

           (defclass button (widget) (caption :string "")
             (defmethod width ((b :in)) (declare (values :f64) (override))
                        (+ (call-super) (to-float (string-char-count (dot b caption)))))
             (defmethod kind ((b :in)) (declare (values :string) (override))
                        (string-concat "button '" (dot b caption) "'")))

           (defun main ()
             (let ((items (vec-of (box (dyn shape)) (box (make-circle :r 2d0)) (box (make-rect :w 3d0 :h 4d0)))))
               (dolist (s items)
                 (print-line (describe s)))
               (print-line (format-string "total area = {:.2f}" (total-area items))))
             (let ((ui (vec-of (box widget) (box (make-widget)) (box (make-button :caption "OK")))))
               (dotimes (i (length ui))
                 (move-to (aref ui i) (to-float (* 10 i)) 5d0))
               (dolist (w ui)
                 (print-line (render w))))))

(defproject shapes-demo (:modules shapes app) (:entry app))
