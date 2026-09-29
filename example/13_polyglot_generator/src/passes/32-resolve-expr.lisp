;;;; 32-resolve-expr.lisp --- resolve expressions: bindings, calls, light types

(in-package :polyglot)

(defgeneric resolve-expr (e)
  (:documentation "Resolve names in E, set (ir-ty E) and return E or its replacement."))

(defmethod resolve-expr ((e lit-expr))
  (setf (ir-ty e) (ecase (ir-kind e)
                    (:int :i64) (:float :f64) (:string :string) (:char :char)
                    (:bool :bool) (:nil :nil)))
  e)

(defmethod resolve-expr ((e var-expr))
  (let ((b (or (lookup-var (ir-name e)) (lookup-item (ir-name e)))))
    (setf (ir-binding e) b
          (ir-ty e) (typecase b
                      (var-def (ir-ty b))
                      (const-item (ir-ty b))
                      (function-item (list :fn (mapcar #'ir-ty (ir-params b)) (ir-ret b)))
                      (t (dsl-error (ir-source e) "unknown variable ~a" (ir-name e)))))
    e))

(defun arithmetic-result (e args)
  (let ((ty (ir-ty (first args))))
    (when (and (eq (ir-op e) :div) (known-type-p ty) (not (float-type-p ty)))
      (dsl-error (ir-source e) "/ is only defined for floats; use truncate or floor"))
    ty))

(defmethod resolve-expr ((e op-expr))
  (let ((args (unify-numeric-operands (mapcar #'resolve-expr (ir-args e)))))
    (setf (ir-args e) args
          (ir-ty e) (case (ir-op e)
                      ((:eq :ne :lt :le :gt :ge :and :or :not) :bool)
                      ((:bitand :bitor :bitxor :bitnot :shl :shr) (ir-ty (first args)))
                      (t (arithmetic-result e args))))
    e))

(defun resolve-args-against (form args params)
  (unless (= (length args) (length params))
    (dsl-error form "wrong number of arguments: expected ~d, got ~d"
               (length params) (length args)))
  (loop for a in args
        for p in params
        unless (box-deref-arg-p a p)
        do (coerce-expr a (ir-ty p) (format nil "argument ~a" (ir-name p))))
  args)

(defun box-deref-arg-p (arg param)
  "A (box T) argument for an :in parameter of type T is borrowed through the box."
  (and (eq :box (type-head (ir-ty arg)))
       (eq :in (ir-mode param))
       (not (eq :box (type-head (ir-ty param))))
       (type-compatible-p (second (ir-ty arg)) (ir-ty param))))

(defun make-method-call (e method)
  (let ((args (ir-args e)))
    (make-method-call-expr :name (ir-name e) :receiver (first args)
                           :args (resolve-args-against (ir-source e) (rest args)
                                                       (rest (ir-params method)))
                           :target method :ty (ir-ret method) :source (ir-source e))))

(defun resolve-item-call (e item)
  (resolve-args-against (ir-source e) (ir-args e) (ir-params item))
  (setf (ir-target e) item
        (ir-call-kind e) (if (typep item 'extern-item) :extern :function)
        (ir-ty e) (ir-ret item))
  e)

(defmethod resolve-expr ((e call-expr))
  (let* ((name (ir-name e))
         (var (lookup-var name)))
    (when (and var (eq :fn (type-head (ir-ty var))))
      (return-from resolve-expr
        (resolve-expr (make-funcall-expr :fn (make-var-expr :name name :source name)
                                         :args (ir-args e) :source (ir-source e)))))
    (setf (ir-args e) (mapcar #'resolve-expr (ir-args e)))
    (let ((method (and (ir-args e) (lookup-method (ir-ty (first (ir-args e))) name)))
          (item (lookup-item name)))
      (cond (method (make-method-call e method))
            ((typep item '(or function-item extern-item)) (resolve-item-call e item))
            ((find-intrinsic name) (resolve-intrinsic-call e (find-intrinsic name)))
            (t (dsl-error (ir-source e) "unknown function ~a" name))))))

(defmethod resolve-expr ((e method-call-expr))
  ;; re-resolution after composition: method calls are rebuilt from scratch
  (resolve-expr (make-call-expr :name (ir-name e) :args (cons (ir-receiver e) (ir-args e))
                                :source (ir-source e))))

(defmethod resolve-expr ((e field-expr))
  (let* ((object (resolve-expr (ir-object e)))
         (item (type-item (strip-indirection (ir-ty object))))
         (field (and (typep item 'struct-item) (find-field item (ir-name e)))))
    (when (and (known-type-p (ir-ty object)) (null field))
      (dsl-error (ir-source e) "~a has no field ~a" (type-string (ir-ty object)) (ir-name e)))
    (setf (ir-object e) object
          (ir-target e) field
          (ir-ty e) (if field (ir-ty field) :unknown))
    e))

(defmethod resolve-expr ((e aref-expr))
  (let ((object (resolve-expr (ir-object e))))
    (setf (ir-object e) object
          (ir-index e) (coerce-expr (resolve-expr (ir-index e)) :i64 "index")
          (ir-ty e) (or (element-type (ir-ty object))
                        (if (known-type-p (ir-ty object))
                            (dsl-error (ir-source e) "aref needs a vec or array, got ~a"
                                       (type-string (ir-ty object)))
                            :unknown)))
    e))

(defmethod resolve-expr ((e make-expr))
  (let ((item (lookup-item (ir-type-name e))))
    (unless (typep item 'struct-item)
      (dsl-error (ir-source e) "make-~a: ~a is not a struct or class" (ir-type-name e) (ir-type-name e)))
    (let ((seen '()))
      (dolist (init (ir-inits e))
        (let ((field (find-field item (ir-name init))))
          (unless field
            (dsl-error (ir-source e) "~a has no field ~a" (ir-name item) (ir-name init)))
          (when (member (ir-name init) seen :test #'string=)
            (dsl-error (ir-source e) "field ~a initialized twice" (ir-name init)))
          (push (ir-name init) seen)
          (setf (ir-value init) (coerce-expr (resolve-expr (ir-value init)) (ir-ty field)
                                             (format nil "field ~a" (ir-name init)))))))
    (setf (ir-target e) item
          (ir-ty e) (list :named (ir-name item) item))
    e))
