;;;; items.lisp --- CL backend: defun, defclass, defgeneric/defmethod, constants

(in-package :polyglot)

(defvar *cl-generics* nil "Generic function symbols already defined in the current module.")
(defvar *cl-clone-used* nil "True when the project clones non-copy values.")

(defun cl-doc (item)
  (when (ir-doc item) (list (ir-doc item))))

(defun cl-defun (fn)
  (let ((name (item-sym fn)))
    `(defun ,name ,(mapcar #'local-sym (ir-params fn))
       ,@(cl-doc fn)
       ,@(cl-function-body (ir-body fn) :block name))))

(defun cl-defgeneric (method)
  "DEFGENERIC for a root METHOD, once per module and name."
  (let ((sym (generic-sym method)))
    (unless (member sym *cl-generics*)
      (push sym *cl-generics*)
      (list `(defgeneric ,sym ,(mapcar #'local-sym (ir-params method))
               ,@(when (ir-doc method) `((:documentation ,(ir-doc method)))))))))

(defun cl-defmethod (method owner)
  (let* ((params (ir-params method))
         (recv (first params))
         (sym (generic-sym method)))
    `(defmethod ,sym ((,(local-sym recv) ,(item-sym owner)) ,@(mapcar #'local-sym (rest params)))
       ,@(cl-doc method)
       ,@(cl-function-body (ir-body method) :block sym))))

(defun cl-method-forms (owner)
  (loop for m in (ir-methods owner)
        append (append (unless (ir-super-target m) (cl-defgeneric m))
                       (unless (function-flag-p m :abstract) (list (cl-defmethod m owner))))))

(defun cl-slot (field)
  `(,(module-sym (ir-module (ir-owner field)) (ir-target-name field))
     :initarg ,(field-keyword field)
     :initform ,(if (ir-default field) (cl-form (ir-default field)) (cl-zero-value (ir-ty field)))
     :accessor ,(accessor-sym field)))

(defun cl-clone-method (item)
  (let ((x (local-sym "pg-original")))
    `(defmethod ,(rt-sym "pg-clone") ((,x ,(item-sym item)))
       (make-instance ',(item-sym item)
                      ,@(loop for f in (all-fields item)
                              append (list (field-keyword f)
                                           `(,(rt-sym "pg-clone") (,(accessor-sym f) ,x))))))))

(defun cl-defclass (item)
  (let ((supers (append (when (ir-base-item item) (list (item-sym (ir-base-item item))))
                        (mapcar #'item-sym (ir-implements-items item)))))
    (append (list `(defclass ,(item-sym item) ,supers
                     ,(mapcar #'cl-slot (ir-fields item))
                     ,@(when (ir-doc item) `((:documentation ,(ir-doc item))))))
            (when *cl-clone-used* (list (cl-clone-method item)))
            (cl-method-forms item))))

(defun cl-definterface (item)
  (append (list `(defclass ,(item-sym item) ,(mapcar #'item-sym (ir-extends-items item)) ()
                   ,@(when (ir-doc item) `((:documentation ,(ir-doc item))))))
          (cl-method-forms item)))

(defun cl-item-forms (item)
  (etypecase item
    (method-item nil)
    (function-item (list (cl-defun item)))
    (struct-item (cl-defclass item))
    (interface-item (cl-definterface item))
    (const-item (list `(defparameter ,(item-sym item) ,(cl-form (ir-value item)))))
    (extern-item nil)))

(defun cl-exported-symbols (module)
  "Symbols of the public items of MODULE, with accessors and generic functions."
  (loop for item in (ir-items module)
        when (eq :public (ir-visibility item))
        append (typecase item
                 (extern-item nil)
                 ((or struct-item interface-item)
                  (append (list (item-sym item))
                          (when (typep item 'struct-item) (mapcar #'accessor-sym (ir-fields item)))
                          (loop for m in (ir-methods item)
                                unless (ir-super-target m) collect (generic-sym m))))
                 (t (list (item-sym item))))))
