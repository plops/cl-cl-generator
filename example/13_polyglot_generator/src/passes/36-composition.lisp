;;;; 36-composition.lisp --- inheritance->composition (plan.md K3 stage 2)
;;;;
;;;; For targets without implementation inheritance (Rust, Go). Every class of
;;;; a hierarchy C becomes
;;;;   - an interface C-dyn (extends B-dyn of the base B) with the accessors
;;;;     C / C-mut that are needed and the virtual methods C introduces,
;;;;   - a data struct C with the field base (the struct of B) and its own
;;;;     fields, implementing the accessors and delegating every virtual method
;;;;     to the free function of the most derived implementation,
;;;;   - one free function C-m per method, whose first parameter is
;;;;     this: (ref (dyn C-dyn)) or (mut-ref (dyn C-dyn)).
;;;; Bodies are rewritten: fields through accessors (dynamic) or base paths
;;;; (static), non-virtual calls to free functions, call-super to the free
;;;; function of the base, (box C) to (box (dyn C-dyn)).

(in-package :polyglot)

(defvar *hierarchy* '() "Classes that take part in inheritance.")
(defvar *compose-receiver* nil "Receiver var-def of the method being rewritten.")
(defvar *write-places* nil "Hash set of field-exprs that are written.")
(defvar *accessor-needs* nil "Hash table class -> list of :read/:write.")

(defun class-derived-p (item project)
  (loop for m in (ir-modules project)
        thereis (some (lambda (i) (and (typep i 'struct-item) (eq item (ir-base-item i))))
                      (ir-items m))))

(defun hierarchy-classes (project)
  (loop for m in (ir-modules project)
        append (remove-if-not (lambda (i) (and (typep i 'struct-item) (ir-class-p i)
                                               (or (ir-base-item i) (class-derived-p i project))))
                              (ir-items m))))

(defun in-hierarchy-p (item) (member item *hierarchy*))
(defun dyn-name (class) (format nil "~a-dyn" (ir-name class)))
(defun accessor-name (class write) (format nil "~a~:[~;-mut~]" (ir-name class) write))
(defun free-fn-name (class method) (format nil "~a-~a" (ir-name class) (ir-name method)))

(defun mk-var (name) (make-var-expr :name name :source (intern (string-upcase name) :polyglot)))
(defun mk-call (name args &optional source)
  (make-call-expr :name name :args args :source (or source (list (intern (string-upcase name) :polyglot)))))
(defun mk-field (object name) (make-field-expr :object object :name name :source (list 'dot name)))

(defun mark-write-chain (e)
  (loop while (typep e '(or field-expr aref-expr))
        do (when (typep e 'field-expr) (setf (gethash e *write-places*) t))
        (setf e (ir-object e))))

(defun collect-write-places (project)
  (walk-nodes (lambda (n)
                (typecase n
                  ((or assign-stmt op-assign-stmt) (mark-write-chain (ir-place n)))
                  (call-expr (cond ((intrinsic-name-is n "push") (mark-write-chain (second (ir-args n))))
                                   ((intrinsic-name-is n "map-set") (mark-write-chain (first (ir-args n))))
                                   ((member (ir-call-kind n) '(:function :extern))
                                    (loop for a in (ir-args n) for p in (ir-params (ir-target n))
                                          when (eq :inout (ir-mode p)) do (mark-write-chain a)))))
                  (method-call-expr
                   (when (eq :inout (ir-mode (method-receiver (ir-target n))))
                     (mark-write-chain (ir-receiver n)))))
                nil)
              project))

(defun compose-type (ty)
  "(box C) -> (box (dyn C-dyn)) for classes of the hierarchy, recursively."
  (cond ((not (consp ty)) ty)
        ((and (eq :box (car ty)) (eq :named (type-head (second ty))) (in-hierarchy-p (third (second ty))))
         (list :box (list :dyn (dyn-name (third (second ty))))))
        ((member (car ty) '(:named :dyn :raw)) (list (car ty) (second ty)))
        ((eq (car ty) :array) (list :array (compose-type (second ty)) (third ty)))
        ((member (car ty) '(:ref :mut-ref :view)) (list (car ty) (compose-type (second ty)) (third ty)))
        ((eq (car ty) :fn) (list :fn (mapcar #'compose-type (second ty)) (compose-type (third ty))))
        (t (cons (car ty) (mapcar #'compose-type (cdr ty))))))

(defun compose-param-type (var)
  "A parameter of a class type becomes a borrow of the dyn interface."
  (let ((ty (ir-declared-ty var)))
    (if (and (eq :param (ir-kind var)) (named-type-p ty) (in-hierarchy-p (third ty)))
        (let ((dyn (list :dyn (dyn-name (third ty)))))
          (ecase (ir-mode var)
            (:in (values (list :ref dyn nil) :in))
            (:inout (values (list :mut-ref dyn nil) :in))
            (:sink (values (list :box dyn) :sink))))
        (values (compose-type ty) (ir-mode var)))))

(defun polymorphic-handle-p (e)
  "E refers to a class value through box/ref (dynamic type), or is the receiver."
  (or (and (typep e 'var-expr) *compose-receiver* (eq (ir-binding e) *compose-receiver*))
      (and (member (type-head (ir-ty e)) '(:box :ref :mut-ref))
           (in-hierarchy-p (type-item (strip-indirection (ir-ty e)))))
      (and (typep e 'var-expr) (typep (ir-binding e) 'var-def) (eq :param (ir-kind (ir-binding e)))
           (in-hierarchy-p (type-item (ir-ty e))))))

(defun base-path (object from to)
  "OBJECT (a value of class FROM) navigated to its part of class TO."
  (loop for c = from then (ir-base-item c)
        until (or (null c) (eq c to))
        do (setf object (mk-field object "base")))
  object)

(defun note-accessor (class write)
  (pushnew (if write :write :read) (gethash class *accessor-needs*)))
