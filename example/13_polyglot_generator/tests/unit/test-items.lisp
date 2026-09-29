;;;; test-items.lisp --- tests of src/frontend/24-items.lisp and 24-modules.lisp

(in-package :polyglot.tests)

(def-suite :polyglot.unit.items :in :polyglot.unit)
(in-suite :polyglot.unit.items)

(defparameter *all-items-module* "
(defmodule geometry (:export point distance shape circle +origin-x+ c-sqrt)
                    (:import util (:std :math))
  (defconst +origin-x+ :f64 0d0)
  (defstruct point (x :f64 0d0) (y :f64)
    (defmethod norm ((self :in)) (declare (values :f64)) (sqrt (+ (* (dot self x) (dot self x)) 1d0))))
  (defun distance (a b)
    \"Euclidean distance.\"
    (declare (type point a b) (values :f64) (pure))
    (sqrt (+ (square (- (dot a x) (dot b x))) (square (- (dot a y) (dot b y))))))
  (defun square (v) (declare (type :f64 v) (values :f64)) (* v v))
  (definterface shape
    (defmethod area ((s :in)) (declare (values :f64)))
    (defmethod describe ((s :in)) (declare (values :string)) (format-string \"{:.2f}\" (area s))))
  (defstruct circle (:implements shape) (r :f64))
  (defmethod area ((c circle :in)) (declare (values :f64)) (* 3d0 (dot c r)))
  (defclass widget () (w :f64)
    (defmethod size ((self :inout)) (declare (values :f64) (virtual)) (dot self w)))
  (defclass button (widget) (label :string \"\"))
  (defextern c-sqrt ((x :f64)) :f64 (:cpp \"std::sqrt\" :includes (\"<cmath>\")) (:python \"math.sqrt\")))")

(defun find-item (module name)
  (find name (ir-items module) :key #'ir-name :test #'string=))

(test module-with-all-items
  (let ((m (parse-module-form (read-dsl *all-items-module*))))
    (is (string= "geometry" (ir-name m)))
    (is (equal '("util") (ir-imports m)))
    (is (equal '(:math) (ir-std-imports m)))
    (is (= 9 (length (ir-items m))))
    (is (eq :public (ir-visibility (find-item m "distance"))))
    (is (eq :private (ir-visibility (find-item m "square"))))
    (is (equal '(:pure) (ir-flags (find-item m "distance"))))
    (is (string= "Euclidean distance." (ir-doc (find-item m "distance"))))
    (is (typep (find-item m "c-sqrt") 'extern-item))
    (is (typep (find-item m "+origin-x+") 'const-item))))

(test receiver-normalization
  (let* ((m (parse-module-form (read-dsl *all-items-module*)))
         (circle (find-item m "circle"))
         (area (first (ir-methods circle)))
         (recv (method-receiver area)))
    (is (string= "area" (ir-name area)))
    (is (string= "c" (ir-name recv)))
    (is (ir-receiver-p recv))
    (is (eq :in (ir-mode recv)))
    (is (equal '(:named "circle") (ir-declared-ty recv)))
    (is (equal '("shape") (ir-implements circle)))))

(test interfaces-and-classes
  (let* ((m (parse-module-form (read-dsl *all-items-module*)))
         (shape (find-item m "shape"))
         (button (find-item m "button"))
         (widget (find-item m "widget")))
    (is (member :abstract (ir-flags (first (ir-methods shape)))))
    (is (not (member :abstract (ir-flags (second (ir-methods shape))))))
    (is (string= "widget" (ir-base button)))
    (is (ir-class-p button))
    (is (eq :inout (ir-mode (method-receiver (first (ir-methods widget))))))
    (is (member :virtual (ir-flags (first (ir-methods widget)))))))

(test item-errors
  (signals dsl-error (parse-module-form (read-dsl "(defmodule m (:export nope) (defun f () 1))")))
  (signals dsl-error (parse-module-form (read-dsl "(defmodule m (defmethod f ((x other :in)) 1))")))
  (signals dsl-error (parse-module-form (read-dsl "(defmodule m (frob x))")))
  (signals dsl-error (parse-module-form (read-dsl "(defmodule m (defun f (x) x))")))
  (signals unsupported-construct
           (parse-module-form (read-dsl "(defmodule m (defclass c (a b)))")))
  (signals dsl-error
           (parse-module-form (read-dsl "(defmodule m (defun f () (declare (virtual)) 1))"))))

(test projects
  (register-module (read-dsl "(defmodule test-lib (:export f) (defun f () (declare (values :i64)) 1))"))
  (register-module (read-dsl "(defmodule test-app (:import test-lib) (defun main () (f)))"))
  (let ((p (parse-project (make-project-spec :name 'demo :modules '(test-lib test-app)
                                             :entry 'test-app))))
    (is (= 2 (length (ir-modules p))))
    (is (ir-entry-p (second (ir-modules p))))
    (is (not (ir-entry-p (first (ir-modules p))))))
  (signals dsl-error (parse-project (make-project-spec :name 'demo :modules '(no-such-module))))
  (signals dsl-error (parse-project (make-project-spec :name 'demo :modules '(test-lib)
                                                       :entry 'test-app))))
