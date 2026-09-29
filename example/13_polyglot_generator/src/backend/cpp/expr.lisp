;;;; expr.lisp --- C++ backend: expressions

(in-package :polyglot)

(defvar *cpp-function* nil "Function or method whose body is emitted.")
(defvar *cpp-local-names* nil "Target names of params/locals of *CPP-FUNCTION*.")

(defun receiver-ref-p (e)
  (and (typep e 'var-expr) (typep (ir-binding e) 'var-def) (ir-receiver-p (ir-binding e))))

(defun cpp-int-literal (v)
  (if (< (- (expt 2 31)) v (expt 2 31)) (princ-to-string v) (format nil "~dLL" v)))

(defmethod emit-expr ((b cpp-backend) (e lit-expr))
  (let ((v (ir-value e)))
    (ecase (ir-kind e)
      (:int (values (cpp-int-literal v) (literal-op v)))
      (:float (values (format nil "~a~:[~;f~]" (float-literal v) (eq :f32 (ir-ty e))) (literal-op v)))
      (:string (prim (string-literal v :c)))
      (:char (prim (char-literal v :c)))
      (:bool (prim (if v "true" "false")))
      (:nil (prim (if (eq :optional (type-head (ir-ty e)))
                      (progn (cpp-std-include "optional") "std::nullopt")
                      (format nil "~a{}" (cpp-type (ir-ty e)))))))))

