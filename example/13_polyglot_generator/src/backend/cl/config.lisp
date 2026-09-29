;;;; config.lisp --- Common Lisp backend: configuration
;;;;
;;;; The CL backend is the semantic oracle: the IR is lowered to S-expressions
;;;; and printed with cl-cl-generator:emit-cl. Names keep the DSL spelling;
;;;; clashes with COMMON-LISP symbols are resolved by shadowing in the
;;;; generated DEFPACKAGE (E4).

(in-package :polyglot)

(defclass cl-backend (backend) ()
  (:documentation "Common Lisp (SBCL, ECL) backend."))

(register-backend (make-instance 'cl-backend :key :cl))

(defmethod backend-directory ((b cl-backend)) "cl")

(defmethod backend-config ((b cl-backend))
  (list :naming '((:type . :kebab) (:function . :kebab) (:method . :kebab) (:field . :kebab)
                  (:constant . :kebab) (:variable . :kebab) (:module . :kebab))
        :reserved '()
        :shadowing :allow
        :capabilities '(:block-expressions t :ternary t :multi-statement-lambda t
                        :implementation-inheritance t :inout-scalars nil :inout-rebind nil)))
