;;;; 01-syntax.lisp --- named readtable for DSL files (no global mutation)

(in-package :polyglot)

(named-readtables:defreadtable polyglot-syntax
  (:merge :standard)
  (:case :invert))

(defmacro in-dsl ()
  "Switch the current file to the DSL syntax: the case preserving readtable
POLYGLOT-SYNTAX (readtable-case :invert) and double-float as the default
float format, so that 1.5 reads as a double."
  `(progn
     (named-readtables:in-readtable polyglot-syntax)
     (eval-when (:compile-toplevel :load-toplevel :execute)
       (setf *read-default-float-format* 'double-float))))
