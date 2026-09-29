;;;; p08_inheritance --- widget -> button -> fancy-button: virtual call from
;;;; the base, call-super over two levels, field mutation through :inout
;;;; (K3 stage 2)

(in-package :polyglot-user)
(in-dsl)

(defmodule widgets (:entry t)
  (defclass widget () (x :f64 0d0) (y :f64 0d0)
    (defmethod area ((w :in)) (declare (values :f64) (virtual)) 0d0)
    (defmethod kind ((w :in)) (declare (values :string) (virtual)) "widget")
    (defmethod describe ((w :in))
      (declare (values :string))
      (format-string "{} at ({:.1f}, {:.1f}) area={:.2f}" (kind w) (dot w x) (dot w y) (area w)))
    (defmethod move-by ((w :inout) dx dy)
      (declare (type :f64 dx dy))
      (incf (dot w x) dx)
      (incf (dot w y) dy)))

  (defclass button (widget) (label :string "")
    (defmethod area ((b :in)) (declare (values :f64) (override)) (+ 1d0 (call-super)))
    (defmethod kind ((b :in)) (declare (values :string) (override))
      (string-concat "button " (dot b label))))

  (defclass fancy-button (button) (glow :f64 1d0)
    (defmethod area ((f :in)) (declare (values :f64) (override)) (* (dot f glow) (call-super)))
    (defmethod kind ((f :in)) (declare (values :string) (override))
      (string-concat "fancy " (call-super))))

  (defun main ()
    (let ((items (vec-of (box widget)
                         (box (make-widget :x 1d0))
                         (box (make-button :label "ok" :y 2d0))
                         (box (make-fancy-button :label "go" :glow 3d0)))))
      (dolist (w items)
        (move-by w 1d0 0.5d0)
        (print-line (describe w))))))

(defproject inheritance (:modules widgets) (:entry widgets))
