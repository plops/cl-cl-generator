;;;; test-rename.lisp --- tests of the rename pass with two fake configs

(in-package :polyglot.tests)

(def-suite :polyglot.unit.rename :in :polyglot.unit)
(in-suite :polyglot.unit.rename)

(defparameter *rust-like*
  (list :backend :test-rust
        :naming '((:type . :pascal) (:function . :snake) (:method . :snake) (:field . :snake)
                  (:constant . :upper-snake) (:variable . :snake) (:module . :snake))
        :reserved '("type" "match" "fn" "self")
        :escape (lambda (n role) (declare (ignore role))
                  (if (string= n "self") "self_" (concatenate 'string "r#" n)))
        :shadowing :allow :receiver-name "self"))

(defparameter *python-like*
  (list :backend :test-python
        :naming '((:type . :pascal) (:function . :snake) (:method . :snake) (:field . :snake)
                  (:constant . :upper-snake) (:variable . :snake) (:module . :snake))
        :reserved '("type" "class" "self" "list")
        :shadowing :rename :private-prefix "_" :receiver-name "self"))

(defun renamed (module-string config &key (entry nil))
  (let* ((m (parse-module-form (read-dsl module-string))))
    (setf (ir-entry-p m) entry)
    (run-passes (make-project-item :name "t" :modules (list m) :entry (ir-name m))
                config :until :rename)))

(defun target-names (project type)
  (let ((out '()))
    (walk-nodes (lambda (n) (when (typep n type) (push (ir-target-name n) out))) project)
    (nreverse out)))

(defparameter *names-module* "(defmodule m (:export point-3d make-thing)
  (defstruct point-3d (x-pos :f64))
  (defconst +max-size+ :i64 10)
  (defun make-thing (type self-ref) (declare (type :i64 type self-ref) (values :i64))
    (let ((x type)) (let ((x (+ x self-ref))) x))))")

(test role-conventions
  (let ((p (renamed *names-module* *rust-like*)))
    (is (equal '("Point3d" "MAX_SIZE" "make_thing") (mapcar #'ir-target-name (ir-items (first (ir-modules p))))))
    (is (equal '("x_pos") (target-names p 'field-def)))))

(test reserved-words
  (is (equal '("r#type" "self_ref" "x" "x") (target-names (renamed *names-module* *rust-like*) 'var-def)))
  (is (equal '("type_" "self_ref" "x" "x_2") (target-names (renamed *names-module* *python-like*) 'var-def))))

(test self-escape-and-receiver
  (let ((p (renamed "(defmodule m (defstruct s (v :i64) (defmethod get ((me :in)) (declare (values :i64)) (dot me v)))
                     (defun f (self) (declare (type :i64 self)) (print-line (format-string \"{}\" self))))"
                    *rust-like*)))
    (is (equal '("self" "self_") (target-names p 'var-def)))))

(test private-prefix
  (let ((p (renamed *names-module* *python-like*)))
    (is (equal '("Point3d" "_MAX_SIZE" "make_thing") (mapcar #'ir-target-name (ir-items (first (ir-modules p)))))))
  (let ((p (renamed *names-module* *python-like* :entry t)))
    (is (equal "MAX_SIZE" (ir-target-name (second (ir-items (first (ir-modules p)))))))))

(test collisions
  (signals dsl-error (renamed "(defmodule m (defun foo-bar () 1) (defun foo_bar () 2))" *rust-like*))
  (signals dsl-error (renamed "(defmodule m (defstruct s (a-b :i64) (a_b :i64)))" *rust-like*)))

(test determinism
  (is (equal (target-names (renamed *names-module* *python-like*) 'var-def)
             (target-names (renamed *names-module* *python-like*) 'var-def))))