(defmethod emit-expr ((b cpp-backend) (e var-expr))
  (let ((binding (ir-binding e)))
    (cond ((receiver-ref-p e) (prim "*this"))
          ((typep binding 'var-def) (prim (ir-target-name binding)))
          (t (prim (cpp-item-ref binding))))))

(defmethod emit-expr ((b cpp-backend) (e op-expr))
  (let ((args (ir-args e)))
    (case (ir-op e)
      ((:neg :bitnot :not) (unary (ir-op e) (first args)))
      (t (binary (ir-op e) (first args) (second args))))))

(defun cpp-call-args (args params)
  "Arguments; a box passed to an :in parameter of the boxed type is dereferenced."
  (format nil "~{~a~^, ~}"
          (loop for a in args
                for p = (pop params)
                collect (if (and p (box-deref-arg-p a p))
                            (format nil "*~a" (operand :neg :only a))
                            (ex-str a)))))

(defmethod emit-expr ((b cpp-backend) (e call-expr))
  (ecase (ir-call-kind e)
    (:function (prim (format nil "~a(~a)" (cpp-item-ref (ir-target e))
                             (cpp-call-args (ir-args e) (ir-params (ir-target e))))))
    (:extern (cpp-extern-call e))
    (:intrinsic (emit-intrinsic e))))

(defun cpp-extern-call (e)
  (let* ((item (ir-target e))
         (spec (or (cdr (assoc :cpp (ir-expansions item)))
                   (unsupported (ir-source e) "extern ~a has no :cpp spelling" (ir-name item)))))
    (dolist (i (getf (cdr spec) :includes)) (note-import (list :raw-include i)))
    (prim (format nil "~a(~a)" (first spec) (comma-list (ir-args e))))))

(defun cpp-member-access (object member)
  "OBJECT.MEMBER, OBJECT->MEMBER or MEMBER alone for the receiver."
  (cond ((receiver-ref-p object)
         (if (member member *cpp-local-names* :test #'string=)
             (format nil "this->~a" member)
             member))
        ((or (cpp-pointer-type-p (ir-ty object))
             (and (typep object 'field-expr) (member (type-head (ir-ty object)) '(:ref :mut-ref))))
         (format nil "~a->~a" (receiver object) member))
        (t (format nil "~a.~a" (receiver object) member))))

(defmethod emit-expr ((b cpp-backend) (e method-call-expr))
  (prim (format nil "~a(~a)" (cpp-member-access (ir-receiver e) (ir-target-name (ir-target e)))
                (cpp-call-args (ir-args e) (rest (ir-params (ir-target e)))))))

(defmethod emit-expr ((b cpp-backend) (e field-expr))
  (prim (cpp-member-access (ir-object e) (ir-target-name (ir-target e)))))

(defmethod emit-expr ((b cpp-backend) (e aref-expr))
  (prim (format nil "~a[~a]" (receiver (ir-object e)) (ex-str (ir-index e)))))

(defmethod emit-expr ((b cpp-backend) (e make-expr))
  (let ((item (ir-target e)))
    (prim (if (cpp-polymorphic-p item)
              (format nil "~a(~a)" (cpp-item-ref item) (cpp-ctor-args item e))
              (format nil "~a{~{~a~^, ~}}" (cpp-item-ref item) (cpp-designated-inits item e))))))

(defun make-init-for (e field)
  (find (ir-name field) (ir-inits e) :key #'ir-name :test #'string=))

(defun cpp-field-value (field value-expr)
  (if (member (type-head (ir-ty field)) '(:ref :mut-ref))
      (format nil "&~a" (operand :neg :only value-expr))
      (ex-str value-expr)))

(defun cpp-designated-inits (item e)
  (loop for f in (ir-fields item)
        for init = (make-init-for e f)
        when init collect (format nil ".~a = ~a" (ir-target-name f) (cpp-field-value f (ir-value init)))))

(defun cpp-ctor-args (item e)
  "Constructor arguments in field order; missing fields take their defaults."
  (format nil "~{~a~^, ~}"
          (loop for f in (all-fields item)
                for init = (make-init-for e f)
                collect (cond (init (cpp-field-value f (ir-value init)))
                              ((ir-default f) (ex-str (ir-default f)))
                              (t (format nil "~a{}" (cpp-type (ir-ty f))))))))

(defmethod emit-expr ((b cpp-backend) (e vec-expr))
  (cpp-std-include "vector")
  (let ((ty (cpp-type (ir-elem-type e))))
    (if (eq :box (type-head (ir-elem-type e)))
        (progn (note-prelude "make_vec")
               (prim (format nil "polyglot_rt::make_vec<~a>(~a)" ty (comma-list (ir-elems e)))))
        (prim (format nil "std::vector<~a>{~a}" ty (comma-list (ir-elems e)))))))

(defmethod emit-expr ((b cpp-backend) (e map-expr))
  (prim (format nil "~a{}" (cpp-type (ir-ty e)))))

(defmethod emit-expr ((b cpp-backend) (e own-expr))
  (let ((v (ir-value e)))
    (ecase (ir-kind e)
      ((:clone :some) (ex v))
      (:move (cpp-std-include "utility") (prim (format nil "std::move(~a)" (ex-str v))))
      (:box (cpp-std-include "memory")
            (let ((inner (strip-indirection (ir-ty v))))
              (prim (if (and (typep v 'make-expr) (cpp-polymorphic-p (ir-target v)))
                        (format nil "std::make_unique<~a>(~a)" (cpp-type inner) (cpp-ctor-args (ir-target v) v))
                        (format nil "std::make_unique<~a>(~a)" (cpp-type inner) (ex-str v)))))))))

(defmethod emit-expr ((b cpp-backend) (e super-expr))
  (let ((target (ir-target e)))
    (prim (format nil "~a::~a(~a)" (cpp-item-ref (ir-owner-item target)) (ir-target-name target)
                  (comma-list (ir-args e))))))

(defmethod emit-expr ((b cpp-backend) (e funcall-expr))
  (prim (format nil "~a(~a)" (receiver (ir-fn e)) (comma-list (ir-args e)))))

(defmethod emit-expr ((b cpp-backend) (e if-expr))
  (values (format nil "~a ? ~a : ~a" (operand :cond :left (ir-test e))
                  (operand :cond :right (ir-then e)) (operand :cond :right (ir-else e)))
          :cond))

(defmethod emit-expr ((b cpp-backend) (e raw-expr)) (prim (ir-text e)))

(defmethod emit-expr ((b cpp-backend) (e target-form-expr))
  (let ((form (ir-form e)))
    (if (and (form-is (car form) "raw") (stringp (second form)))
        (prim (second form))
        (unsupported form "unknown cpp: form"))))
