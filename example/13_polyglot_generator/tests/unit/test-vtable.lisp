;;;; test-vtable.lisp --- tests of the vtable pass

(in-package :polyglot.tests)

(def-suite :polyglot.unit.vtable :in :polyglot.unit)
(in-suite :polyglot.unit.vtable)

(defparameter *widgets* "(defmodule m
  (defclass widget () (x :f64 0d0)
    (defmethod area ((self :in)) (declare (values :f64) (virtual)) 0d0)
    (defmethod describe ((self :in)) (declare (values :string))
      (format-string \"area={:.2f}\" (area self))))
  (defclass button (widget) (label :string \"\")
    (defmethod area ((self :in)) (declare (values :f64) (override)) (+ 1d0 (call-super))))
  (defclass fancy-button (button) (glow :f64 1d0)
    (defmethod area ((self :in)) (declare (values :f64) (override)) (* 2d0 (call-super)))))")

(defun vt-project (string)
  (let ((m (parse-module-form (read-dsl string))))
    (run-passes (make-project-item :name "t" :modules (list m) :entry (ir-name m))
                (list :backend :test) :until :vtable)))

(defun vt-item (p name)
  (find name (ir-items (first (ir-modules p))) :key #'ir-name :test #'string=))

(test three-levels
  (let* ((p (vt-project *widgets*))
         (w (vt-item p "widget")) (b (vt-item p "button")) (f (vt-item p "fancy-button")))
    (is (equal '("area") (mapcar #'car (ir-vtable f))))
    (is (eq (first (ir-methods f)) (cdr (first (ir-vtable f)))))
    (is (eq (first (ir-methods b)) (ir-super-target (first (ir-methods f)))))
    (is (eq (first (ir-methods w)) (ir-super-target (first (ir-methods b)))))
    (is (not (method-virtual-p (second (ir-methods w)))))
    (let ((supers '()))
      (walk-nodes (lambda (n) (when (typep n 'super-expr) (push (ir-target n) supers))) f)
      (is (equal (list (first (ir-methods b))) supers)))))

(test override-errors
  (signals dsl-error
           (vt-project "(defmodule m (defclass a () (defmethod f ((self :in)) (declare (values :i64)) 1))
                  (defclass b (a) (defmethod f ((self :in)) (declare (values :i64) (override)) 2)))"))
  (signals dsl-error
           (vt-project "(defmodule m (defclass a () (defmethod g ((self :in)) (declare (values :i64) (virtual)) 1))
                  (defclass b (a) (defmethod f ((self :in)) (declare (values :i64) (override)) 2)))"))
  (signals dsl-error
           (vt-project "(defmodule m (defclass a () (defmethod f ((self :in)) (declare (values :i64) (virtual)) 1))
                  (defclass b (a) (defmethod f ((self :in)) (declare (values :i64)) 2)))")))

(test interface-defaults-and-missing-methods
  (let* ((p (vt-project "(defmodule m
             (definterface shape
               (defmethod area ((s :in)) (declare (values :f64)))
               (defmethod twice ((s :in)) (declare (values :f64)) (* 2d0 (area s))))
             (defstruct sq (:implements shape) (a :f64)
               (defmethod area ((self :in)) (* (dot self a) (dot self a)))))"))
         (sq (vt-item p "sq")))
    (is (equal '("area" "twice") (mapcar #'car (ir-vtable sq))))
    (is (eq (vt-item p "shape") (ir-owner-item (cdr (second (ir-vtable sq))))))
    (is (method-virtual-p (first (ir-methods sq)))))
  (signals dsl-error
           (vt-project "(defmodule m (definterface shape (defmethod area ((s :in)) (declare (values :f64))))
                  (defstruct sq (:implements shape) (a :f64)))")))

(test abstract-class-instantiation
  (signals dsl-error
           (vt-project "(defmodule m (defclass a () (defmethod f ((self :in)) (declare (values :i64) (abstract))))
                  (defun g () (make-a)))")))
