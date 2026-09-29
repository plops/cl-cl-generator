;;;; test-resolve.lisp --- tests of the resolve pass

(in-package :polyglot.tests)

(def-suite :polyglot.unit.resolve :in :polyglot.unit)
(in-suite :polyglot.unit.resolve)

(defun resolved (&rest module-strings)
  "Parse MODULE-STRINGS into a project (last one is the entry) and resolve it."
  (let* ((modules (mapcar (lambda (s) (parse-module-form (read-dsl s))) module-strings))
         (p (make-project-item :name "t" :modules modules
                               :entry (ir-name (car (last modules))))))
    (run-passes p (list :backend :test) :until :resolve)))

(defun module-fn (project module-name fn-name)
  (let ((m (find module-name (ir-modules project) :key #'ir-name :test #'string=)))
    (find fn-name (ir-items m) :key #'ir-name :test #'string=)))

(defun collect-nodes (type node)
  (let ((out '()))
    (walk-nodes (lambda (n) (when (typep n type) (push n out))) node)
    (nreverse out)))

(test shadowing-binds-innermost
  (let* ((p (resolved "(defmodule m (defun f (x) (declare (type :i64 x) (values :i64))
                          (let ((x (+ x 1))) (let ((x (* x 2))) x))))"))
         (fn (module-fn p "m" "f"))
         (decls (collect-nodes 'decl-stmt fn))
         (refs (collect-nodes 'var-expr fn)))
    ;; refs: x in (+ x 1) -> param, x in (* x 2) -> first let, final x -> second let
    (is (eq (first (ir-params fn)) (ir-binding (first refs))))
    (is (eq (ir-var (first decls)) (ir-binding (second refs))))
    (is (eq (ir-var (second decls)) (ir-binding (third refs))))
    (is (eq :i64 (ir-ty (third refs))))))

(test unknown-names
  (signals dsl-error (resolved "(defmodule m (defun f () (print-line y)))"))
  (signals dsl-error (resolved "(defmodule m (defun f () (frobnicate 1)))"))
  (signals dsl-error (resolved "(defmodule m (defun f (p) (declare (type nope p)) p))")))

(test light-types
  (let* ((p (resolved "(defmodule m
                         (defstruct point (x :f64) (y :f64))
                         (defun f (v) (declare (type (vec point) v) (values :f64))
                           (let ((s 0d0)) (dolist (q v) (incf s (* 2 (dot q x)))) s)))"))
         (fn (module-fn p "m" "f"))
         (mul (find :mul (collect-nodes 'op-expr fn) :key #'ir-op)))
    (is (eq :f64 (ir-ty mul)))
    (is (eq :float (ir-kind (first (ir-args mul)))))))

(test method-resolution
  (let* ((p (resolved "(defmodule m
                         (definterface shape
                           (defmethod area ((s :in)) (declare (values :f64)))
                           (defmethod twice ((s :in)) (declare (values :f64)) (* 2d0 (area s))))
                         (defstruct circle (:implements shape) (r :f64))
                         (defmethod area ((c circle :in)) (* (dot c r) (dot c r)))
                         (defun f (c b) (declare (type circle c) (type (box (dyn shape)) b)
                                                 (values :f64))
                           (+ (area c) (twice c) (area b))))"))
         (calls (collect-nodes 'method-call-expr (module-fn p "m" "f"))))
    (is (= 3 (length calls)))
    (is (string= "circle" (ir-owner (ir-target (first calls)))))
    (is (string= "shape" (ir-owner (ir-target (second calls)))))
    (is (eq :f64 (ir-ty (third calls))))))

(test imports-between-modules
  (let* ((p (resolved "(defmodule lib (:export point norm2)
                         (defstruct point (x :f64))
                         (defun norm2 (p) (declare (type point p) (values :f64)) (* (dot p x) (dot p x)))
                         (defun hidden () (declare (values :i64)) 1))"
                      "(defmodule app (:import lib)
                         (defun main () (norm2 (make-point :x 2d0))))"))
         (call (first (collect-nodes 'call-expr (module-fn p "app" "main")))))
    (is (eq :function (ir-call-kind call)))
    (is (string= "lib" (ir-name (ir-module (ir-target call))))))
  (signals dsl-error
           (resolved "(defmodule lib (:export f) (defun f () 1) (defun hidden () 2))"
                     "(defmodule app (:import lib) (defun main () (hidden)))"))
  (signals dsl-error (resolved "(defmodule app (:import nowhere) (defun main () 1))")))

(test type-errors
  (signals dsl-error (resolved "(defmodule m (defun f (a) (declare (type :i64 a) (values :i64)) (/ a 2)))"))
  (signals dsl-error (resolved "(defmodule m (defun f () (declare (values :i64)) \"no\"))"))
  (signals dsl-error (resolved "(defmodule m (defun f () (return 1)))"))
  (signals dsl-error (resolved "(defmodule m (defstruct p (x :i64)) (defun f () (make-p :y 1)))")))
