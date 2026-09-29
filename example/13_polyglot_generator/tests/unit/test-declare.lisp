;;;; test-declare.lisp --- tests of src/frontend/23-declare.lisp

(in-package :polyglot.tests)

(def-suite :polyglot.unit.declare :in :polyglot.unit)
(in-suite :polyglot.unit.declare)

(defun decls (string)
  (split-declares (read-dsl string)))

(test every-clause
  (let ((info (decls "((declare (type :i64 a b) (values :f64) (mode :inout a)
                                 (borrows-from a) (outlives :a :b) (virtual) (pure)
                                 (capture :ref)))")))
    (is (eq :i64 (declared-type info "a")))
    (is (eq :i64 (declared-type info "b")))
    (is (eq :f64 (decl-info-ret info)))
    (is (eq :inout (declared-mode info "a")))
    (is (eq :in (declared-mode info "b")))
    (is (equal '("a") (decl-info-borrows-from info)))
    (is (equal '((:a :b)) (decl-info-outlives info)))
    (is (member :virtual (decl-info-flags info)))
    (is (member :pure (decl-info-flags info)))
    (is (eq :ref (decl-info-capture info)))))

(test docstring-before-declare
  (multiple-value-bind (info body doc)
      (split-declares (read-dsl "(\"doc\" (declare (values :i64)) 1)"))
    (is (string= "doc" doc))
    (is (eq :i64 (decl-info-ret info)))
    (is (equal '(1) body)))
  (multiple-value-bind (info body doc) (split-declares (read-dsl "(\"only\")"))
    (declare (ignore info))
    (is (null doc))
    (is (equal '("only") body))))

(test declare-errors
  (signals dsl-error (decls "((declare (type :i64 a) (type :f64 a)))"))
  (signals dsl-error (decls "((declare (values :i64) (values :f64)))"))
  (signals dsl-error (decls "((declare (frobnicate a)))"))
  (signals dsl-error (decls "((declare (mode :out a)))"))
  (signals dsl-error (decls "((declare (virtual) (virtual)))")))

(test lambda-lists
  (is (equal '("a" "b") (parse-lambda-list nil (read-dsl "(a b)"))))
  (signals unsupported-construct (parse-lambda-list nil (read-dsl "(a &optional b)")))
  (signals unsupported-construct (parse-lambda-list nil (read-dsl "(&key b)"))))

(test lambda-expr
  (let ((l (parse-expr (read-dsl "(lambda (a) (declare (type :i64 a) (values :i64)) (* a 2))"))))
    (is (eq :i64 (ir-ret l)))
    (is (eq :i64 (ir-declared-ty (first (ir-params l)))))
    (is (eq :value (ir-capture l))))
  (signals dsl-error (parse-expr (read-dsl "(lambda (a) a)"))))
