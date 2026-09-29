;;;; test-composition.lisp --- inheritance->composition on IR level

(in-package :polyglot.tests)

(def-suite :polyglot.unit.composition :in :polyglot.unit)
(in-suite :polyglot.unit.composition)

(defparameter *compose-config*
  (list :backend :test-compose :capabilities '(:implementation-inheritance nil :block-expressions t)))

(defun composed (string)
  (let ((m (parse-module-form (read-dsl string))))
    (setf (ir-entry-p m) t)
    (first (ir-modules (run-passes (make-project-item :name "t" :modules (list m) :entry (ir-name m))
                                   *compose-config* :until :re-mutability)))))

(defun item-names (module type)
  (mapcar #'ir-name (remove-if-not (lambda (i) (typep i type)) (ir-items module))))

(test hierarchy-becomes-interfaces-structs-and-functions
  (let* ((m (composed *widgets*))
         (button (find "button" (ir-items m) :key #'ir-name :test #'string=)))
    (is (equal '("widget-dyn" "button-dyn" "fancy-button-dyn") (item-names m 'interface-item)))
    (is (equal '("widget" "button" "fancy-button") (item-names m 'struct-item)))
    (is (subsetp '("widget-area" "widget-describe" "button-area" "fancy-button-area")
                 (item-names m 'function-item) :test #'string=))
    (is (notany #'ir-class-p (remove-if-not (lambda (i) (typep i 'struct-item)) (ir-items m))))
    (is (string= "base" (ir-name (first (ir-fields button)))))
    (is (equal '(:named "widget") (subseq (ir-ty (first (ir-fields button))) 0 2)))))

(test delegation-and-supers
  (let* ((m (composed *widgets*))
         (fancy (find "fancy-button" (ir-items m) :key #'ir-name :test #'string=))
         (area (find "area" (ir-methods fancy) :key #'ir-name :test #'string=))
         (fb-area (find "fancy-button-area" (ir-items m) :key #'ir-name :test #'string=)))
    ;; the struct delegates to the free function of its own implementation
    (is (string= "fancy-button-area" (ir-name (ir-value (first (ir-body area))))))
    ;; call-super became a call of the base free function with this
    (let ((calls (mapcar #'ir-name (collect-nodes 'call-expr fb-area))))
      (is (member "button-area" calls :test #'string=)))
    ;; the virtual method is implemented through the root interface
    (is (string= "widget-dyn" (ir-name (ir-owner-item (root-method area)))))))

(defparameter *widgets-rw* "(defmodule m
  (defclass widget () (x :f64 0d0)
    (defmethod area ((w :in)) (declare (values :f64) (virtual)) (dot w x))
    (defmethod grow ((w :inout)) (incf (dot w x))))
  (defclass button (widget) (label :string \"\"))
  (defclass fancy-button (button) (glow :f64 1d0)
    (defmethod area ((f :in)) (declare (values :f64) (override)) (* (dot f glow) (call-super)))))")

(test accessors-only-when-needed
  (let* ((m (composed *widgets-rw*))
         (bd (find "button-dyn" (ir-items m) :key #'ir-name :test #'string=))
         (wd (find "widget-dyn" (ir-items m) :key #'ir-name :test #'string=))
         (fd (find "fancy-button-dyn" (ir-items m) :key #'ir-name :test #'string=)))
    (is (equal '("widget" "widget-mut" "area") (mapcar #'ir-name (ir-methods wd))))
    (is (null (ir-methods bd)))
    (is (equal '("fancy-button") (mapcar #'ir-name (ir-methods fd))))))

(test no-hierarchy-no-change
  (let ((m (composed "(defmodule m (defstruct p (x :i64)) (defun f (a) (declare (type p a) (values :i64)) (dot a x)))")))
    (is (equal '("p") (item-names m 'struct-item)))
    (is (null (item-names m 'interface-item)))))
