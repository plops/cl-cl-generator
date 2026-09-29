;;;; stmt.lisp --- Python backend: statements

(in-package :polyglot)

(defun py-body (stmts)
  "Emit STMTS indented; an empty body (or one with only comments) gets pass (E2)."
  (with-indent ()
    (mapc (lambda (s) (emit-stmt *backend* s)) stmts)
    (when (every (lambda (s) (typep s 'comment-stmt)) stmts)
      (emit-line "pass"))))

(defmethod emit-stmt ((b python-backend) (s expr-stmt))
  (emit-line (ex-str (ir-expr s))))

(defmethod emit-stmt ((b python-backend) (s decl-stmt))
  (let ((var (ir-var s)) (init (ir-init s)))
    (cond ((typep init 'lambda-expr) (py-def (ir-target-name var) init))
          (init (emit-line "~a = ~a" (ir-target-name var) (ex-str init)))
          (t (emit-line "~a: ~a" (ir-target-name var) (py-type (ir-ty var)))))))

(defmethod emit-stmt ((b python-backend) (s assign-stmt))
  (emit-line "~a = ~a" (ex-str (ir-place s)) (ex-str (ir-value s))))

(defmethod emit-stmt ((b python-backend) (s op-assign-stmt))
  (emit-line "~a ~a= ~a" (ex-str (ir-place s)) (ecase (ir-op s) (:add "+") (:sub "-"))
             (ex-str (ir-value s))))

(defmethod emit-stmt ((b python-backend) (s block-stmt))
  (mapc (lambda (x) (emit-stmt b x)) (ir-stmts s)))

(defun py-if (s keyword)
  (emit-line "~a ~a:" keyword (ex-str (ir-test s)))
  (py-body (ir-then s))
  (let ((else (ir-else s)))
    (cond ((and (= 1 (length else)) (typep (first else) 'if-stmt)) (py-if (first else) "elif"))
          (else (emit-line "else:") (py-body else)))))

(defmethod emit-stmt ((b python-backend) (s if-stmt))
  (py-if s "if"))

(defmethod emit-stmt ((b python-backend) (s while-stmt))
  (emit-line "while ~a:" (ex-str (ir-test s)))
  (py-body (ir-body s)))

(defmethod emit-stmt ((b python-backend) (s for-range-stmt))
  (let ((start (ir-start s)))
    (emit-line "for ~a in range(~:[~a, ~;~*~]~a):" (ir-target-name (ir-var s))
               (and (typep start 'lit-expr) (eql 0 (ir-value start))) (ex-str start)
               (ex-str (ir-end s)))
    (py-body (ir-body s))))

(defmethod emit-stmt ((b python-backend) (s for-each-stmt))
  (emit-line "for ~a in ~a:" (ir-target-name (ir-var s)) (ex-str (ir-seq s)))
  (py-body (ir-body s)))

(defmethod emit-stmt ((b python-backend) (s return-stmt))
  (if (ir-value s)
      (emit-line "return ~a" (ex-str (ir-value s)))
      (emit-line "return")))

(defmethod emit-stmt ((b python-backend) (s break-stmt)) (emit-line "break"))
(defmethod emit-stmt ((b python-backend) (s continue-stmt)) (emit-line "continue"))

(defmethod emit-stmt ((b python-backend) (s comment-stmt))
  (dolist (l (ir-lines s)) (emit-line "# ~a" l)))

(defmethod emit-stmt ((b python-backend) (s raw-stmt))
  (emit-line (ir-text s)))

(defmethod emit-stmt ((b python-backend) (s target-form-stmt))
  (emit-line (ex-str (make-target-form-expr :backend (ir-backend s) :form (ir-form s)
                                            :source (ir-source s)))))

(defmethod emit-stmt ((b python-backend) (s if-let-stmt))
  (emit-line "if (~a := ~a) is not None:" (ir-target-name (ir-var s)) (ex-str (ir-expr s)))
  (py-body (ir-then s))
  (when (ir-else s)
    (emit-line "else:")
    (py-body (ir-else s))))

(defun py-def (name lam)
  (emit-line "def ~a(~{~a~^, ~}):" name (py-lambda-params lam))
  (py-body (ir-body lam)))

(defmethod emit-stmt ((b python-backend) (s local-fn-stmt))
  (py-def (ir-target-name (ir-var s)) (ir-fn s)))
