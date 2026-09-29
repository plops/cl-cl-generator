;;;; 32-resolve-stmt.lisp --- resolve statements and items; the resolve pass

(in-package :polyglot)

(defgeneric resolve-stmt (s)
  (:documentation "Resolve S in the current scope and return it (or a replacement)."))

(defun resolve-stmts (stmts)
  (mapcar #'resolve-stmt stmts))

(defun resolve-scoped (stmts)
  (with-scope () (resolve-stmts stmts)))

(defmethod resolve-stmt ((s block-stmt))
  (setf (ir-stmts s) (if (ir-scope s) (resolve-scoped (ir-stmts s)) (resolve-stmts (ir-stmts s))))
  s)

(defmethod resolve-stmt ((s decl-stmt))
  (let* ((var (ir-var s))
         (declared (and (ir-declared-ty var) (resolve-type (ir-declared-ty var) (ir-source s))))
         (init (and (ir-init s) (resolve-expr (ir-init s)))))
    (when init (coerce-expr init declared (format nil "initial value of ~a" (ir-name var))))
    (setf (ir-init s) init
          (ir-declared-ty var) declared
          (ir-ty var) (cond (declared declared)
                            (init (ir-ty init))
                            (t (dsl-error (ir-source s) "~a needs a type or an initial value"
                                          (ir-name var)))))
    (bind-var var)
    s))

(defun resolve-assignment (s)
  (setf (ir-place s) (resolve-expr (ir-place s))
        (ir-value s) (coerce-expr (resolve-expr (ir-value s)) (ir-ty (ir-place s)) "assigned value"))
  s)

(defmethod resolve-stmt ((s assign-stmt)) (resolve-assignment s))
(defmethod resolve-stmt ((s op-assign-stmt)) (resolve-assignment s))

(defmethod resolve-stmt ((s if-stmt))
  (setf (ir-test s) (coerce-expr (resolve-expr (ir-test s)) :bool "if test")
        (ir-then s) (resolve-scoped (ir-then s))
        (ir-else s) (resolve-scoped (ir-else s)))
  s)

(defmethod resolve-stmt ((s while-stmt))
  (setf (ir-test s) (coerce-expr (resolve-expr (ir-test s)) :bool "while test")
        (ir-body s) (resolve-scoped (ir-body s)))
  s)

(defmethod resolve-stmt ((s for-range-stmt))
  (setf (ir-start s) (coerce-expr (resolve-expr (ir-start s)) :i64 "loop start")
        (ir-end s) (coerce-expr (resolve-expr (ir-end s)) :i64 "loop end"))
  (setf (ir-ty (ir-var s)) :i64)
  (with-scope ()
    (bind-var (ir-var s))
    (setf (ir-body s) (resolve-scoped (ir-body s))))
  s)

(defmethod resolve-stmt ((s for-each-stmt))
  (let* ((seq (resolve-expr (ir-seq s)))
         (elem (element-type (ir-ty seq))))
    (when (and (null elem) (known-type-p (ir-ty seq)))
      (dsl-error (ir-source s) "dolist needs a vec or array, got ~a" (type-string (ir-ty seq))))
    (setf (ir-seq s) seq
          (ir-ty (ir-var s)) (or elem :unknown))
    (with-scope ()
      (bind-var (ir-var s))
      (setf (ir-body s) (resolve-scoped (ir-body s))))
    s))

(defun function-ret (fn)
  (if fn (ir-ret fn) :void))

(defmethod resolve-stmt ((s return-stmt))
  (let ((ret (function-ret *function*)))
    (cond ((and (eq ret :void) (ir-value s))
           (dsl-error (ir-source s) "return with a value in a function without (values T)"))
          ((and (not (eq ret :void)) (null (ir-value s)))
           (dsl-error (ir-source s) "return without a value in a function returning ~a"
                      (type-string ret))))
    (when (ir-value s)
      (setf (ir-value s) (coerce-expr (resolve-expr (ir-value s)) ret "return value")))
    s))

(defmethod resolve-stmt ((s expr-stmt))
  (setf (ir-expr s) (resolve-expr (ir-expr s)))
  s)

(defmethod resolve-stmt ((s if-let-stmt))
  (let* ((e (resolve-expr (ir-expr s)))
         (ty (ir-ty e)))
    (unless (or (eq :optional (type-head ty)) (not (known-type-p ty)))
      (dsl-error (ir-source s) "if-let needs an optional value, got ~a" (type-string ty)))
    (setf (ir-expr s) e
          (ir-ty (ir-var s)) (if (known-type-p ty) (second ty) :unknown))
    (with-scope ()
      (bind-var (ir-var s))
      (setf (ir-then s) (resolve-scoped (ir-then s))))
    (setf (ir-else s) (resolve-scoped (ir-else s)))
    s))

(defmethod resolve-stmt ((s stmt))
  ;; break, continue, comment, raw, target-form: nothing to resolve
  s)
