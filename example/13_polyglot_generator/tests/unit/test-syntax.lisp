;;;; test-syntax.lisp --- readtable and condition smoke tests

(in-package :polyglot.tests)

(def-suite :polyglot.unit.syntax :in :polyglot.unit)
(in-suite :polyglot.unit.syntax)

(test invert-readtable-keeps-mixed-case
  (is (string= "Point" (symbol-name (read-dsl "Point"))))
  (is (string= "POINT" (symbol-name (read-dsl "point"))))
  (is (string= "point" (symbol-name (read-dsl "POINT")))))

(test dsl-reads-doubles
  (is (typep (read-dsl "1.5") 'double-float)))

(test conditions-carry-form
  (let ((c (handler-case (dsl-error '(foo 1) "bad ~a" 42)
             (dsl-error (e) e))))
    (is (equal '(foo 1) (dsl-error-form c)))
    (is (search "bad 42" (princ-to-string c))))
  (signals unsupported-construct (unsupported '(x) "nope")))
