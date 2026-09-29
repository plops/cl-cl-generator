;;;; test-desugar.lisp --- tests of the pass pipeline and desugar

(in-package :polyglot.tests)

(def-suite :polyglot.unit.desugar :in :polyglot.unit)
(in-suite :polyglot.unit.desugar)

(defun project-of (module-string &key (backend :test))
  "Parse MODULE-STRING as the only (entry) module of a project."
  (let* ((module (parse-module-form (read-dsl module-string))))
    (setf (ir-entry-p module) t)
    (values (make-project-item :name "test" :modules (list module) :entry (ir-name module))
            backend)))

(defun desugared-body (body-string &key (ret ":void") (backend :test))
  (let* ((p (project-of (format nil "(defmodule m (defun f (x) (declare (type :i64 x) (values ~a)) ~a))"
                                ret body-string)))
         (d (run-passes p (list :backend backend) :until :desugar)))
    (ir-body (first (ir-items (first (ir-modules d)))))))

(test pipeline-order
  (let ((names (mapcar #'pass-name (pass-sequence))))
    (is (eq :signatures (first names)))
    (is (< (position :desugar names) (position :resolve names)))
    (is (equal names (remove-duplicates names)))))

(test pipeline-does-not-modify-input
  (let* ((p (project-of "(defmodule m (defun f () (when true (g))))"))
         (before (ir-body (first (ir-items (first (ir-modules p)))))))
    (run-passes p (list :backend :test) :until :desugar)
    (is (typep (first before) 'when-stmt))))

(test when-unless
  (is (typep (first (desugared-body "(when (> x 0) (g))")) 'if-stmt))
  (let ((s (first (desugared-body "(unless (> x 0) (g))"))))
    (is (eq :not (ir-op (ir-test s))))))

(test cond-chain
  (let ((s (first (desugared-body "(cond ((> x 0) (a)) ((< x 0) (b)) (t (c)))"))))
    (is (typep s 'if-stmt))
    (is (typep (first (ir-else s)) 'if-stmt))
    (is (typep (first (ir-else (first (ir-else s)))) 'expr-stmt))))

(test dotimes-and-incf
  (let ((s (first (desugared-body "(dotimes (i 10) (incf x 2))"))))
    (is (typep s 'for-range-stmt))
    (is (eql 0 (ir-value (ir-start s))))
    (is (typep (first (ir-body s)) 'op-assign-stmt))
    (is (eq :add (ir-op (first (ir-body s)))))))

(test tail-returns
  (let ((s (desugared-body "(if (> x 0) x (- x))" :ret ":i64")))
    (is (typep (first (ir-then (first s))) 'return-stmt))
    (is (typep (first (ir-else (first s))) 'return-stmt)))
  (is (typep (first (desugared-body "(+ x 1)" :ret ":i64")) 'return-stmt))
  (is (typep (first (desugared-body "(+ x 1)")) 'expr-stmt)))

(test progn-spliced
  (is (= 2 (length (desugared-body "(progn (a) (b))")))))

(test target-case-selected
  (let ((s (desugared-body "(target-case (:cpp (a)) (t (b)))" :backend :cpp)))
    (is (string= "a" (ir-name (ir-expr (first s))))))
  (let ((s (desugared-body "(target-case (:cpp (a)) (t (b)))" :backend :rust)))
    (is (string= "b" (ir-name (ir-expr (first s))))))
  (signals unsupported-construct (desugared-body "(target-case (:cpp (a)))" :backend :rust)))
