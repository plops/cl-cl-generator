;;;; 32-resolve-env.lisp --- symbol tables, scopes, type resolution, lookups

(in-package :polyglot)

(defvar *project* nil "The project being resolved.")
(defvar *module* nil "The module being resolved.")
(defvar *module-scope* nil "Hash table name -> item visible in *module*.")
(defvar *scopes* '() "List of hash tables name -> var-def, innermost first.")
(defvar *function* nil "Function-item, method-item or lambda-expr being resolved.")

(defun find-module (name &optional (project *project*))
  (find name (ir-modules project) :key #'ir-name :test #'string=))

(defun add-scope-entry (table name item source)
  (let ((old (gethash name table)))
    (when (and old (not (eq old item)))
      (dsl-error source "name ~a is defined twice (~(~a~) and ~(~a~))"
                 name (item-kind old) (item-kind item)))
    (setf (gethash name table) item)))

(defun build-module-scope (module)
  "Own items plus the public items of all imported modules."
  (let ((table (make-hash-table :test 'equal)))
    (dolist (item (ir-items module))
      (add-scope-entry table (ir-name item) item (ir-source item)))
    (dolist (imp (ir-imports module) table)
      (let ((other (find-module imp)))
        (unless other
          (dsl-error (ir-source module) "module ~a imports unknown module ~a" (ir-name module) imp))
        (when (eq other module)
          (dsl-error (ir-source module) "module ~a imports itself" imp))
        (dolist (item (ir-items other))
          (when (eq :public (ir-visibility item))
            (add-scope-entry table (ir-name item) item (ir-source module))))))))

(defun lookup-item (name)
  (and *module-scope* (gethash name *module-scope*)))

(defun lookup-type-item (name source)
  (let ((item (lookup-item name)))
    (unless (typep item '(or struct-item interface-item))
      (dsl-error source "unknown type ~a" name))
    item))

(defun resolve-type (ty &optional source)
  "Attach the defining item to named and dyn types: (:named n item)."
  (cond ((atom ty) ty)
        ((member (car ty) '(:named :dyn))
         (let ((item (lookup-type-item (second ty) (or source ty))))
           (when (and (eq (car ty) :dyn) (not (typep item 'interface-item)))
             (dsl-error (or source ty) "dyn needs an interface, ~a is not one" (second ty)))
           (list (car ty) (second ty) item)))
        ((eq (car ty) :raw) ty)
        ((eq (car ty) :array) (list :array (resolve-type (second ty) source) (third ty)))
        ((member (car ty) '(:ref :mut-ref :view))
         (list (car ty) (resolve-type (second ty) source) (third ty)))
        ((eq (car ty) :fn)
         (list :fn (mapcar (lambda (x) (resolve-type x source)) (second ty))
               (resolve-type (third ty) source)))
        (t (cons (car ty) (mapcar (lambda (x) (resolve-type x source)) (cdr ty))))))

(defun type-item (ty)
  "The struct or interface item of a resolved named/dyn type."
  (and (consp ty) (member (car ty) '(:named :dyn)) (third ty)))

(defun strip-indirection (ty)
  "Look through box, ref, mut-ref and optional for member access."
  (if (and (consp ty) (member (car ty) '(:box :ref :mut-ref)))
      (strip-indirection (second ty))
      ty))

;;; scopes

(defmacro with-scope (() &body body)
  `(let ((*scopes* (cons (make-hash-table :test 'equal) *scopes*)))
     ,@body))

(defun bind-var (var)
  (setf (gethash (ir-name var) (first *scopes*)) var))

(defun lookup-var (name)
  (loop for table in *scopes*
        for v = (gethash name table)
        when v return v))

;;; members

(defun struct-base-chain (item)
  "ITEM and its base classes, most derived first."
  (loop for s = item then (ir-base-item s)
        while s collect s))

(defun interface-closure (items)
  "INTERFACES and everything they extend, without duplicates."
  (let ((out '()))
    (labels ((walk (i)
               (unless (member i out)
                 (push i out)
                 (mapc #'walk (ir-extends-items i)))))
      (mapc #'walk items))
    (nreverse out)))

(defun type-interfaces (item)
  "All interfaces implemented by the struct ITEM (including base classes)."
  (interface-closure (loop for s in (struct-base-chain item)
                           append (ir-implements-items s))))

(defun find-field (item name)
  (loop for s in (struct-base-chain item)
        for f = (find name (ir-fields s) :key #'ir-name :test #'string=)
        when f return f))

(defun all-fields (item)
  "Fields of ITEM including inherited ones, base fields first."
  (loop for s in (reverse (struct-base-chain item)) append (ir-fields s)))

(defun lookup-method (ty name)
  "Method NAME applicable to the resolved type TY, or NIL."
  (let ((item (type-item (strip-indirection ty))))
    (typecase item
      (struct-item
       (or (loop for s in (struct-base-chain item)
                 for m = (find name (ir-methods s) :key #'ir-name :test #'string=)
                 when m return m)
           (find-interface-method (type-interfaces item) name)))
      (interface-item (find-interface-method (interface-closure (list item)) name)))))

(defun find-interface-method (interfaces name)
  (loop for i in interfaces
        for m = (find name (ir-methods i) :key #'ir-name :test #'string=)
        when m return m))
