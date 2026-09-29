;;;; test-macros.lisp --- DSL macros, target-case, extension forms

(in-package :polyglot.tests)

(def-suite :polyglot.unit.macros :in :polyglot.unit)
(in-suite :polyglot.unit.macros)

(define-dsl-macro test-square (x) `(* ,x ,x))
(define-dsl-macro test-twice (x) `(+ (test-square ,x) (test-square ,x)))
(define-dsl-macro test-forever (x) `(test-forever ,x))
(define-dsl-macro test-grow (x) `(+ 1 (test-grow ,x)))

(test macro-expansion
  (let ((e (parse-expr '(test-square a))))
    (is (eq :mul (ir-op e))))
  (let ((e (parse-expr '(test-twice a))))
    (is (eq :add (ir-op e)))
    (is (eq :mul (ir-op (first (ir-args e))))))
  (is (typep (parse-stmt '(test-square a)) 'expr-stmt)))

(test macro-depth-limit
  (signals dsl-error (parse-expr '(test-forever a)))
  (signals dsl-error (parse-expr '(test-grow a))))

(test target-case-branches
  (let ((s (parse-stmt (read-dsl "(target-case (:cpp (f)) ((:rust :go) (g)) (t (h)))"))))
    (is (= 3 (length (ir-branches s))))
    (is (equal '(:cpp) (ir-backends (select-target-branch s :cpp))))
    (is (equal '(:rust :go) (ir-backends (select-target-branch s :go))))
    (is (eq t (ir-backends (select-target-branch s :python)))))
  (let ((s (parse-stmt (read-dsl "(target-case (:cpp (f)))"))))
    (is (null (select-target-branch s :rust))))
  (signals dsl-error (parse-stmt (read-dsl "(target-case (:java (f)))")))
  (signals dsl-error (parse-expr (read-dsl "(target-case (:cpp 1 2))"))))

(test extension-forms
  (let ((s (parse-stmt '(polyglot.rs::raw "unsafe {}"))))
    (is (typep s 'target-form-stmt))
    (is (eq :rust (ir-backend s))))
  (is (eq :cpp (ir-backend (parse-expr '(polyglot.cpp::raw "x"))))))
