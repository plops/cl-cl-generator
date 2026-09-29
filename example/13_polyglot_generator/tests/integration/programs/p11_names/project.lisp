;;;; p11_names --- reserved words and role based naming (E4): type, class,
;;;; match, fn, self-ref, list, point-3d, +max-size+

(in-package :polyglot-user)
(in-dsl)

(defmodule names (:entry t)
  (defstruct point-3d (x :i64 0) (y :i64 0) (z :i64 0))
  (defconst +max-size+ :i64 100)

  (defun match (type class)
    (declare (type :i64 type class) (values :i64))
    (+ type class))

  (defun fn (list)
    (declare (type (vec :i64) list) (values :i64))
    (length list))

  (defun sum-3d (self-ref)
    (declare (type point-3d self-ref) (values :i64))
    (+ (dot self-ref x) (dot self-ref y) (dot self-ref z)))

  (defun main ()
    (let* ((type 1)
           (class 2)
           (match (match type class))
           (list (vec-of :i64 1 2 3))
           (self-ref (make-point-3d :x 1 :y 2 :z 3)))
      (print-line (format-string "match = {}" match))
      (print-line (format-string "fn = {}" (fn list)))
      (print-line (format-string "sum = {}" (sum-3d self-ref)))
      (print-line (format-string "max = {}" +max-size+)))))

(defproject names (:modules names) (:entry names))
