;;;; 00-package.lisp --- package definitions of the polyglot generator

(defpackage :polyglot
  (:use :cl)
  (:nicknames :pg)
  (:documentation "Multi-target transpiler: one S-expression DSL, several
idiomatic target languages (C++20, Python 3, Rust, Common Lisp, Go).")
  (:export
   ;; syntax
   #:in-dsl
   #:polyglot-syntax
   ;; conditions
   #:dsl-error
   #:unsupported-construct
   #:dsl-warning
   #:dsl-error-form
   #:dsl-error-backend
   ;; user facing definition forms
   #:defmodule
   #:defproject
   #:define-dsl-macro
   #:define-intrinsic
   #:parse-module-form
   #:find-module-form
   ;; driver
   #:write-project
   #:generate-project
   #:run-cli))

(defpackage :polyglot.cpp
  (:use)
  (:nicknames :cpp)
  (:documentation "Target specific DSL forms that only the C++ backend accepts."))

(defpackage :polyglot.py
  (:use)
  (:nicknames :py)
  (:documentation "Target specific DSL forms that only the Python backend accepts."))

(defpackage :polyglot.rs
  (:use)
  (:nicknames :rs)
  (:documentation "Target specific DSL forms that only the Rust backend accepts."))

(defpackage :polyglot.go
  (:use)
  (:nicknames :go)
  (:documentation "Target specific DSL forms that only the Go backend accepts."))
