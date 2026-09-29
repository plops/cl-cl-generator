;;;; expr.lisp --- CL backend: expressions -> S-expressions

(in-package :polyglot)

(defgeneric cl-form (e)
  (:documentation "S-expression for the IR expression E."))

(defmethod cl-form ((e lit-expr))
  (ecase (ir-kind e)
    ((:int :string :char) (ir-value e))
    (:float (coerce (ir-value e) 'double-float))
    (:bool (if (ir-value e) 't 'nil))
    (:nil (if (member (type-head (ir-ty e)) '(:vec))
              (list (rt-sym "pg-vec"))
              (if (eq :map (type-head (ir-ty e)))
                  '(make-hash-table :test 'equal)
                  nil)))))

(defmethod cl-form ((e var-expr))
  (let ((b (ir-binding e)))
    (etypecase b
      (var-def (local-sym b))
      (const-item (item-sym b))
      (function-item `(function ,(item-sym b))))))

(defun cl-equality-op (ty)
  (let ((ty (borrow-target ty)))
    (cond ((numeric-type-p ty) '=)
          ((eq ty :string) 'string=)
          ((eq ty :char) 'char=)
          ((eq ty :bool) 'eq)
          (t 'equalp))))

(defun cl-comparison-op (op ty)
  (let ((stringp (eq :string (borrow-target ty))))
    (ecase op
      (:lt (if stringp 'string< '<)) (:le (if stringp 'string<= '<=))
      (:gt (if stringp 'string> '>)) (:ge (if stringp 'string>= '>=)))))

(defun flatten-nary (form)
  "(+ (+ a b) c) -> (+ a b c): the CL operators are n-ary and evaluate left to right."
  (if (and (consp form) (consp (second form)) (eq (car form) (car (second form)))
           (member (car form) '(+ - * and or logand logior logxor))
           (cddr (second form)) (= 3 (length form)))
      (append (second form) (cddr form))
      form))

(defmethod cl-form ((e op-expr))
  (flatten-nary (cl-op-form e)))

(defun cl-op-form (e)
  (let* ((args (mapcar #'cl-form (ir-args e)))
         (a (first args)) (b (second args))
         (ty (ir-ty (first (ir-args e)))))
    (ecase (ir-op e)
      (:add `(+ ,a ,b)) (:sub `(- ,a ,b)) (:mul `(* ,a ,b)) (:div `(/ ,a ,b))
      (:neg `(- ,a))
      (:eq `(,(cl-equality-op ty) ,a ,b))
      (:ne (if (numeric-type-p ty) `(/= ,a ,b) `(not (,(cl-equality-op ty) ,a ,b))))
      ((:lt :le :gt :ge) `(,(cl-comparison-op (ir-op e) ty) ,a ,b))
      (:and `(and ,a ,b)) (:or `(or ,a ,b)) (:not `(not ,a))
      (:bitand `(logand ,a ,b)) (:bitor `(logior ,a ,b)) (:bitxor `(logxor ,a ,b))
      (:bitnot `(lognot ,a))
      (:shl `(ash ,a ,b)) (:shr `(ash ,a (- ,b))))))

(defmethod cl-form ((e call-expr))
  (let ((args (mapcar #'cl-form (ir-args e))))
    (ecase (ir-call-kind e)
      (:function `(,(item-sym (ir-target e)) ,@args))
      (:extern (cl-extern-call e args))
      (:intrinsic (funcall (getf (intrinsic-expansion (ir-target e) :cl (ir-source e)) :function)
                           e args)))))

(defun cl-extern-call (e args)
  (let* ((item (ir-target e))
         (spec (or (cdr (assoc :cl (ir-expansions item)))
                   (unsupported (ir-source e) "extern ~a has no :cl spelling" (ir-name item)))))
    `(,(let ((*package* (scratch-package *cl-module*))) (read-from-string (first spec))) ,@args)))

(defmethod cl-form ((e method-call-expr))
  `(,(generic-sym (ir-target e)) ,(cl-form (ir-receiver e)) ,@(mapcar #'cl-form (ir-args e))))

(defmethod cl-form ((e field-expr))
  `(,(accessor-sym (ir-target e)) ,(cl-form (ir-object e))))

(defmethod cl-form ((e aref-expr))
  `(aref ,(cl-form (ir-object e)) ,(cl-form (ir-index e))))

(defmethod cl-form ((e make-expr))
  `(make-instance ',(item-sym (ir-target e))
                  ,@(loop for init in (ir-inits e)
                          for field = (find-field (ir-target e) (ir-name init))
                          append (list (field-keyword field) (cl-form (ir-value init))))))

(defmethod cl-form ((e vec-expr))
  `(,(rt-sym "pg-vec") ,@(mapcar #'cl-form (ir-elems e))))

(defmethod cl-form ((e map-expr))
  '(make-hash-table :test 'equal))

(defmethod cl-form ((e own-expr))
  (let ((v (cl-form (ir-value e))))
    (if (and (eq :clone (ir-kind e))
             (not (copy-type-p (ir-ty e)))
             (not (eq :string (ir-ty e))))
        `(,(rt-sym "pg-clone") ,v)
        v)))

(defmethod cl-form ((e super-expr))
  (if (ir-args e)
      `(call-next-method ,(local-sym (method-receiver (ir-method e))) ,@(mapcar #'cl-form (ir-args e)))
      '(call-next-method)))

(defmethod cl-form ((e lambda-expr))
  `(lambda ,(mapcar #'local-sym (ir-params e))
     ,@(cl-function-body (ir-body e))))

(defmethod cl-form ((e funcall-expr))
  `(funcall ,(cl-form (ir-fn e)) ,@(mapcar #'cl-form (ir-args e))))

(defmethod cl-form ((e if-expr))
  `(if ,(cl-form (ir-test e)) ,(cl-form (ir-then e)) ,(cl-form (ir-else e))))

(defmethod cl-form ((e block-expr))
  (let ((forms (cl-stmt-forms (ir-stmts e) (list (cl-form (ir-value e))) nil)))
    (if (cdr forms) `(progn ,@forms) (first forms))))

(defmethod cl-form ((e raw-expr))
  `(cl-cl-generator:raw ,(ir-text e)))
