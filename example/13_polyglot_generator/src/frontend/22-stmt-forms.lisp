;;;; 22-stmt-forms.lisp --- loops, jumps, comments and other statements

(in-package :polyglot)

(defun loop-header (form)
  "(dotimes (var expr) ...) -> (values var-symbol expr-form)."
  (let ((h (second form)))
    (unless (and (consp h) (= 2 (length h)) (symbolp (first h)) (first h))
      (dsl-error form "~a needs (var expr)" (form-name (car form))))
    (values (first h) (second h))))

(define-surface-form "dotimes" (:stmt form)
  (multiple-value-bind (var count) (loop-header form)
    (make-dotimes-stmt :var (make-var-def :name (spelling var) :kind :loop :declared-ty :i64)
                       :count (parse-expr count) :body (parse-stmts (cddr form))
                       :source form)))

(define-surface-form "dolist" (:stmt form)
  (multiple-value-bind (var seq) (loop-header form)
    (make-for-each-stmt :var (make-var-def :name (spelling var) :kind :loop)
                        :seq (parse-expr seq) :body (parse-stmts (cddr form))
                        :source form)))

(define-surface-form "return" (:stmt form)
  (check-arg-count form 0 1)
  (make-return-stmt :value (when (cdr form) (parse-expr (second form))) :source form))

(define-surface-form "break" (:stmt form)
  (check-arg-count form 0)
  (make-break-stmt :source form))

(define-surface-form "continue" (:stmt form)
  (check-arg-count form 0)
  (make-continue-stmt :source form))

(define-surface-form "progn" (:stmt form)
  (make-block-stmt :stmts (parse-stmts (cdr form)) :scope nil :source form))

(define-surface-form "if-let" (:stmt form)
  (check-arg-count form 2 3)
  (let ((h (second form)))
    (unless (and (consp h) (= 2 (length h)) (symbolp (first h)))
      (dsl-error form "if-let needs (var optional-expr)"))
    (make-if-let-stmt :var (make-var-def :name (spelling (first h)) :kind :local)
                      :expr (parse-expr (second h))
                      :then (list (parse-stmt (third form)))
                      :else (when (cdddr form) (list (parse-stmt (fourth form))))
                      :source form)))

(define-surface-form "comment" (:stmt form)
  (make-comment-stmt :lines (comment-lines form) :source form))

(define-surface-form "comments" (:stmt form)
  (make-comment-stmt :lines (comment-lines form) :source form))

(define-surface-form "raw" (:stmt form)
  (unless (and (= 2 (length form)) (stringp (second form)))
    (dsl-error form "raw expects one string"))
  (make-raw-stmt :text (second form) :source form))

(define-surface-form "target-case" (:stmt form)
  (make-target-case-stmt :branches (parse-target-case form #'parse-stmts) :source form))
