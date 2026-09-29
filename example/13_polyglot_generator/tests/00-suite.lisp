;;;; 00-suite.lisp --- test package and FiveAM suites

(defpackage :polyglot.tests
  (:use :cl :fiveam)
  (:documentation "Unit and spec tests. All internal symbols of POLYGLOT are
imported (unless they clash with FiveAM) so tests can call internals directly."))

(in-package :polyglot.tests)

;; Imported at load time with IMPORT (not SHADOWING-IMPORT in DEFPACKAGE) so
;; that reloading does not trigger package variance warnings.
(eval-when (:compile-toplevel :load-toplevel :execute)
  (do-symbols (sym :polyglot)
    (when (and (eq (symbol-package sym) (find-package :polyglot))
               (not (find-symbol (symbol-name sym) :polyglot.tests)))
      (import sym :polyglot.tests))))

(def-suite :polyglot :description "All tests of the polyglot generator.")
(def-suite :polyglot.unit :in :polyglot :description "Unit tests per source file.")
(def-suite :polyglot.spec :in :polyglot :description "Spec table: expected output per backend.")

(defun read-dsl (string)
  "Read STRING with the DSL readtable and double-float default."
  (let ((*readtable* (named-readtables:find-readtable 'polyglot:polyglot-syntax))
        (*read-default-float-format* 'double-float)
        (*package* (find-package :polyglot.tests)))
    (read-from-string string)))
