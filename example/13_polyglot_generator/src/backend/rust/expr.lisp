;;;; expr.lisp --- Rust backend: expressions

(in-package :polyglot)

(defun rs-literal-suffix (ty)
  (cond ((eq ty :f32) "_f32") (t "")))

(defmethod emit-expr ((b rust-backend) (e lit-expr))
  (let ((v (ir-value e)))
    (ecase (ir-kind e)
      (:int (values (princ-to-string v) (literal-op v)))
      (:float (values (format nil "~a~a" (float-literal v) (rs-literal-suffix (ir-ty e))) (literal-op v)))
      (:string (prim (string-literal v :rust)))
      (:char (prim (char-literal v :rust)))
      (:bool (prim (if v "true" "false")))
      (:nil (prim (case (type-head (ir-ty e))
                    (:vec "Vec::new()")
                    (:map (note-import (list :std "std::collections::HashMap")) "HashMap::new()")
                    (t "None")))))))

(defmethod emit-expr ((b rust-backend) (e var-expr))
  (let ((binding (ir-binding e)))
    (cond ((not (typep binding 'var-def)) (prim (rs-item-ref binding)))
          ((and (eq :inout (ir-mode binding)) (member (ir-kind binding) '(:param))
                (copy-type-p (ir-ty binding)))
           (values (format nil "*~a" (ir-target-name binding)) :deref))
          (t (prim (ir-target-name binding))))))

(defmethod emit-expr ((b rust-backend) (e op-expr))
  (let ((args (ir-args e)))
    (case (ir-op e)
      ((:neg :bitnot :not) (unary (ir-op e) (first args)))
      (t (binary (ir-op e) (first args) (second args))))))

(defmethod emit-expr ((b rust-backend) (e call-expr))
  (ecase (ir-call-kind e)
    (:function (prim (format nil "~a(~a)" (rs-item-ref (ir-target e))
                             (rs-args (ir-args e) (ir-params (ir-target e))))))
    (:extern (rs-extern-call e))
    (:intrinsic (emit-intrinsic e))))

(defun rs-extern-call (e)
  (let* ((item (ir-target e))
         (spec (or (cdr (assoc :rust (ir-expansions item)))
                   (unsupported (ir-source e) "extern ~a has no :rust spelling" (ir-name item)))))
    (if (getf (cdr spec) :method)
        (prim (format nil "~a.~a(~a)" (receiver (first (ir-args e)))
                      (let* ((name (first spec)) (p (search "::" name :from-end t)))
                        (if p (subseq name (+ p 2)) name))
                      (comma-list (rest (ir-args e)))))
        (prim (format nil "~a(~a)" (first spec) (comma-list (ir-args e)))))))

(defun rs-note-trait-use (method)
  "Calling a trait method needs the trait in scope."
  (let ((owner (ir-owner-item (root-method method))))
    (when (typep owner 'interface-item)
      (rs-item-ref owner))))

(defmethod emit-expr ((b rust-backend) (e method-call-expr))
  (let ((m (ir-target e)))
    (rs-note-trait-use m)
    (prim (format nil "~a.~a(~a)" (receiver (ir-receiver e)) (ir-target-name m)
                  (rs-args (ir-args e) (rest (ir-params m)))))))

(defmethod emit-expr ((b rust-backend) (e field-expr))
  (prim (format nil "~a.~a" (receiver (ir-object e)) (ir-target-name (ir-target e)))))

(defun rs-index (e)
  (if (typep e 'lit-expr) (ex-str e) (format nil "~a as usize" (operand :cast :left e))))

(defmethod emit-expr ((b rust-backend) (e aref-expr))
  (prim (format nil "~a[~a]" (receiver (ir-object e)) (rs-index (ir-index e)))))

(defun rs-field-init (field value)
  (let ((name (ir-target-name field))
        (text (ex-str-for value (ir-ty field))))
    (if (string= text name) name (format nil "~a: ~a" name text))))

(defmethod emit-expr ((b rust-backend) (e make-expr))
  (let ((item (ir-target e)))
    (prim (format nil "~a { ~{~a~^, ~} }" (rs-item-ref item)
                  (loop for f in (ir-fields item)
                        for init = (make-init-for e f)
                        collect (cond (init (rs-field-init f (ir-value init)))
                                      ((ir-default f) (rs-field-init f (ir-default f)))
                                      ((rs-zero-value (ir-ty f))
                                       (format nil "~a: ~a" (ir-target-name f) (rs-zero-value (ir-ty f))))
                                      (t (dsl-error (ir-source e) "field ~a of ~a needs a value"
                                                    (ir-name f) (ir-name item)))))))))

(defmethod emit-expr ((b rust-backend) (e vec-expr))
  (if (ir-elems e)
      (prim (format nil "vec![~{~a~^, ~}]"
                    (mapcar (lambda (x) (ex-str-for x (ir-elem-type e))) (ir-elems e))))
      (prim "Vec::new()")))

(defmethod emit-expr ((b rust-backend) (e map-expr))
  (note-import (list :std "std::collections::HashMap"))
  (prim "HashMap::new()"))

(defmethod emit-expr ((b rust-backend) (e own-expr))
  (let ((v (ir-value e)))
    (ecase (ir-kind e)
      (:move (ex v))
      (:clone (if (copy-type-p (ir-ty e))
                  (ex v)
                  (prim (format nil "~a.clone()" (receiver v)))))
      (:some (prim (format nil "Some(~a)" (ex-str-for v (second (ir-ty e))))))
      (:box (prim (format nil "Box::new(~a)" (ex-str v)))))))

(defmethod emit-expr ((b rust-backend) (e funcall-expr))
  (prim (format nil "~a(~a)" (receiver (ir-fn e)) (comma-list (ir-args e)))))

(defmethod emit-expr ((b rust-backend) (e if-expr))
  (values (format nil "if ~a { ~a } else { ~a }" (ex-str (ir-test e))
                  (ex-str-for (ir-then e) (ir-ty e)) (ex-str-for (ir-else e) (ir-ty e)))
          :block))

(defmethod emit-expr ((b rust-backend) (e raw-expr)) (prim (ir-text e)))

(defmethod emit-expr ((b rust-backend) (e target-form-expr))
  (let ((form (ir-form e)))
    (if (and (form-is (car form) "raw") (stringp (second form)))
        (prim (second form))
        (unsupported form "unknown rs: form"))))
