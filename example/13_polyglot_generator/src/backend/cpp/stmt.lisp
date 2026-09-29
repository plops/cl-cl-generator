;;;; stmt.lisp --- C++ backend: statements and lambdas

(in-package :polyglot)

(defun cpp-stmts (stmts)
  "Emit STMTS; a scoped block that is the last statement is spliced (its names
are unique after rename, so no redeclaration can happen)."
  (loop for (s . rest) on stmts
        do (if (and (typep s 'block-stmt) (null rest))
               (cpp-stmts (ir-stmts s))
               (emit-stmt *backend* s))))

(defun cpp-block (header stmts &optional (close "}"))
  (with-block ((format nil "~a {" header) close)
    (cpp-stmts stmts)))

(defmethod emit-stmt ((b cpp-backend) (s expr-stmt))
  (emit-line "~a;" (ex-str (ir-expr s))))

(defun cpp-local-type (var)
  (let ((ty (ir-ty var)))
    (if (known-type-p ty) (cpp-type ty) "auto")))

(defmethod emit-stmt ((b cpp-backend) (s decl-stmt))
  (let* ((var (ir-var s))
         (const (and (not (ir-mutable var)) (ir-init s)
                     (not (member (type-head (ir-ty var)) '(:box :ref :mut-ref))))))
    (if (ir-init s)
        (emit-line "~:[~;const ~]~a ~a = ~a;" const (cpp-local-type var) (ir-target-name var)
                   (ex-str (ir-init s)))
        (emit-line "~a ~a{};" (cpp-local-type var) (ir-target-name var)))))

(defmethod emit-stmt ((b cpp-backend) (s assign-stmt))
  (emit-line "~a = ~a;" (ex-str (ir-place s)) (ex-str (ir-value s))))

(defmethod emit-stmt ((b cpp-backend) (s op-assign-stmt))
  (let ((v (ir-value s)))
    (if (and (typep v 'lit-expr) (eql 1 (ir-value v)))
        (emit-line "~a~a;" (ecase (ir-op s) (:add "++") (:sub "--")) (ex-str (ir-place s)))
        (emit-line "~a ~a= ~a;" (ex-str (ir-place s)) (ecase (ir-op s) (:add "+") (:sub "-"))
                   (ex-str v)))))

(defmethod emit-stmt ((b cpp-backend) (s block-stmt))
  (if (ir-scope s)
      (with-block ("{" "}") (cpp-stmts (ir-stmts s)))
      (cpp-stmts (ir-stmts s))))

(defun cpp-if (s prefix)
  (emit-line "~aif (~a) {" prefix (ex-str (ir-test s)))
  (with-indent () (cpp-stmts (ir-then s)))
  (let ((else (ir-else s)))
    (cond ((and (= 1 (length else)) (typep (first else) 'if-stmt)) (cpp-if (first else) "} else "))
          (else (emit-line "} else {") (with-indent () (cpp-stmts else)) (emit-line "}"))
          (t (emit-line "}")))))

(defmethod emit-stmt ((b cpp-backend) (s if-stmt)) (cpp-if s ""))

(defmethod emit-stmt ((b cpp-backend) (s while-stmt))
  (cpp-block (format nil "while (~a)" (ex-str (ir-test s))) (ir-body s)))

(defmethod emit-stmt ((b cpp-backend) (s for-range-stmt))
  (let ((i (ir-target-name (ir-var s))))
    (cpp-block (format nil "for (std::int64_t ~a = ~a; ~a < ~a; ++~a)" i (ex-str (ir-start s)) i
                       (operand :lt :right (ir-end s)) i)
               (ir-body s))))

(defmethod emit-stmt ((b cpp-backend) (s for-each-stmt))
  (cpp-block (format nil "for (~a ~a : ~a)" (if (eq :mut (ir-iter-mode s)) "auto&" "const auto&")
                     (ir-target-name (ir-var s)) (ex-str (ir-seq s)))
             (ir-body s)))

(defmethod emit-stmt ((b cpp-backend) (s return-stmt))
  (if (ir-value s)
      (emit-line "return ~a;" (ex-str (ir-value s)))
      (emit-line "return;")))

(defmethod emit-stmt ((b cpp-backend) (s break-stmt)) (emit-line "break;"))
(defmethod emit-stmt ((b cpp-backend) (s continue-stmt)) (emit-line "continue;"))

(defmethod emit-stmt ((b cpp-backend) (s comment-stmt))
  (dolist (l (ir-lines s)) (emit-line "// ~a" l)))

(defmethod emit-stmt ((b cpp-backend) (s raw-stmt)) (emit-line (ir-text s)))

(defmethod emit-stmt ((b cpp-backend) (s target-form-stmt))
  (emit-line (ex-str (make-target-form-expr :backend (ir-backend s) :form (ir-form s)
                                            :source (ir-source s)))))

(defmethod emit-stmt ((b cpp-backend) (s if-let-stmt))
  (let* ((var (ir-target-name (ir-var s)))
         (opt (format nil "~a_opt" var)))
    (emit-line "if (const auto ~a = ~a; ~a.has_value()) {" opt (ex-str (ir-expr s)) opt)
    (with-indent ()
      (emit-line "const auto& ~a = *~a;" var opt)
      (cpp-stmts (ir-then s)))
    (if (ir-else s)
        (progn (emit-line "} else {") (with-indent () (cpp-stmts (ir-else s))) (emit-line "}"))
        (emit-line "}"))))

(defun lambda-free-vars (lam)
  "Var-defs referenced in LAM but bound outside of it; second value: uses this."
  (let ((own '()) (refs '()) (this nil))
    (walk-nodes (lambda (n)
                  (when (typep n 'var-def) (push n own))
                  (when (and (typep n 'var-expr) (typep (ir-binding n) 'var-def))
                    (if (ir-receiver-p (ir-binding n)) (setf this t) (pushnew (ir-binding n) refs))))
                lam)
    (values (set-difference refs own) this)))

(defun cpp-capture-list (lam)
  (multiple-value-bind (free this) (lambda-free-vars lam)
    (let ((default (if (eq :ref (ir-capture lam)) "&" "=")))
      (format nil "[~{~a~^, ~}]" (append (when free (list default)) (when this (list "this")))))))

(defmethod emit-expr ((b cpp-backend) (e lambda-expr))
  (let ((body (with-output-lines (:unit "  ") (with-indent () (cpp-stmts (ir-body e))))))
    (values (format nil "~a(~{~a~^, ~}) -> ~a {~%~a}" (cpp-capture-list e)
                    (loop for p in (ir-params e)
                          collect (format nil "~a ~a" (cpp-param-type p) (ir-target-name p)))
                    (cpp-type (ir-ret e)) body)
            :lambda)))
