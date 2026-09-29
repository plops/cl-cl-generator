;;;; 20-registry.lisp --- surface form registry, DSL macros, target-case and
;;;; extension forms

(in-package :polyglot)

(defvar *expr-forms* (make-hash-table :test 'equal)
  "Form name -> parser function (FORM) returning an expression node.")
(defvar *stmt-forms* (make-hash-table :test 'equal)
  "Form name -> parser function (FORM) returning a statement node.")
(defvar *dsl-macros* (make-hash-table :test 'equal)
  "Form name -> expander function (FORM) returning a new form.")

(defparameter +macro-depth-limit+ 100)
(defvar *macro-depth* 0)

(defmacro define-surface-form (name (context form) &body body)
  "Register a parser for the DSL form NAME (a string). CONTEXT is :expr, :stmt
or :both; FORM is bound to the whole source form."
  (let ((fn (gensym "PARSER")))
    `(let ((,fn (lambda (,form) ,@body)))
       ,@(when (member context '(:expr :both))
           `((setf (gethash ,name *expr-forms*) ,fn)))
       ,@(when (member context '(:stmt :both))
           `((setf (gethash ,name *stmt-forms*) ,fn)))
       ,name)))

(defmacro define-dsl-macro (name lambda-list &body body)
  "Define a DSL macro NAME. It is expanded before parsing, wherever a form with
this head appears (expression, statement or item position)."
  (let ((form (gensym "FORM")))
    `(progn
       (setf (gethash ,(string-downcase (symbol-name name)) *dsl-macros*)
             (lambda (,form)
               (destructuring-bind ,lambda-list (cdr ,form)
                 ,@body)))
       ',name)))

(defun dsl-macro-p (form)
  (and (consp form) (symbolp (car form))
       (gethash (form-name (car form)) *dsl-macros*)))

(defun expand-dsl-macro (form)
  "Expand FORM once if its head is a DSL macro."
  (let ((expander (dsl-macro-p form)))
    (if expander
        (funcall expander form)
        form)))

(defmacro with-macro-expansion ((var form) &body body)
  "Expand FORM completely at the head position, bind the result to VAR and run
BODY with an incremented expansion depth (limit +MACRO-DEPTH-LIMIT+)."
  `(call-with-macro-expansion ,form (lambda (,var) ,@body)))

(defun call-with-macro-expansion (form fn)
  (if (not (dsl-macro-p form))
      (funcall fn form)
      (let ((*macro-depth* *macro-depth*)
            (current form))
        (loop while (dsl-macro-p current)
              do (when (> (incf *macro-depth*) +macro-depth-limit+)
                   (dsl-error form "DSL macro expansion deeper than ~d levels"
                              +macro-depth-limit+))
              (setf current (expand-dsl-macro current)))
        (funcall fn current))))

(defun extension-form-backend (form)
  "Backend keyword when FORM is a list whose head lives in an extension package."
  (and (consp form) (symbolp (car form)) (car form)
       (symbol-package (car form))
       (target-package-backend (symbol-package (car form)))))

(defun parse-target-backends (form spec)
  (cond ((eq spec t) t)
        ((keywordp spec) (list (normalize-backend-key form spec)))
        ((and (consp spec) (every #'keywordp spec))
         (mapcar (lambda (k) (normalize-backend-key form k)) spec))
        (t (dsl-error form "target-case branch needs a backend keyword, a list of them or T"))))

(defun normalize-backend-key (form key)
  (case key
    ((:cpp :c++) :cpp)
    ((:py :python) :python)
    ((:rs :rust) :rust)
    (:go :go)
    (:cl :cl)
    (t (dsl-error form "unknown backend ~s" key))))

(defun parse-target-case (form parse-branch-body)
  "Parse (target-case (keys forms...) ...) with PARSE-BRANCH-BODY on the forms."
  (when (null (cdr form))
    (dsl-error form "empty target-case"))
  (loop for clause in (cdr form)
        do (unless (consp clause)
             (dsl-error form "malformed target-case clause ~s" clause))
        collect (make-target-branch :backends (parse-target-backends form (car clause))
                                    :body (funcall parse-branch-body (cdr clause))
                                    :source clause)))

(defun select-target-branch (node backend)
  "The branch of the target-case NODE that applies to BACKEND, or NIL."
  (or (find-if (lambda (b) (and (listp (ir-backends b)) (member backend (ir-backends b))))
               (ir-branches node))
      (find t (ir-branches node) :key #'ir-backends)))
