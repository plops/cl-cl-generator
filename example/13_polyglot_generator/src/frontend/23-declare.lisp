;;;; 23-declare.lisp --- declare clauses, lambda lists, functions and lambdas

(in-package :polyglot)

(defstruct decl-info
  "Parsed declare clauses of one body."
  (types '())                           ; alist name -> type
  (ret nil) (ret-p nil)                 ; (values T)
  (modes '())                           ; alist name -> :in/:inout/:sink
  (borrows-from '()) (outlives '())
  (flags '())                           ; :virtual :override :abstract :pure
  (capture nil)
  (kinds '()))                          ; clause kinds seen, for validation

(defparameter +flag-clauses+ '("virtual" "override" "abstract" "pure"))

(defun declare-form-p (form)
  (and (consp form) (form-is (car form) "declare")))

(defun add-per-var (info form slot names value what)
  "Record VALUE for every name in NAMES in the alist SLOT (:types or :modes)."
  (dolist (n names)
    (let ((name (spelling n)))
      (when (assoc name (if (eq slot :types) (decl-info-types info) (decl-info-modes info))
                   :test #'string=)
        (dsl-error form "duplicate ~a declaration for ~a" what name))
      (if (eq slot :types)
          (push (cons name value) (decl-info-types info))
          (push (cons name value) (decl-info-modes info))))))

(defun parse-declare-clause (info clause form)
  (unless (and (consp clause) (symbolp (car clause)))
    (dsl-error form "malformed declare clause ~s" clause))
  (let ((kind (form-name (car clause))) (args (cdr clause)))
    (cond
      ((string= kind "type")
       (pushnew :types (decl-info-kinds info))
       (add-per-var info clause :types (cdr args) (parse-type (car args)) "type"))
      ((string= kind "values")
       (when (decl-info-ret-p info) (dsl-error clause "duplicate values declaration"))
       (unless (= 1 (length args)) (dsl-error clause "values expects exactly one type"))
       (setf (decl-info-ret info) (parse-type (car args)) (decl-info-ret-p info) t)
       (pushnew :values (decl-info-kinds info)))
      ((string= kind "mode")
       (unless (member (car args) '(:in :inout :sink))
         (dsl-error clause "mode must be :in, :inout or :sink"))
       (pushnew :modes (decl-info-kinds info))
       (add-per-var info clause :modes (cdr args) (car args) "mode"))
      ((string= kind "borrows-from")
       (when (decl-info-borrows-from info) (dsl-error clause "duplicate borrows-from"))
       (pushnew :borrows-from (decl-info-kinds info))
       (setf (decl-info-borrows-from info) (mapcar #'spelling args)))
      ((string= kind "outlives")
       (unless (and (= 2 (length args)) (every #'keywordp args))
         (dsl-error clause "outlives expects two region keywords"))
       (pushnew :outlives (decl-info-kinds info))
       (push args (decl-info-outlives info)))
      ((member kind +flag-clauses+ :test #'string=)
       (let ((flag (alexandria:make-keyword (string-upcase kind))))
         (when (member flag (decl-info-flags info)) (dsl-error clause "duplicate ~a" kind))
         (pushnew :flags (decl-info-kinds info))
         (push flag (decl-info-flags info))))
      ((string= kind "capture")
       (unless (member (car args) '(:value :ref)) (dsl-error clause "capture must be :value or :ref"))
       (pushnew :capture (decl-info-kinds info))
       (setf (decl-info-capture info) (car args)))
      ((string= kind "ignorable") nil)
      (t (dsl-error clause "unknown declare clause ~a" kind)))))

(defun split-declares (body &key (allow-doc t))
  "Split BODY into (values decl-info remaining-forms docstring)."
  (let ((info (make-decl-info)) (doc nil))
    (when (and allow-doc (stringp (car body)) (cdr body))
      (setf doc (pop body)))
    (loop while (declare-form-p (car body))
          do (dolist (clause (cdr (pop body)))
               (parse-declare-clause info clause clause)))
    (values info body doc)))

(defun declared-type (info name)
  (cdr (assoc name (decl-info-types info) :test #'string=)))

(defun declared-mode (info name)
  (or (cdr (assoc name (decl-info-modes info) :test #'string=)) :in))

(defun check-declare-kinds (form info allowed)
  (dolist (k (decl-info-kinds info))
    (unless (member k allowed)
      (dsl-error form "declare clause ~(~a~) is not allowed here" k))))

(defun check-declared-names (form info names)
  (dolist (entry (append (decl-info-types info) (decl-info-modes info)))
    (unless (member (car entry) names :test #'string=)
      (dsl-error form "declaration for unknown variable ~a" (car entry)))))

(defun parse-lambda-list (form lambda-list)
  (unless (listp lambda-list)
    (dsl-error form "lambda list expected"))
  (dolist (p lambda-list)
    (when (member p lambda-list-keywords)
      (error 'unsupported-construct :form form
             :message (format nil "~a is not supported in the MVP" p)))
    (unless (and (symbolp p) p (not (keywordp p)))
      (dsl-error form "parameter name expected, got ~s" p)))
  (mapcar #'spelling lambda-list))

(defun make-params (form names info &key require-types)
  (loop for n in names
        for ty = (declared-type info n)
        do (when (and require-types (null ty))
             (dsl-error form "parameter ~a has no type; add (declare (type T ~a))" n n))
        collect (make-var-def :name n :kind :param :declared-ty ty
                              :mode (declared-mode info n) :source n)))

(defun parse-lambda (form)
  "(lambda (params) [declare] body...) -> lambda-expr."
  (check-arg-count form 1 nil)
  (let ((names (parse-lambda-list form (second form))))
    (multiple-value-bind (info body) (split-declares (cddr form) :allow-doc nil)
      (check-declare-kinds form info '(:types :values :modes :capture))
      (check-declared-names form info names)
      (make-lambda-expr :params (make-params form names info :require-types t)
                        :ret (if (decl-info-ret-p info) (decl-info-ret info) :void)
                        :body (parse-stmts body)
                        :capture (or (decl-info-capture info) :value)
                        :source form))))
