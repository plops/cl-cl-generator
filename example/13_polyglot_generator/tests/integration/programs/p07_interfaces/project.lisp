;;;; p07_interfaces --- interface with abstract and default methods, two
;;;; implementations, a vec of (box (dyn shape)) (K3 stage 1)

(in-package :polyglot-user)
(in-dsl)

(defmodule shapes (:entry t)
  (definterface shape
    (defmethod area ((s :in)) (declare (values :f64)))
    (defmethod label ((s :in)) (declare (values :string)))
    (defmethod describe ((s :in))
      (declare (values :string))
      (format-string "{} with area {:.2f}" (label s) (area s))))

  (defstruct circle (:implements shape) (r :f64 1d0)
    (defmethod area ((c :in)) (* 3.14159d0 (dot c r) (dot c r)))
    (defmethod label ((c :in)) "circle"))

  (defstruct rect (:implements shape) (w :f64) (h :f64)
    (defmethod area ((r :in)) (* (dot r w) (dot r h)))
    (defmethod label ((r :in)) "rect")
    (defmethod describe ((r :in)) (format-string "rect {:.1f}x{:.1f}" (dot r w) (dot r h))))

  (defun total-area (shapes)
    (declare (type (vec (box (dyn shape))) shapes) (values :f64))
    (let ((sum 0d0))
      (dolist (s shapes)
        (incf sum (area s)))
      sum))

  (defun main ()
    (let ((shapes (vec-of (box (dyn shape))
                          (box (make-circle :r 1d0))
                          (box (make-rect :w 2d0 :h 3d0))
                          (box (make-circle :r 0.5d0)))))
      (dolist (s shapes)
        (print-line (describe s)))
      (print-line (format-string "total = {:.3f}" (total-area shapes))))))

(defproject interfaces (:modules shapes) (:entry shapes))
