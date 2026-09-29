;;;; p09_multimodule --- modules with private helpers; a struct used by value
;;;; across a module boundary (C++: include) and only in a signature through
;;;; box (C++: forward declaration) (K2, R12)

(in-package :polyglot-user)
(in-dsl)

(defmodule util (:export point norm2 +unit+)
  (defconst +unit+ :f64 1d0)
  (defstruct point (x :f64 0d0) (y :f64 0d0))
  (defun square (v)
    "Private helper."
    (declare (type :f64 v) (values :f64))
    (* v v))
  (defun norm2 (p)
    (declare (type point p) (values :f64))
    (+ (square (dot p x)) (square (dot p y)))))

(defmodule geometry (:export segment seg-length midpoint) (:import util)
  (defstruct segment (a point) (b point))
  (defun half (v)
    (declare (type :f64 v) (values :f64))
    (/ v 2d0))
  (defun seg-length (s)
    (declare (type segment s) (values :f64))
    (sqrt (norm2 (make-point :x (- (dot s b x) (dot s a x)) :y (- (dot s b y) (dot s a y))))))
  (defun midpoint (s)
    (declare (type segment s) (values point))
    (make-point :x (half (+ (dot s a x) (dot s b x))) :y (half (+ (dot s a y) (dot s b y))))))

(defmodule report (:export describe-boxed) (:import util)
  (defun describe-boxed (p)
    (declare (type (box point) p) (values :string))
    (format-string "boxed ({:.2f}, {:.2f}) norm2={:.2f}" (dot p x) (dot p y) (norm2 p))))

(defmodule app (:import util geometry report)
  (defun main ()
    (let* ((s (make-segment :a (make-point :x 1d0 :y 2d0) :b (make-point :x 4d0 :y 6d0)))
           (m (midpoint s)))
      (print-line (format-string "length = {:.6f}" (seg-length s)))
      (print-line (format-string "midpoint = ({:.2f}, {:.2f})" (dot m x) (dot m y)))
      (print-line (describe-boxed (box (make-point :x +unit+ :y 2d0)))))))

(defproject multimodule (:modules util geometry report app) (:entry app))
