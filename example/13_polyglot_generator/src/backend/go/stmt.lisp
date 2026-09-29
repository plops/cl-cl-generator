;;;; stmt.lisp --- Go backend: statements and function literals

(in-package :polyglot)

(defvar *go-loop-pointers* nil "Loop var-defs that are bound to &v[i].")
(defvar *go-function* nil "Function whose body is emitted.")

(defun go-stmts (stmts)
  (loop for (s . rest) on stmts
        do (if (and (typep s 'block-stmt) (null rest))
               (go-stmts (ir-stmts s))
               (emit-stmt *backend* s))))

(defun go-block (header stmts)
  (with-block ((format nil "~a {" header) "}") (go-stmts stmts)))

(defmethod emit-stmt ((b go-backend) (s expr-stmt)) (emit-line (ex-str (ir-expr s))))

(defun literal-only-p (e)
  (or (typep e 'lit-expr)
      (and (typep e 'op-expr) (every #'literal-only-p (ir-args e)))))

(defmethod emit-stmt ((b go-backend) (s decl-stmt))
  (let* ((var (ir-var s)) (init (ir-init s)) (name (ir-target-name var)) (ty (ir-ty var)))
    (cond ((null init) (emit-line "var ~a ~a" name (go-type ty)))
          ((and (int-type-p ty) (literal-only-p init))
           (emit-line "var ~a ~a = ~a" name (go-type ty) (ex-str init)))
          (t (emit-line "~a := ~a" name (go-arg init (make-var-def :name "v" :kind :param :mode :in :ty ty)))))))

(defmethod emit-stmt ((b go-backend) (s assign-stmt))
  (emit-line "~a = ~a" (ex-str (ir-place s))
             (go-arg (ir-value s) (make-var-def :name "v" :kind :param :mode :in :ty (ir-ty (ir-place s))))))

(defmethod emit-stmt ((b go-backend) (s op-assign-stmt))
  (let ((v (ir-value s)))
    (if (and (typep v 'lit-expr) (eql 1 (ir-value v)))
        (emit-line "~a~a" (operand :postfix :only (ir-place s)) (ecase (ir-op s) (:add "++") (:sub "--")))
        (emit-line "~a ~a= ~a" (ex-str (ir-place s)) (ecase (ir-op s) (:add "+") (:sub "-")) (ex-str v)))))

(defmethod emit-stmt ((b go-backend) (s block-stmt))
  (if (ir-scope s)
      (with-block ("{" "}") (go-stmts (ir-stmts s)))
      (go-stmts (ir-stmts s))))

(defun go-if (s prefix)
  (emit-line "~aif ~a {" prefix (ex-str (ir-test s)))
  (with-indent () (go-stmts (ir-then s)))
  (let ((else (ir-else s)))
    (cond ((and (= 1 (length else)) (typep (first else) 'if-stmt)) (go-if (first else) "} else "))
          (else (emit-line "} else {") (with-indent () (go-stmts else)) (emit-line "}"))
          (t (emit-line "}")))))

(defmethod emit-stmt ((b go-backend) (s if-stmt)) (go-if s ""))

(defmethod emit-stmt ((b go-backend) (s while-stmt))
  (let ((test (ir-test s)))
    (go-block (if (and (typep test 'lit-expr) (eq :bool (ir-kind test)) (ir-value test))
                  "for"
                  (format nil "for ~a" (ex-str test)))
              (ir-body s))))

(defmethod emit-stmt ((b go-backend) (s for-range-stmt))
  (let ((i (ir-target-name (ir-var s))))
    (go-block (format nil "for ~a := int64(~a); ~a < ~a; ~a++" i (ex-str (ir-start s)) i
                      (operand :lt :right (ir-end s)) i)
              (ir-body s))))

(defmethod emit-stmt ((b go-backend) (s for-each-stmt))
  (let ((var (ir-var s)) (seq (ir-seq s)))
    (if (and (eq :mut (ir-iter-mode s)) (named-type-p (ir-ty var)))
        ;; mutate the elements in place: bind a pointer to v[i]
        (let ((i (format nil "~a_i" (ir-target-name var))) (v (receiver seq)))
          (push var *go-loop-pointers*)
          (with-block ((format nil "for ~a := range ~a {" i v) "}")
            (emit-line "~a := &~a[~a]" (ir-target-name var) v i)
            (go-stmts (ir-body s))))
        (go-block (format nil "for _, ~a := range ~a" (ir-target-name var) (ex-str seq)) (ir-body s)))))

(defmethod emit-stmt ((b go-backend) (s return-stmt))
  (if (ir-value s)
      (emit-line "return ~a" (go-arg (ir-value s) (make-var-def :name "r" :kind :param :mode :in
                                                                :ty (ir-ret *go-function*))))
      (emit-line "return")))

(defmethod emit-stmt ((b go-backend) (s break-stmt)) (emit-line "break"))
(defmethod emit-stmt ((b go-backend) (s continue-stmt)) (emit-line "continue"))
(defmethod emit-stmt ((b go-backend) (s comment-stmt)) (dolist (l (ir-lines s)) (emit-line "// ~a" l)))
(defmethod emit-stmt ((b go-backend) (s raw-stmt)) (emit-line (ir-text s)))
(defmethod emit-stmt ((b go-backend) (s target-form-stmt))
  (emit-line (ex-str (make-target-form-expr :backend (ir-backend s) :form (ir-form s) :source (ir-source s)))))

(defmethod emit-stmt ((b go-backend) (s if-let-stmt))
  (let* ((var (ir-target-name (ir-var s))) (e (ir-expr s)))
    (if (intrinsic-name-is e "map-get")
        (emit-line "if ~a, ok := ~a[~a]; ok {" var (receiver (first (ir-args e))) (ex-str (second (ir-args e))))
        (progn (emit-line "if ~a_ptr := ~a; ~a_ptr != nil {" var (ex-str e) var)
               (with-indent () (emit-line "~a := *~a_ptr" var var))))
    (with-indent () (go-stmts (ir-then s)))
    (if (ir-else s)
        (progn (emit-line "} else {") (with-indent () (go-stmts (ir-else s))) (emit-line "}"))
        (emit-line "}"))))

(defmethod emit-expr ((b go-backend) (e lambda-expr))
  (let ((*go-function* e))
    (prim (format nil "func(~{~a~^, ~})~@[ ~a~] {~%~a}"
                  (loop for p in (ir-params e) collect (format nil "~a ~a" (ir-target-name p) (go-param-type p)))
                  (let ((r (go-type (ir-ret e)))) (and (plusp (length r)) r))
                  (with-output-lines (:unit "	") (with-indent () (go-stmts (ir-body e))))))))

(defmethod emit-expr ((b go-backend) (e if-expr))
  (unsupported (ir-source e) "if as value must be lowered for go"))
