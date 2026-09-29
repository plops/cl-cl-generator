;;;; test-signatures.lisp --- the signatures pass and remaining negative cases

(in-package :polyglot.tests)

(def-suite :polyglot.unit.signatures :in :polyglot.unit)
(in-suite :polyglot.unit.signatures)

(defun signatures-of (string)
  (let ((m (parse-module-form (read-dsl string))))
    (first (ir-modules (run-passes (make-project-item :name "t" :modules (list m) :entry (ir-name m))
                                   (list :backend :test) :until :desugar)))))

(test result-type-is-inherited
  (let* ((m (signatures-of "(defmodule m
             (definterface shape (defmethod area ((s :in)) (declare (values :f64))))
             (defstruct sq (:implements shape) (a :f64) (defmethod area ((q :in)) (* (dot q a) (dot q a)))))"))
         (area (first (ir-methods (second (ir-items m))))))
    (is (eq :f64 (ir-ret area)))
    ;; and desugar could add the tail return because the type was known
    (is (typep (first (ir-body area)) 'return-stmt))))

(test inherited-through-base-class
  (let* ((m (signatures-of "(defmodule m
             (defclass a () (defmethod f ((x :in)) (declare (values :i64) (virtual)) 1))
             (defclass b (a) (defmethod f ((x :in)) (declare (override)) 2)))"))
         (f (first (ir-methods (second (ir-items m))))))
    (is (eq :i64 (ir-ret f)))))

(test cyclic-inheritance-is-an-error
  (signals dsl-error
           (signatures-of "(defmodule m (defclass a (b) (defmethod f ((x :in)) 1)) (defclass b (a)))")))

(test composition-rejects-sink-receivers
  (signals unsupported-construct
           (let ((m (parse-module-form
                     (read-dsl "(defmodule m (defclass a () (defmethod f ((x :sink)) (declare (virtual)) (print-line \"a\")))
                                      (defclass b (a)) (defun main () (f (make-b))))"))))
             (setf (ir-entry-p m) t)
             (generate-artifacts (find-backend :rust) (make-project-item :name "t" :modules (list m) :entry "m")))))

(test unknown-backend-key-in-target-case
  (signals dsl-error (parse-stmt (read-dsl "(target-case (:fortran (f)))"))))
