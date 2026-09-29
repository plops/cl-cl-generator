;;;; 32-resolve-expr2.lisp --- resolve collections, ownership, lambdas and
;;;; intrinsic calls

(in-package :polyglot)

(defmethod resolve-expr ((e vec-expr))
  (let ((elem (resolve-type (ir-elem-type e) (ir-source e))))
    (setf (ir-elem-type e) elem
          (ir-elems e) (mapcar (lambda (x) (coerce-expr (resolve-expr x) elem "vec element"))
                               (ir-elems e))
          (ir-ty e) (list :vec elem))
    e))

(defmethod resolve-expr ((e map-expr))
  (setf (ir-key-type e) (resolve-type (ir-key-type e) (ir-source e))
        (ir-value-type e) (resolve-type (ir-value-type e) (ir-source e))
        (ir-ty e) (list :map (ir-key-type e) (ir-value-type e)))
  e)

(defmethod resolve-expr ((e own-expr))
  (let* ((value (resolve-expr (ir-value e)))
         (ty (ir-ty value)))
    (setf (ir-value e) value
          (ir-ty e) (ecase (ir-kind e)
                      (:box (list :box ty))
                      (:some (list :optional ty))
                      ((:clone :move) (borrow-target ty))))
    e))

(defmethod resolve-expr ((e super-expr))
  (unless (typep *function* 'method-item)
    (dsl-error (ir-source e) "call-super outside a method"))
  (setf (ir-args e) (mapcar #'resolve-expr (ir-args e))
        (ir-method e) *function*
        (ir-ty e) (ir-ret *function*))
  (resolve-args-against (ir-source e) (ir-args e) (rest (ir-params *function*)))
  e)

(defun resolve-params (params)
  (dolist (p params)
    (unless (ir-declared-ty p)
      (dsl-error (ir-source p) "parameter ~a has no type" (ir-name p)))
    (setf (ir-declared-ty p) (resolve-type (ir-declared-ty p) (ir-source p))
          (ir-ty p) (ir-declared-ty p))))

(defmethod resolve-expr ((e lambda-expr))
  (resolve-params (ir-params e))
  (setf (ir-ret e) (resolve-type (ir-ret e) (ir-source e)))
  (let ((*function* e))
    (with-scope ()
      (mapc #'bind-var (ir-params e))
      (setf (ir-body e) (resolve-stmts (ir-body e)))))
  (setf (ir-ty e) (list :fn (mapcar #'ir-ty (ir-params e)) (ir-ret e)))
  e)

(defmethod resolve-expr ((e funcall-expr))
  (let* ((fn (resolve-expr (ir-fn e)))
         (ty (ir-ty fn)))
    (setf (ir-fn e) fn
          (ir-args e) (mapcar #'resolve-expr (ir-args e)))
    (cond ((eq :fn (type-head ty))
           (unless (= (length (second ty)) (length (ir-args e)))
             (dsl-error (ir-source e) "funcall: wrong number of arguments"))
           (loop for a in (ir-args e) for pt in (second ty) do (coerce-expr a pt "argument"))
           (setf (ir-ty e) (third ty)))
          ((known-type-p ty) (dsl-error (ir-source e) "funcall of a non-function"))
          (t (setf (ir-ty e) :unknown)))
    e))

(defmethod resolve-expr ((e if-expr))
  (setf (ir-test e) (coerce-expr (resolve-expr (ir-test e)) :bool "if test")
        (ir-then e) (resolve-expr (ir-then e))
        (ir-else e) (resolve-expr (ir-else e)))
  (unify-numeric-operands (list (ir-then e) (ir-else e)))
  (coerce-expr (ir-else e) (ir-ty (ir-then e)) "else branch")
  (setf (ir-ty e) (ir-ty (ir-then e)))
  e)

(defmethod resolve-expr ((e block-expr))
  (with-scope ()
    (setf (ir-stmts e) (resolve-stmts (ir-stmts e))
          (ir-value e) (resolve-expr (ir-value e))))
  (setf (ir-ty e) (ir-ty (ir-value e)))
  e)

(defmethod resolve-expr ((e comment-expr))
  (dsl-error (ir-source e) "a comment is not a value"))

(defmethod resolve-expr ((e expr))
  ;; target-form-expr, raw-expr: opaque
  e)

;;; intrinsic calls

(defun intrinsic-arg (intrinsic args name)
  (let ((pos (position name (intrinsic-param-names intrinsic) :test #'string=)))
    (and pos (nth pos args))))

(defun intrinsic-result-type (intrinsic args form)
  (let ((spec (intrinsic-ret intrinsic)))
    (if (or (atom spec) (not (member (car spec) '(:type-of :map-value-optional :map-keys))))
        spec
        (let* ((arg (intrinsic-arg intrinsic args (spelling (second spec))))
               (ty (strip-indirection (if arg (ir-ty arg) :unknown))))
          (ecase (car spec)
            (:type-of ty)
            (:map-value-optional (if (eq :map (type-head ty)) (list :optional (third ty))
                                     (dsl-error form "~a needs a map" (intrinsic-name intrinsic))))
            (:map-keys (if (eq :map (type-head ty)) (list :vec (second ty))
                           (dsl-error form "~a needs a map" (intrinsic-name intrinsic)))))))))

(defun check-intrinsic-arg (arg spec form)
  (let ((ty (strip-indirection (ir-ty arg))))
    (flet ((bad (what) (dsl-error form "argument must be ~a, got ~a" what (type-string ty))))
      (when (known-type-p ty)
        (case spec
          (:number (unless (numeric-type-p ty) (bad "a number")))
          (:integer (unless (int-type-p ty) (bad "an integer")))
          (:vec (unless (eq :vec (type-head ty)) (bad "a vec")))
          (:map (unless (eq :map (type-head ty)) (bad "a map")))
          ((:any :collection) nil)
          (:string (unless (or (eq ty :string) (equal (borrow-target ty) :string)) (bad "a string")))
          (t (coerce-expr arg spec "argument")))))))

(defun coerce-container-args (name args)
  "Element/key/value coercion for push and the map intrinsics."
  (let ((container (strip-indirection (ir-ty (if (string= name "push") (second args) (first args))))))
    (cond ((string= name "push") (coerce-expr (first args) (element-type container) "pushed item"))
          ((eq :map (type-head container))
           (when (second args) (coerce-expr (second args) (second container) "map key"))
           (when (third args) (coerce-expr (third args) (third container) "map value"))))))

(defun resolve-intrinsic-call (e intrinsic)
  (let ((args (ir-args e)) (form (ir-source e)) (name (intrinsic-name intrinsic)))
    (check-intrinsic-arity intrinsic form (length args))
    (loop for a in args
          for (nil spec) in (append (intrinsic-params intrinsic) (intrinsic-optional intrinsic))
          do (check-intrinsic-arg a spec form))
    (when (member name '("min" "max") :test #'string=)
      (unify-numeric-operands args))
    (coerce-container-args name args)
    (setf (ir-target e) intrinsic
          (ir-call-kind e) :intrinsic
          (ir-ty e) (intrinsic-result-type intrinsic args form))
    e))
