;;;; 32-resolve.lisp --- the resolve pass: items, signatures, bodies

(in-package :polyglot)

(defmacro with-module ((module) &body body)
  `(let* ((*module* ,module)
          (*module-scope* (build-module-scope *module*)))
     ,@body))

(defun resolve-struct-links (item)
  "Base class, implemented interfaces, field owners and field types."
  (when (ir-base item)
    (let ((base (lookup-item (ir-base item))))
      (unless (and (typep base 'struct-item) (ir-class-p base))
        (dsl-error (ir-source item) "base ~a of ~a is not a class" (ir-base item) (ir-name item)))
      (setf (ir-base-item item) base)))
  (setf (ir-implements-items item)
        (loop for n in (ir-implements item)
              for i = (lookup-item n)
              do (unless (typep i 'interface-item)
                   (dsl-error (ir-source item) "~a is not an interface" n))
              collect i))
  (dolist (f (ir-fields item))
    (setf (ir-owner f) item
          (ir-ty f) (resolve-type (ir-ty f) (ir-source f)))))

(defun resolve-interface-links (item)
  (setf (ir-extends-items item)
        (loop for n in (ir-extends item)
              for i = (lookup-item n)
              do (unless (typep i 'interface-item)
                   (dsl-error (ir-source item) "~a is not an interface" n))
              collect i)))

(defun item-methods (item)
  (typecase item
    ((or struct-item interface-item) (ir-methods item))))

(defun resolve-signature (fn)
  (resolve-params (ir-params fn))
  (setf (ir-ret fn) (resolve-type (ir-ret fn) (ir-source fn))))

(defun resolve-links (module)
  (dolist (item (ir-items module))
    (setf (ir-module item) module)
    (typecase item
      (struct-item (resolve-struct-links item))
      (interface-item (resolve-interface-links item))
      (const-item (setf (ir-ty item) (resolve-type (ir-ty item) (ir-source item))))
      ((or function-item extern-item) (resolve-signature item)))
    (dolist (m (item-methods item))
      (setf (ir-module m) module
            (ir-owner-item m) item)
      (resolve-signature m))))

(defun resolve-function-body (fn)
  (let ((*function* fn))
    (with-scope ()
      (mapc #'bind-var (ir-params fn))
      (setf (ir-body fn) (resolve-stmts (ir-body fn))))))

(defun resolve-bodies (module)
  (dolist (item (ir-items module))
    (typecase item
      (function-item (resolve-function-body item))
      (const-item (setf (ir-value item)
                        (coerce-expr (resolve-expr (ir-value item)) (ir-ty item) "constant")))
      (struct-item (dolist (f (ir-fields item))
                     (when (ir-default f)
                       (setf (ir-default f) (coerce-expr (resolve-expr (ir-default f)) (ir-ty f)
                                                         "field default"))))))
    (mapc #'resolve-function-body (item-methods item))))

(defun resolve-project (project)
  "Resolve all modules of PROJECT in place and return it."
  (let ((*project* project) (*scopes* '()))
    (dolist (m (ir-modules project))
      (setf (ir-project m) project))
    (dolist (m (ir-modules project)) (with-module (m) (resolve-links m)))
    (dolist (m (ir-modules project)) (with-module (m) (resolve-bodies m)))
    project))

(define-pass :resolve (:order 20) (project)
             "Scopes, symbol tables, signatures, method calls and light type inference."
             (resolve-project project))
