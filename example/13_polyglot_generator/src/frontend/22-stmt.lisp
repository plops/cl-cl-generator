;;;; 22-stmt.lisp --- parser: surface statements -> statement nodes

(in-package :polyglot)

(defun parse-stmt (form)
  "Parse FORM in statement position."
  (if (atom form)
      (make-expr-stmt :expr (parse-expr form) :source form)
      (with-macro-expansion (f form)
        (if (atom f)
            (parse-stmt f)
            (let ((parser (and (symbolp (car f)) (gethash (form-name (car f)) *stmt-forms*)))
                  (backend (extension-form-backend f)))
              (cond (backend (make-target-form-stmt :backend backend :form f :source f))
                    (parser (funcall parser f))
                    (t (make-expr-stmt :expr (parse-expr f) :source f))))))))

(defun parse-stmts (forms)
  (mapcar #'parse-stmt forms))

(defun binding-parts (form spec)
  "(name init) | (name) | name -> (values name-symbol init-form-or-:none)."
  (cond ((and (symbolp spec) spec (not (keywordp spec))) (values spec :none))
        ((and (consp spec) (symbolp (car spec)) (<= 1 (length spec) 2))
         (values (car spec) (if (cdr spec) (second spec) :none)))
        (t (dsl-error form "malformed binding ~s" spec))))

(defun check-parallel-let (form decls)
  "LET binds in parallel, the targets bind sequentially: an init that refers
to a name bound EARLIER in the same LET would see the new binding. Such a LET
must be written as LET*."
  (loop for d in decls
        for earlier = '() then (cons (ir-name (ir-var prev)) earlier)
        for prev = d
        do (when (ir-init d)
             (walk-nodes (lambda (n)
                           (when (and (typep n 'var-expr)
                                      (member (ir-name n) earlier :test #'string=))
                             (dsl-error form "init of ~a refers to ~a bound by the same let; use let*"
                                        (ir-name (ir-var d)) (ir-name n))))
                         (ir-init d)))))

(defun parse-let-bindings (form)
  "Returns (values decl-stmts body-forms) of a LET or LET* FORM."
  (unless (and (cdr form) (listp (second form)))
    (dsl-error form "let needs a binding list"))
  (multiple-value-bind (info body) (split-declares (cddr form) :allow-doc nil)
    (check-declare-kinds form info '(:types))
    (let ((decls (loop for spec in (second form)
                       collect (multiple-value-bind (sym init) (binding-parts form spec)
                                 (make-decl-stmt
                                  :var (make-var-def :name (spelling sym) :kind :local
                                                     :declared-ty (declared-type info (spelling sym)))
                                  :init (unless (eq init :none) (parse-expr init))
                                  :source spec)))))
      (check-declared-names form info (mapcar (lambda (d) (ir-name (ir-var d))) decls))
      (when (form-is (car form) "let")
        (check-parallel-let form decls))
      (values decls body))))

(defun parse-let-stmt (form)
  (multiple-value-bind (decls body) (parse-let-bindings form)
    (make-block-stmt :stmts (append decls (parse-stmts body)) :scope t :source form)))

(define-surface-form "let" (:stmt form) (parse-let-stmt form))
(define-surface-form "let*" (:stmt form) (parse-let-stmt form))

(defun parse-place (form place)
  (let ((node (parse-expr place)))
    (unless (typep node '(or var-expr field-expr aref-expr))
      (dsl-error form "~s is not a place (variable, dot or aref)" place))
    node))

(define-surface-form "setf" (:stmt form)
  (let ((pairs (cdr form)))
    (when (or (null pairs) (oddp (length pairs)))
      (dsl-error form "setf needs place/value pairs"))
    (let ((assigns (loop for (p v) on pairs by #'cddr
                         collect (make-assign-stmt :place (parse-place form p)
                                                   :value (parse-expr v) :source form))))
      (if (cdr assigns)
          (make-block-stmt :stmts assigns :scope nil :source form)
          (first assigns)))))

(macrolet ((incf-form (name op)
             `(define-surface-form ,name (:stmt form)
                (check-arg-count form 1 2)
                (make-incf-stmt :op ,op :place (parse-place form (second form))
                                :delta (if (cddr form)
                                           (parse-expr (third form))
                                           (make-lit-expr :value 1 :kind :int :source 1))
                                :source form))))
  (incf-form "incf" :add)
  (incf-form "decf" :sub))

(define-surface-form "if" (:stmt form)
  (check-arg-count form 2 3)
  (make-if-stmt :test (parse-expr (second form))
                :then (list (parse-stmt (third form)))
                :else (when (cdddr form) (list (parse-stmt (fourth form))))
                :source form))

(define-surface-form "when" (:stmt form)
  (check-arg-count form 1 nil)
  (make-when-stmt :test (parse-expr (second form)) :body (parse-stmts (cddr form))
                  :source form))

(define-surface-form "unless" (:stmt form)
  (check-arg-count form 1 nil)
  (make-when-stmt :test (parse-expr (second form)) :body (parse-stmts (cddr form))
                  :negate t :source form))

(define-surface-form "cond" (:stmt form)
  (when (null (cdr form))
    (dsl-error form "empty cond"))
  (make-cond-stmt
   :clauses (loop for c in (cdr form)
                  do (unless (consp c) (dsl-error form "malformed cond clause ~s" c))
                  collect (make-cond-clause :test (if (eq t (car c)) nil (parse-expr (car c)))
                                            :body (parse-stmts (cdr c)) :source c))
   :source form))

(define-surface-form "while" (:stmt form)
  (check-arg-count form 1 nil)
  (make-while-stmt :test (parse-expr (second form)) :body (parse-stmts (cddr form))
                   :source form))
