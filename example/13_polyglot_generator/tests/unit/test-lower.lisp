;;;; test-lower.lisp --- lower (E9/E10/E3), comments (E11), order-args (E8),
;;;; capability (R4)

(in-package :polyglot.tests)

(def-suite :polyglot.unit.lower :in :polyglot.unit)
(in-suite :polyglot.unit.lower)

(defparameter *cpp-like* (list :backend :test-cpp :capabilities '(:ternary t :multi-statement-lambda t)
                               :unspecified-arg-order t))
(defparameter *go-like* (list :backend :test-go :capabilities '(:ternary nil :multi-statement-lambda t)))
(defparameter *py-like* (list :backend :test-py :capabilities '(:ternary t :multi-statement-lambda nil)))

(defparameter *lower-prelude*
  "(defun f1 () (declare (values :i64)) (print-line \"f1\") 1)
   (defun f2 () (declare (values :i64)) (print-line \"f2\") 2)
   (defun g (a b) (declare (type :i64 a b) (values :i64)) (+ a b))
   (defun sq (a) (declare (type :i64 a) (values :i64) (pure)) (* a a))")

(defun lowered-body (body config &key (until :capability))
  (let* ((m (parse-module-form
             (read-dsl (format nil "(defmodule m ~a (defun main (c) (declare (type :bool c)) ~a))"
                               *lower-prelude* body))))
         (p (run-passes (make-project-item :name "t" :modules (list m) :entry "m") config :until until)))
    (ir-body (find "main" (ir-items (first (ir-modules p))) :key #'ir-name :test #'string=))))

(defun stmt-classes (stmts) (mapcar (lambda (s) (class-name (class-of s))) stmts))

(test simple-if-stays-ternary
  (let ((body (lowered-body "(let ((x (if c 1 2))) (print-line (format-string \"{}\" x)))" *cpp-like*)))
    (is (typep (ir-init (first (ir-stmts (first body)))) 'if-expr))))

(test if-without-ternary-becomes-statement
  (let* ((body (lowered-body "(let ((x (if c 1 2))) (print-line (format-string \"{}\" x)))" *go-like*))
         (inner (ir-stmts (first body))))
    (is (equal '(decl-stmt if-stmt expr-stmt) (stmt-classes inner)))
    (is (null (ir-init (first inner))))
    (is (typep (first (ir-then (second inner))) 'assign-stmt))))

(test block-value-in-argument-uses-temp
  (let ((body (lowered-body "(print-line (format-string \"{}\" (let ((a 1)) (+ a 1))))" *cpp-like*)))
    (is (equal '(decl-stmt block-stmt expr-stmt) (stmt-classes body)))
    (is (string= "tmp_1" (ir-target-name (ir-var (first body)))))))

(test return-of-if-expression
  (let ((body (lowered-body "(return)" *go-like*)))
    (is (typep (first body) 'return-stmt))))

(test short-circuit-right-operand
  (signals unsupported-construct
           (lowered-body "(when (and c (let ((y 1)) (> y 0))) (print-line \"y\"))" *cpp-like*)))

(test lambda-lifting-and-captures
  (let ((body (lowered-body "(dolist (i (vec-of :i64 1 2))
                               (let ((h (lambda (k) (declare (type :i64 k) (values :i64))
                                          (let ((z (+ k i))) (* z 2)))))
                                 (print-line (format-string \"{}\" (funcall h 1)))))" *py-like*)))
    (let* ((loop-body (ir-body (first body)))
           (block (first loop-body))
           (stmts (ir-stmts block)))
      (is (typep (first stmts) 'local-fn-stmt))
      (is (equal '("i") (mapcar #'ir-name (ir-captures (ir-fn (first stmts)))))))))

(test comments-in-expressions-move-before-statement
  (let ((s (handler-bind ((dsl-warning #'muffle-warning))
             (parse-stmt (read-dsl "(g 1 (comment \"why\") 2)")))))
    (is (typep s 'block-stmt))
    (is (equal '(comment-stmt expr-stmt) (stmt-classes (ir-stmts s)))))
  (signals dsl-warning (parse-stmt (read-dsl "(g 1 (comment \"why\") 2)"))))

(test argument-order
  (let ((body (lowered-body "(print-line (format-string \"{}\" (g (f1) (f2))))" *cpp-like*)))
    (is (equal '(decl-stmt decl-stmt expr-stmt) (stmt-classes body)))
    (is (string= "f1" (ir-name (ir-init (first body))))))
  (let ((body (lowered-body "(print-line (format-string \"{}\" (g (sq 1) (f2))))" *cpp-like*)))
    (is (equal '(expr-stmt) (stmt-classes body))))
  (let ((body (lowered-body "(print-line (format-string \"{}\" (g (f1) (f2))))" *go-like*)))
    (is (equal '(expr-stmt) (stmt-classes body)))))

(test capability-checks
  (signals unsupported-construct (lowered-body "(polyglot.rs::raw \"x\")" *cpp-like*))
  (finishes (lowered-body "(polyglot.cpp::raw \"x\")" (list* :backend :cpp (cddr *cpp-like*))))
  (signals unsupported-construct
           (let ((m (parse-module-form (read-dsl "(defmodule m (defun inc (x) (declare (type :i64 x) (mode :inout x)) (incf x)))"))))
             (run-passes (make-project-item :name "t" :modules (list m) :entry "m") *py-like*)))
  (signals unsupported-construct
           (lowered-body "(let ((v (vec-of :i64))) (push 1 v))"
                         (list* :unsupported-nodes '(vec-expr) *cpp-like*))))
