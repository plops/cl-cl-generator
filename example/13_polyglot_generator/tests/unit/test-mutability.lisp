;;;; test-mutability.lisp --- tests of the mutability pass

(in-package :polyglot.tests)

(def-suite :polyglot.unit.mutability :in :polyglot.unit)
(in-suite :polyglot.unit.mutability)

(defun mutability-of (module-string)
  "Alist local name -> mutable flag after the mutability pass."
  (let* ((m (parse-module-form (read-dsl module-string)))
         (p (run-passes (make-project-item :name "t" :modules (list m) :entry (ir-name m))
                        (list :backend :test) :until :mutability))
         (out '()))
    (walk-nodes (lambda (n)
                  (when (and (typep n 'var-def) (member (ir-kind n) '(:local :param)))
                    (push (cons (ir-name n) (ir-mutable n)) out)))
                p)
    (values out p)))

(defun mutable-p (alist name) (cdr (assoc name alist :test #'string=)))

(defparameter *mut-prelude* "(defstruct point (x :i64 0))
  (defstruct bag (items (vec :i64) nil))
  (defmethod bump ((p point :inout)) (incf (dot p x)))
  (defmethod get-x ((p point :in)) (declare (values :i64)) (dot p x))
  (defun move-it (p) (declare (type point p) (mode :inout p)) (setf (dot p x) 5))")

(defun mut-module (body)
  (format nil "(defmodule m ~a (defun f () ~a))" *mut-prelude* body))

(test assignment-and-incf
  (let ((a (mutability-of (mut-module "(let ((a 1) (b 2) (c 3)) (setf a 5) (incf b) (print-line (format-string \"{}{}{}\" a b c)))"))))
    (is (mutable-p a "a"))
    (is (mutable-p a "b"))
    (is (not (mutable-p a "c")))))

(test field-assignment-and-push
  (let ((a (mutability-of (mut-module "(let ((p (make-point)) (q (make-bag)) (v (vec-of :i64)))
                                          (setf (dot p x) 1) (push 1 (dot q items)) (push 2 v))"))))
    (is (mutable-p a "p"))
    (is (mutable-p a "q"))
    (is (mutable-p a "v"))))

(test inout-argument-and-receiver
  (let ((a (mutability-of (mut-module "(let ((p (make-point)) (q (make-point)) (r (make-point)))
                                          (move-it p) (bump q) (print-line (format-string \"{}\" (get-x r))))"))))
    (is (mutable-p a "p"))
    (is (mutable-p a "q"))
    (is (not (mutable-p a "r")))))

(test loop-iteration-modes
  (multiple-value-bind (a p)
      (mutability-of (mut-module "(let ((ps (vec-of point (make-point))) (ns (vec-of :i64 1)))
                                    (dolist (q ps) (bump q))
                                    (dolist (n ns) (print-line (format-string \"{}\" n)))
                                    (dolist (k (vec-of :i64 1 2)) (print-line (format-string \"{}\" k))))"))
    (is (mutable-p a "ps"))
    (is (not (mutable-p a "ns")))
    (let ((modes (let ((out '()))
                   (walk-nodes (lambda (n) (when (typep n 'for-each-stmt) (push (ir-iter-mode n) out))) p)
                   (nreverse out))))
      (is (equal '(:mut :ref :move) modes)))))

(test loop-variable-assignment-rejected
  (signals dsl-error (mutability-of (mut-module "(dolist (n (vec-of :i64 1)) (setf n 2))"))))

(test sink-parameter-mutation
  (let ((a (mutability-of "(defmodule m (defun f (v) (declare (type (vec :i64) v) (mode :sink v)) (push 1 v)))")))
    (is (mutable-p a "v"))))
