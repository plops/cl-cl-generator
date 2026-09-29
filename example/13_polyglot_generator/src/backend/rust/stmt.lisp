;;;; stmt.lisp --- Rust backend: statements, tail expressions, closures

(in-package :polyglot)

(defvar *rs-ret* :void "Return type of the function being emitted.")

(defun same-place-p (a b)
  "A and B denote the same variable or field path."
  (cond ((and (typep a 'var-expr) (typep b 'var-expr)) (eq (ir-binding a) (ir-binding b)))
        ((and (typep a 'field-expr) (typep b 'field-expr))
         (and (eq (ir-target a) (ir-target b)) (same-place-p (ir-object a) (ir-object b))))
        (t nil)))

(defparameter +rs-assign-ops+ '((:add . "+=") (:sub . "-=") (:mul . "*=") (:div . "/=")
                                (:bitand . "&=") (:bitor . "|=") (:bitxor . "^=")))

(defmethod emit-stmt ((b rust-backend) (s assign-stmt))
  (let ((v (ir-value s)) (place (ir-place s)))
    (if (and (typep v 'op-expr) (assoc (ir-op v) +rs-assign-ops+) (same-place-p place (first (ir-args v))))
        ;; clippy::assign_op_pattern
        (emit-line "~a ~a ~a;" (rs-place place) (cdr (assoc (ir-op v) +rs-assign-ops+))
                   (operand (ir-op v) :right (second (ir-args v))))
        (emit-line "~a = ~a;" (rs-place place) (ex-str-for v (ir-ty place))))))

(defmethod emit-stmt ((b rust-backend) (s op-assign-stmt))
  (emit-line "~a ~a= ~a;" (rs-place (ir-place s)) (ecase (ir-op s) (:add "+") (:sub "-"))
             (ex-str (ir-value s))))

(defun rs-decl-annotation (var init)
  "Type annotation of a let: needed for integer literals, empty collections and
vecs of boxes (the coercion to Box<dyn T> needs the expected type)."
  (let ((ty (ir-ty var)))
    (when (or (null init)
              (and (int-type-p ty) (typep init '(or lit-expr op-expr)) (not (eq ty :i32)))
              (typep init 'map-expr)
              (and (typep init 'lit-expr) (eq :nil (ir-kind init)))
              (and (typep init 'vec-expr) (or (null (ir-elems init))
                                              (eq :box (type-head (ir-elem-type init))))))
      (rs-type ty))))

(defmethod emit-stmt ((b rust-backend) (s decl-stmt))
  (let* ((var (ir-var s)) (init (ir-init s)) (ann (rs-decl-annotation var init)))
    (emit-line "let ~:[~;mut ~]~a~@[: ~a~]~@[ = ~a~];" (ir-mutable var) (ir-target-name var) ann
               (and init (ex-str-for init (ir-ty var))))))

(defmethod emit-stmt ((b rust-backend) (s expr-stmt))
  (emit-line "~a;" (ex-str (ir-expr s))))

(defmethod emit-stmt ((b rust-backend) (s return-stmt))
  (if (ir-value s)
      (emit-line "return ~a;" (ex-str-for (ir-value s) *rs-ret*))
      (emit-line "return;")))

(defmethod emit-stmt ((b rust-backend) (s block-stmt))
  (if (ir-scope s)
      (with-block ("{" "}") (rs-stmts (ir-stmts s) nil))
      (rs-stmts (ir-stmts s) nil)))

(defmethod emit-stmt ((b rust-backend) (s if-stmt)) (rs-if s nil ""))

(defun rs-if (s tail prefix)
  (emit-line "~aif ~a {" prefix (ex-str (ir-test s)))
  (with-indent () (rs-stmts (ir-then s) tail))
  (let ((else (ir-else s)))
    (cond ((and (= 1 (length else)) (typep (first else) 'if-stmt)) (rs-if (first else) tail "} else "))
          (else (emit-line "} else {") (with-indent () (rs-stmts else tail)) (emit-line "}"))
          (t (emit-line "}")))))

(defmethod emit-stmt ((b rust-backend) (s while-stmt))
  (let ((test (ir-test s)))
    ;; clippy::while_true
    (with-block ((if (and (typep test 'lit-expr) (eq :bool (ir-kind test)) (ir-value test))
                     "loop {"
                     (format nil "while ~a {" (ex-str test)))
                 "}")
      (rs-stmts (ir-body s) nil))))

(defmethod emit-stmt ((b rust-backend) (s for-range-stmt))
  (with-block ((format nil "for ~a in ~a..~a {" (ir-target-name (ir-var s)) (ex-str (ir-start s))
                       (ex-str (ir-end s)))
               "}")
    (rs-stmts (ir-body s) nil)))

(defun rs-loop-head (s)
  (let* ((var (ir-var s)) (seq (ir-seq s)) (mode (ir-iter-mode s))
         (copy (copy-type-p (ir-ty var))) (name (ir-target-name var)))
    (setf (gethash var *rs-loop-modes*) mode)
    (ecase mode
      (:move (format nil "for ~a in ~a {" name (ex-str seq)))
      (:ref (format nil "for ~:[~;&~]~a in ~a {" copy name (rs-borrowed seq)))
      (:mut (format nil "for ~a in ~a {" name
                    (if (eq :mut (rs-ref-kind seq)) (format nil "~a.iter_mut()" (receiver seq))
                        (rs-borrowed seq :mut t)))))))

(defmethod emit-stmt ((b rust-backend) (s for-each-stmt))
  (with-block ((rs-loop-head s) "}")
    (rs-stmts (ir-body s) nil)))

(defmethod emit-stmt ((b rust-backend) (s break-stmt)) (emit-line "break;"))
(defmethod emit-stmt ((b rust-backend) (s continue-stmt)) (emit-line "continue;"))
(defmethod emit-stmt ((b rust-backend) (s comment-stmt))
  (dolist (l (ir-lines s)) (emit-line "// ~a" l)))
(defmethod emit-stmt ((b rust-backend) (s raw-stmt)) (emit-line (ir-text s)))
(defmethod emit-stmt ((b rust-backend) (s target-form-stmt))
  (emit-line (ex-str (make-target-form-expr :backend (ir-backend s) :form (ir-form s)
                                            :source (ir-source s)))))

(defun rs-if-let (s tail)
  (emit-line "if let Some(~a) = ~a {" (ir-target-name (ir-var s)) (ex-str (ir-expr s)))
  (with-indent () (rs-stmts (ir-then s) tail))
  (if (ir-else s)
      (progn (emit-line "} else {") (with-indent () (rs-stmts (ir-else s) tail)) (emit-line "}"))
      (emit-line "}")))

(defmethod emit-stmt ((b rust-backend) (s if-let-stmt)) (rs-if-let s nil))

(defun rs-tail (s)
  "Emit S as the tail (value) of a function body."
  (typecase s
    (return-stmt (when (ir-value s) (emit-line (ex-str-for (ir-value s) *rs-ret*))))
    (if-stmt (rs-if s t ""))
    (if-let-stmt (rs-if-let s t))
    (block-stmt (if (ir-scope s)
                    (with-block ("{" "}") (rs-stmts (ir-stmts s) t))
                    (rs-stmts (ir-stmts s) t)))
    (t (emit-stmt *backend* s))))

(defun let-and-return-p (decl ret)
  "let x = e; x at the end (clippy::let_and_return)."
  (and (typep decl 'decl-stmt) (typep ret 'return-stmt) (ir-init decl)
       (typep (ir-value ret) 'var-expr) (eq (ir-binding (ir-value ret)) (ir-var decl))))

(defun rs-stmts (stmts tail)
  "Emit STMTS; with TAIL the last statement is the value of the body."
  (loop for (s . rest) on stmts
        do (cond ((and tail rest (null (cdr rest)) (let-and-return-p s (first rest)))
                  (emit-line (ex-str-for (ir-init s) *rs-ret*))
                  (return))
                 ((and (null rest) (typep s 'block-stmt))
                  ;; the last scope of a body needs no braces
                  (rs-stmts (ir-stmts s) tail))
                 ((and tail (null rest)) (rs-tail s))
                 (t (emit-stmt *backend* s)))))

(defmethod emit-expr ((b rust-backend) (e block-expr))
  (let ((body (with-output-lines ()
                (with-indent ()
                  (rs-stmts (ir-stmts e) nil)
                  (emit-line (ex-str (ir-value e)))))))
    (values (format nil "{~%~a}" body) :block)))

(defmethod emit-expr ((b rust-backend) (e lambda-expr))
  (let* ((params (format nil "~{~a~^, ~}" (loop for p in (ir-params e)
                                                collect (format nil "~a: ~a" (ir-target-name p) (rs-param-type p)))))
         (move (if (eq :value (ir-capture e)) "move " ""))
         (*rs-ret* (ir-ret e))
         (body (ir-body e)))
    (values (if (and (= 1 (length body)) (typep (first body) 'return-stmt))
                (format nil "~a|~a| ~a" move params (ex-str-for (ir-value (first body)) (ir-ret e)))
                (format nil "~a|~a|~:[ -> ~a~;~*~] {~%~a}" move params (eq :void (ir-ret e)) (rs-type (ir-ret e))
                        (with-output-lines () (with-indent () (rs-stmts body t)))))
            :lambda)))
