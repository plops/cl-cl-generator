;;;; p10_closures --- lambdas capture the loop variable by value (E3), a
;;;; lambda with several statements (E10), funcall, functions as arguments

(in-package :polyglot-user)
(in-dsl)

(defmodule closures (:entry t)
  (defun apply-twice (f x)
    (declare (type (fn (:i64) :i64) f) (type :i64 x) (values :i64))
    (funcall f (funcall f x)))

  (defun main ()
    (let ((adders (vec-of (fn (:i64) :i64))))
      (dotimes (i 3)
        (push (lambda (x) (declare (type :i64 x) (values :i64)) (+ x i)) adders))
      (dolist (f adders)
        (print-line (format-string "adder: {}" (funcall f 10)))))
    (let ((scale 3))
      (let ((g (lambda (x)
                 (declare (type :i64 x) (values :i64))
                 (let ((y (* x scale)))
                   (if (> y 20) (- y 20) y)))))
        (print-line (format-string "g(4) = {}" (funcall g 4)))
        (print-line (format-string "g(9) = {}" (funcall g 9)))
        (print-line (format-string "twice = {}" (apply-twice g 2)))))))

(defproject closures (:modules closures) (:entry closures))
