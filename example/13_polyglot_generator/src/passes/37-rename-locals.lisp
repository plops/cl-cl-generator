;;;; 37-rename-locals.lisp --- names of parameters and locals, shadowing policy

(in-package :polyglot)

(defvar *visible-names* '() "Target names visible in the current function, innermost first.")
(defvar *function-names* nil "Hash table of all target names used in the current function.")

(defun fresh-local-name (base)
  (loop for i from 2
        for candidate = (format nil "~a_~d" base i)
        unless (or (member candidate *visible-names* :test #'string=)
                   (gethash candidate *function-names*))
        return candidate))

(defun name-local (var)
  (let* ((base (if (and (ir-receiver-p var) (config-get :receiver-name))
                   (config-get :receiver-name)
                   (target-name-for (ir-name var) :variable)))
         (name (if (and (eq :rename (config-get :shadowing :allow))
                        (member base *visible-names* :test #'string=))
                   (fresh-local-name base)
                   base)))
    (setf (ir-target-name var) name
          (gethash name *function-names*) t)
    (push name *visible-names*)))

(defmacro with-local-scope (() &body body)
  `(let ((*visible-names* *visible-names*)) ,@body))

(defgeneric rename-node (n)
  (:documentation "Assign target names to the bindings in N, respecting scopes."))

(defun rename-list (nodes) (mapc #'rename-node nodes))

(defun rename-scoped (nodes) (with-local-scope () (rename-list nodes)))

(defmethod rename-node ((n node))
  (rename-list (node-children n)))

(defmethod rename-node ((n block-stmt))
  (if (ir-scope n) (rename-scoped (ir-stmts n)) (rename-list (ir-stmts n))))

(defmethod rename-node ((n decl-stmt))
  (when (ir-init n) (rename-node (ir-init n)))
  (name-local (ir-var n)))

(defmethod rename-node ((n block-expr))
  (with-local-scope ()
    (rename-list (ir-stmts n))
    (rename-node (ir-value n))))

(defmethod rename-node ((n if-stmt))
  (rename-node (ir-test n))
  (rename-scoped (ir-then n))
  (rename-scoped (ir-else n)))

(defmethod rename-node ((n while-stmt))
  (rename-node (ir-test n))
  (rename-scoped (ir-body n)))

(defmethod rename-node ((n for-range-stmt))
  (rename-node (ir-start n))
  (rename-node (ir-end n))
  (with-local-scope ()
    (name-local (ir-var n))
    (rename-scoped (ir-body n))))

(defmethod rename-node ((n for-each-stmt))
  (rename-node (ir-seq n))
  (with-local-scope ()
    (name-local (ir-var n))
    (rename-scoped (ir-body n))))

(defmethod rename-node ((n if-let-stmt))
  (rename-node (ir-expr n))
  (with-local-scope ()
    (name-local (ir-var n))
    (rename-scoped (ir-then n)))
  (rename-scoped (ir-else n)))

(defmethod rename-node ((n lambda-expr))
  (with-local-scope ()
    (mapc #'name-local (ir-params n))
    (rename-scoped (ir-body n))))

(defun rename-function (fn)
  (let ((*visible-names* '())
        (*function-names* (make-hash-table :test 'equal)))
    (mapc #'name-local (ir-params fn))
    (check-collisions (ir-params fn) "parameter")
    (rename-scoped (ir-body fn))))

(defun rename-project (project)
  (dolist (m (ir-modules project))
    (rename-items m))
  (dolist (m (ir-modules project) project)
    (dolist (item (ir-items m))
      (typecase item
        ((or function-item extern-item) (rename-function item))
        ((or struct-item interface-item) (mapc #'rename-function (ir-methods item)))
        (const-item (rename-node (ir-value item)))))))

(define-pass :rename (:order 70) (project)
             "Assign target names to all definitions according to the backend config."
             (rename-project project))
