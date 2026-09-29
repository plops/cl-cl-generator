;;;; 02-conditions.lisp --- condition classes of the generator

(in-package :polyglot)

(defvar *current-backend* nil
  "Keyword of the backend that is currently running, or NIL in the frontend.")

(defun first-symbol-package (form)
  "Home package of the first non-keyword symbol in FORM (the DSL file's package)."
  (cond ((and (symbolp form) form (not (keywordp form)) (symbol-package form)))
        ((consp form) (or (first-symbol-package (car form)) (first-symbol-package (cdr form))))
        (t nil)))

(defun form-string (form)
  "Print FORM the way it was written in a DSL file (readtable-case :invert,
symbols relative to the package of the file)."
  (let ((*readtable* (named-readtables:find-readtable 'polyglot-syntax))
        (*print-pretty* nil) (*print-length* 12) (*print-level* 5)
        (*print-readably* nil)
        (*package* (or (first-symbol-package form) (find-package :polyglot))))
    (prin1-to-string form)))

(define-condition dsl-error (error)
  ((form :initarg :form :initform nil :reader dsl-error-form)
   (backend :initarg :backend :initform nil :reader dsl-error-backend)
   (message :initarg :message :initform "" :reader dsl-error-message))
  (:report (lambda (c stream)
             (format stream "DSL error~@[ [~(~a~)]~]: ~a~@[~%  in form: ~a~]"
                     (dsl-error-backend c)
                     (dsl-error-message c)
                     (and (dsl-error-form c) (form-string (dsl-error-form c))))))
  (:documentation "Error in a DSL program. FORM is the offending source form,
BACKEND the backend keyword when the error was found by a backend."))

(define-condition unsupported-construct (dsl-error)
  ()
  (:report (lambda (c stream)
             (format stream "Unsupported construct~@[ for backend ~(~a~)~]: ~a~@[~%  in form: ~a~]"
                     (dsl-error-backend c)
                     (dsl-error-message c)
                     (and (dsl-error-form c) (form-string (dsl-error-form c))))))
  (:documentation "The construct is valid DSL but the backend cannot express it."))

(define-condition dsl-warning (warning)
  ((form :initarg :form :initform nil :reader dsl-warning-form)
   (message :initarg :message :initform "" :reader dsl-warning-message))
  (:report (lambda (c stream)
             (format stream "DSL warning: ~a~@[~%  in form: ~s~]"
                     (dsl-warning-message c)
                     (dsl-warning-form c))))
  (:documentation "Non fatal problem, e.g. a missing formatter."))

(defun dsl-error (form control &rest args)
  "Signal a DSL-ERROR for FORM with a message built from CONTROL and ARGS."
  (error 'dsl-error :form form :backend *current-backend*
         :message (apply #'format nil control args)))

(defun unsupported (form control &rest args)
  "Signal UNSUPPORTED-CONSTRUCT for FORM in the current backend."
  (error 'unsupported-construct :form form :backend *current-backend*
         :message (apply #'format nil control args)))

(defun dsl-warn (form control &rest args)
  "Signal a DSL-WARNING for FORM."
  (warn 'dsl-warning :form form :message (apply #'format nil control args)))
