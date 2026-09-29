;;;; 32-resolve-types.lisp --- type compatibility and literal coercion

(in-package :polyglot)

(defun struct-subtype-p (sub super)
  "True when the struct/interface item SUB can be used where SUPER is expected."
  (or (eq sub super)
      (and (typep sub 'struct-item)
           (or (member super (struct-base-chain sub))
               (member super (type-interfaces sub))))
      (and (typep sub 'interface-item)
           (member super (interface-closure (list sub))))))

(defun type-compatible-p (actual expected)
  "Lenient compatibility check used for arguments, returns and assignments."
  (cond ((or (not (known-type-p actual)) (not (known-type-p expected))) t)
        ((equal actual expected) t)
        ((and (int-type-p actual) (int-type-p expected)) t)
        ((member (type-head expected) '(:ref :mut-ref :view))
         (or (and (eq :box (type-head actual)) (member (type-head expected) '(:ref :mut-ref))
                  (type-compatible-p (second actual) (second expected)))
             (and (eq (type-head actual) (type-head expected))
                  (type-compatible-p (second actual) (second expected)))
             (and (eq (type-head expected) :ref) (eq (type-head actual) :mut-ref)
                  (type-compatible-p (second actual) (second expected)))
             (type-compatible-p actual (second expected))))
        ((member (type-head actual) '(:ref :mut-ref))
         (type-compatible-p (second actual) expected))
        ((and (eq (type-head expected) :box) (eq (type-head actual) :box))
         (type-compatible-p (second actual) (second expected)))
        ((and (type-item actual) (type-item expected))
         (struct-subtype-p (type-item actual) (type-item expected)))
        ((and (eq actual :nil) (member (type-head expected) '(:optional :vec :map))) t)
        (t nil)))

(defun coerce-literal (e expected)
  "Adapt the literal E to EXPECTED. Returns T when E was a literal."
  (when (typep e 'lit-expr)
    (case (ir-kind e)
      (:int (cond ((float-type-p expected)
                   (setf (ir-kind e) :float
                         (ir-value e) (coerce (ir-value e) 'double-float)
                         (ir-ty e) expected))
                  ((int-type-p expected) (setf (ir-ty e) expected))))
      (:float (when (float-type-p expected) (setf (ir-ty e) expected)))
      (:nil (when (member (type-head expected) '(:optional :vec :map))
              (setf (ir-ty e) expected))))
    t))

(defun coerce-expr (e expected &optional (what "value"))
  "Coerce literals inside E to EXPECTED and check type compatibility."
  (when (and e (known-type-p expected))
    (typecase e
      (lit-expr (coerce-literal e expected))
      (op-expr (when (and (member (ir-op e) '(:neg :add :sub :mul :div))
                          (numeric-type-p expected))
                 (dolist (a (ir-args e)) (coerce-expr a expected what))
                 (setf (ir-ty e) (ir-ty (first (ir-args e))))))
      (if-expr (coerce-expr (ir-then e) expected what)
               (coerce-expr (ir-else e) expected what)
               (setf (ir-ty e) (ir-ty (ir-then e))))
      (block-expr (coerce-expr (ir-value e) expected what)
                  (setf (ir-ty e) (ir-ty (ir-value e)))))
    (unless (or (type-compatible-p (ir-ty e) expected)
                (and (typep e 'lit-expr) (eq :nil (ir-kind e))))
      (dsl-error (ir-source e) "type mismatch for ~a: expected ~a, got ~a"
                 what (type-string expected) (type-string (ir-ty e)))))
  e)

(defun unify-numeric-operands (args)
  "When one operand is a float, int literals among ARGS become floats."
  (let ((float (find-if (lambda (a) (float-type-p (ir-ty a))) args)))
    (when float
      (dolist (a args)
        (when (and (typep a 'lit-expr) (eq :int (ir-kind a)))
          (coerce-literal a (ir-ty float)))
        (when (and (typep a 'op-expr) (eq :neg (ir-op a)))
          (coerce-expr a (ir-ty float)))))
    args))

(defun element-type (ty)
  "Element type of a vec, array or view of a vec; NIL otherwise."
  (let ((ty (strip-indirection ty)))
    (case (type-head ty)
      ((:vec :array) (second ty))
      (:view (when (eq :vec (type-head (second ty))) (second (second ty)))))))
