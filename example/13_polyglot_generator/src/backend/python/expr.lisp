;;;; expr.lisp --- Python backend: expressions

(in-package :polyglot)

(defvar *py-module* nil "Module being emitted.")

(defun py-ref (item)
  "Name of ITEM as seen from *PY-MODULE*; notes the import of foreign items."
  (let ((module (ir-module item)))
    (unless (or (null module) (eq module *py-module*))
      (note-import (list :from (ir-target-name module) (ir-target-name item))))
    (ir-target-name item)))

(defun py-type (ty)
  "Python type annotation of TY."
  (cond ((int-type-p ty) "int")
        ((float-type-p ty) "float")
        ((eq ty :bool) "bool")
        ((member ty '(:string :char)) "str")
        ((eq ty :void) "None")
        ((not (consp ty)) "object")
        (t (case (car ty)
             ((:vec :array) (format nil "list[~a]" (py-type (second ty))))
             (:map (format nil "dict[~a, ~a]" (py-type (second ty)) (py-type (third ty))))
             (:optional (format nil "~a | None" (py-type (second ty))))
             ((:box :ref :mut-ref :view) (py-type (second ty)))
             ((:named :dyn) (py-ref (third ty)))
             (:fn (note-import (list :from "collections.abc" "Callable"))
                  (format nil "Callable[[~{~a~^, ~}], ~a]" (mapcar #'py-type (second ty))
                          (py-type (third ty))))
             (:raw (if (eq (second ty) :python) (third ty) "object"))
             (t "object")))))

(defmethod emit-expr ((b python-backend) (e lit-expr))
  (let ((v (ir-value e)))
    (ecase (ir-kind e)
      (:int (values (princ-to-string v) (literal-op v)))
      (:float (values (float-literal v) (literal-op v)))
      (:string (prim (string-literal v :python)))
      (:char (prim (string-literal (string v) :python)))
      (:bool (prim (if v "True" "False")))
      (:nil (prim (case (type-head (ir-ty e)) (:vec "[]") (:map "{}") (t "None")))))))

(defmethod emit-expr ((b python-backend) (e var-expr))
  (let ((binding (ir-binding e)))
    (prim (if (typep binding 'var-def) (ir-target-name binding) (py-ref binding)))))

(defmethod emit-expr ((b python-backend) (e op-expr))
  (let ((args (ir-args e)))
    (case (ir-op e)
      ((:neg :bitnot :not) (unary (ir-op e) (first args)))
      (t (binary (ir-op e) (first args) (second args))))))

(defmethod emit-expr ((b python-backend) (e call-expr))
  (ecase (ir-call-kind e)
    (:function (prim (format nil "~a(~a)" (py-ref (ir-target e)) (comma-list (ir-args e)))))
    (:extern (py-extern-call e))
    (:intrinsic (emit-intrinsic e))))

(defun py-extern-call (e)
  (let* ((item (ir-target e))
         (spec (or (cdr (assoc :python (ir-expansions item)))
                   (unsupported (ir-source e) "extern ~a has no :python spelling" (ir-name item)))))
    (dolist (i (getf (cdr spec) :imports)) (note-import (list :import i)))
    (prim (format nil "~a(~a)" (first spec) (comma-list (ir-args e))))))

(defmethod emit-expr ((b python-backend) (e method-call-expr))
  (prim (format nil "~a.~a(~a)" (receiver (ir-receiver e)) (ir-target-name (ir-target e))
                (comma-list (ir-args e)))))

(defmethod emit-expr ((b python-backend) (e field-expr))
  (prim (format nil "~a.~a" (receiver (ir-object e)) (ir-target-name (ir-target e)))))

(defmethod emit-expr ((b python-backend) (e aref-expr))
  (prim (format nil "~a[~a]" (receiver (ir-object e)) (ex-str (ir-index e)))))

(defmethod emit-expr ((b python-backend) (e make-expr))
  (let ((item (ir-target e)))
    (prim (format nil "~a(~{~a~^, ~})" (py-ref item)
                  (loop for init in (ir-inits e)
                        collect (format nil "~a=~a" (ir-target-name (find-field item (ir-name init)))
                                        (ex-str (ir-value init))))))))

(defmethod emit-expr ((b python-backend) (e vec-expr))
  (prim (format nil "[~a]" (comma-list (ir-elems e)))))

(defmethod emit-expr ((b python-backend) (e map-expr))
  (prim "{}"))

(defun py-clone (e)
  (let ((ty (ir-ty e)) (v (ir-value e)))
    (cond ((or (copy-type-p ty) (eq ty :string)) (ex v))
          ((and (member (type-head ty) '(:vec :map))
                (let ((elem (if (eq :map (type-head ty)) (third ty) (second ty))))
                  (or (copy-type-p elem) (eq elem :string))))
           (prim (format nil "~a.copy()" (receiver v))))
          (t (note-import (list :import "copy"))
             (prim (format nil "copy.deepcopy(~a)" (ex-str v)))))))

(defmethod emit-expr ((b python-backend) (e own-expr))
  (if (eq :clone (ir-kind e)) (py-clone e) (ex (ir-value e))))

(defmethod emit-expr ((b python-backend) (e super-expr))
  (prim (format nil "super().~a(~a)" (ir-target-name (ir-target e)) (comma-list (ir-args e)))))

(defun py-lambda-params (lam)
  (append (mapcar #'ir-target-name (ir-params lam))
          (mapcar (lambda (v) (format nil "~a=~a" (ir-target-name v) (ir-target-name v)))
                  (ir-captures lam))))

(defmethod emit-expr ((b python-backend) (e lambda-expr))
  (let* ((s (first (ir-body e)))
         (body (typecase s
                 (return-stmt (ex-str (ir-value s)))
                 (expr-stmt (ex-str (ir-expr s)))
                 (t "None"))))
    (values (format nil "lambda~@[ ~{~a~^, ~}~]: ~a" (py-lambda-params e) body) :lambda)))

(defmethod emit-expr ((b python-backend) (e funcall-expr))
  (prim (format nil "~a(~a)" (receiver (ir-fn e)) (comma-list (ir-args e)))))

(defmethod emit-expr ((b python-backend) (e if-expr))
  (values (format nil "~a if ~a else ~a"
                  (operand :if :left (ir-then e)) (operand :if :left (ir-test e))
                  (operand :if :right (ir-else e)))
          :if))

(defmethod emit-expr ((b python-backend) (e raw-expr))
  (prim (ir-text e)))

(defmethod emit-expr ((b python-backend) (e target-form-expr))
  (py-target-form e))

(defun py-target-form (e)
  (let ((form (ir-form e)))
    (if (and (form-is (car form) "raw") (stringp (second form)))
        (prim (second form))
        (unsupported form "unknown py: form"))))
