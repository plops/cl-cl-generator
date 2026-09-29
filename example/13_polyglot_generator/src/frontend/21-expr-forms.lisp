;;;; 21-expr-forms.lisp --- surface forms in value position

(in-package :polyglot)

(define-surface-form "dot" (:expr form)
  (check-arg-count form 2 nil)
  (let ((object (parse-expr (second form))))
    (dolist (field (cddr form) object)
      (unless (and (symbolp field) field (not (keywordp field)))
        (dsl-error form "field name expected, got ~s" field))
      (setf object (make-field-expr :object object :name (spelling field) :source form)))))

(define-surface-form "aref" (:expr form)
  (check-arg-count form 2)
  (make-aref-expr :object (parse-expr (second form)) :index (parse-expr (third form))
                  :source form))

(define-surface-form "if" (:expr form)
  (unless (= 4 (length form))
    (dsl-error form "if in value position needs a test, a then and an else form"))
  (make-if-expr :test (parse-expr (second form)) :then (parse-expr (third form))
                :else (parse-expr (fourth form)) :source form))

(defun parse-value-body (forms source)
  "FORMS in value position: all but the last are statements. Returns a
block-expr, or the plain expression when there is only one form."
  (when (null forms)
    (dsl-error source "empty body in value position"))
  (if (null (cdr forms))
      (parse-expr (car forms))
      (make-block-expr :stmts (mapcar #'parse-stmt (butlast forms))
                       :value (parse-expr (car (last forms)))
                       :source source)))

(define-surface-form "progn" (:expr form)
  (parse-value-body (cdr form) form))

(defun parse-let-expr (form)
  (multiple-value-bind (decls body) (parse-let-bindings form)
    (when (null body)
      (dsl-error form "let in value position needs a body"))
    (make-block-expr :stmts (append decls (mapcar #'parse-stmt (butlast body)))
                     :value (parse-expr (car (last body)))
                     :source form)))

(define-surface-form "let" (:expr form) (parse-let-expr form))
(define-surface-form "let*" (:expr form) (parse-let-expr form))

(define-surface-form "cond" (:expr form)
  (let ((clauses (cdr form)))
    (unless (and clauses (eq t (car (car (last clauses)))))
      (dsl-error form "cond in value position needs a final (t ...) clause"))
    (labels ((build (cs)
               (let ((c (car cs)))
                 (if (eq t (car c))
                     (parse-value-body (cdr c) form)
                     (make-if-expr :test (parse-expr (car c))
                                   :then (parse-value-body (cdr c) form)
                                   :else (build (cdr cs))
                                   :source c)))))
      (build clauses))))

(define-surface-form "vec-of" (:expr form)
  (check-arg-count form 1 nil)
  (make-vec-expr :elem-type (parse-type (second form))
                 :elems (mapcar #'parse-expr (cddr form)) :source form))

(define-surface-form "map-of" (:expr form)
  (check-arg-count form 2)
  (make-map-expr :key-type (parse-type (second form))
                 :value-type (parse-type (third form)) :source form))

(macrolet ((own (name kind)
             `(define-surface-form ,name (:expr form)
                (check-arg-count form 1)
                (make-own-expr :kind ,kind :value (parse-expr (second form)) :source form))))
  (own "box" :box)
  (own "clone" :clone)
  (own "move" :move)
  (own "some" :some))

(define-surface-form "call-super" (:expr form)
  (make-super-expr :args (mapcar #'parse-expr (cdr form)) :source form))

(define-surface-form "funcall" (:expr form)
  (check-arg-count form 1 nil)
  (make-funcall-expr :fn (parse-expr (second form))
                     :args (mapcar #'parse-expr (cddr form)) :source form))

(define-surface-form "lambda" (:expr form)
  (parse-lambda form))

(define-surface-form "comment" (:expr form)
  (make-comment-expr :lines (comment-lines form) :source form))

(define-surface-form "comments" (:expr form)
  (make-comment-expr :lines (comment-lines form) :source form))

(define-surface-form "raw" (:expr form)
  (unless (and (= 2 (length form)) (stringp (second form)))
    (dsl-error form "raw expects one string"))
  (make-raw-expr :text (second form) :source form))

(define-surface-form "target-case" (:expr form)
  (make-target-case-expr
   :branches (parse-target-case form
                                (lambda (forms)
                                  (unless (= 1 (length forms))
                                    (dsl-error form "target-case in value position needs one form per branch"))
                                  (list (parse-expr (first forms)))))
   :source form))

(defun comment-lines (form)
  (unless (and (cdr form) (every #'stringp (cdr form)))
    (dsl-error form "comment expects strings"))
  (loop for s in (cdr form)
        append (cl-ppcre:split "\\n" s)))
