;;;; p12_arg_order --- arguments with side effects are evaluated left to
;;;; right in every target (E8; C++ needs temporaries)

(in-package :polyglot-user)
(in-dsl)

(defmodule argorder (:entry t)
           (defstruct counter (n :i64 0))

           (defun next (c tag)
             (declare (type counter c) (mode :inout c) (type :string tag) (values :i64))
             (incf (dot c n))
             (print-line (format-string "eval {} -> {}" tag (dot c n)))
             (dot c n))

           (defun combine (a b cc)
             (declare (type :i64 a b cc) (values :i64) (pure))
             (+ (* 100 a) (* 10 b) cc))

           (defun main ()
             (let ((c (make-counter)))
               (print-line (format-string "combine = {}" (combine (next c "a") (next c "b") (next c "c"))))
               (print-line (format-string "sum = {}" (+ (next c "x") (* 2 (next c "y"))))))))

(defproject argorder (:modules argorder) (:entry argorder))
