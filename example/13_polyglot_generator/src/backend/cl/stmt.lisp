;;;; stmt.lisp --- CL backend: statements -> S-expressions
;;;;
;;;; Statement lists become form lists; a run of declarations opens a LET*
;;;; around the rest of the list. A return in tail position is just the value,
;;;; any other return is (return-from <block> value).

(in-package :polyglot)

(defvar *cl-block* nil "Block name for non-tail returns in the current function.")

(defun cl-zero-value (ty)
  (cond ((int-type-p ty) 0)
        ((float-type-p ty) 0d0)
        ((eq ty :string) "")
        ((eq ty :char) #\Space)
        ((eq :vec (type-head ty)) (list (rt-sym "pg-vec")))
        ((eq :map (type-head ty)) '(make-hash-table :test 'equal))
        (t nil)))

(defun cl-progn (forms)
  (cond ((null forms) nil)
        ((null (cdr forms)) (first forms))
        (t `(progn ,@forms))))

(defun cl-binding (decl)
  (let ((var (ir-var decl)))
    (list (local-sym var)
          (if (ir-init decl) (cl-form (ir-init decl)) (cl-zero-value (ir-ty var))))))

(defun cl-stmt-forms (stmts &optional extra tail-p)
  "Forms for STMTS followed by the forms EXTRA. TAIL-P: the last statement is
in the tail position of a function."
  (cond ((null stmts) extra)
        ((typep (car stmts) 'decl-stmt)
         (let* ((decls (loop for s in stmts while (typep s 'decl-stmt) collect s))
                (rest (nthcdr (length decls) stmts)))
           (list `(,(if (cdr decls) 'let* 'let) ,(mapcar #'cl-binding decls)
                    ,@(or (cl-stmt-forms rest extra tail-p) '(nil))))))
        (t (append (cl-stmt (car stmts) (and tail-p (null (cdr stmts)) (null extra)))
                   (cl-stmt-forms (cdr stmts) extra tail-p)))))

(defgeneric cl-stmt (s tail-p)
  (:documentation "List of forms for the statement S."))

(defmethod cl-stmt ((s expr-stmt) tail-p)
  (declare (ignore tail-p))
  (list (cl-form (ir-expr s))))

(defmethod cl-stmt ((s return-stmt) tail-p)
  (let ((v (and (ir-value s) (cl-form (ir-value s)))))
    (cond (tail-p (when (ir-value s) (list v)))
          (t (list `(return-from ,*cl-block* ,v))))))

(defmethod cl-stmt ((s block-stmt) tail-p)
  (cl-stmt-forms (ir-stmts s) nil tail-p))

(defmethod cl-stmt ((s assign-stmt) tail-p)
  (declare (ignore tail-p))
  (list `(setf ,(cl-form (ir-place s)) ,(cl-form (ir-value s)))))

(defmethod cl-stmt ((s op-assign-stmt) tail-p)
  (declare (ignore tail-p))
  (let ((v (cl-form (ir-value s))))
    (list `(,(ecase (ir-op s) (:add 'incf) (:sub 'decf))
             ,(cl-form (ir-place s)) ,@(unless (eql v 1) (list v))))))

(defun cl-if-chain-p (s)
  (and (= 1 (length (ir-else s))) (typep (first (ir-else s)) 'if-stmt)))

(defun cl-cond-clauses (s tail-p)
  (cons `(,(cl-form (ir-test s)) ,@(cl-stmt-forms (ir-then s) nil tail-p))
        (cond ((cl-if-chain-p s) (cl-cond-clauses (first (ir-else s)) tail-p))
              ((ir-else s) (list `(t ,@(cl-stmt-forms (ir-else s) nil tail-p))))
              (t '()))))

(defmethod cl-stmt ((s if-stmt) tail-p)
  (let ((test (cl-form (ir-test s)))
        (then (cl-stmt-forms (ir-then s) nil tail-p))
        (else (cl-stmt-forms (ir-else s) nil tail-p)))
    (list (cond ((cl-if-chain-p s) `(cond ,@(cl-cond-clauses s tail-p)))
                ((and (null else) (consp test) (eq (car test) 'not))
                 `(unless ,(second test) ,@then))
                ((null else) `(when ,test ,@then))
                ((and (null (cdr then)) (null (cdr else))) `(if ,test ,(first then) ,(first else)))
                (t `(if ,test ,(cl-progn then) ,(cl-progn else)))))))

(defun loop-kw (name)
  "LOOP keyword NAME as a symbol of the generated package (prints unqualified)."
  (intern (string-upcase name) (scratch-package *cl-module*)))

(defun contains-continue-p (stmts)
  "True when STMTS contain a CONTINUE of the loop around them (not of an inner loop)."
  (let ((found nil))
    (dolist (s stmts found)
      (walk-nodes (lambda (n)
                    (typecase n
                      ((or while-stmt for-range-stmt for-each-stmt lambda-expr) :skip)
                      (continue-stmt (setf found t))))
                  s))))

(defun captured-by-lambda-p (var stmts)
  "A lambda in STMTS refers to VAR."
  (let ((found nil))
    (dolist (s stmts found)
      (walk-nodes (lambda (n)
                    (when (typep n 'lambda-expr)
                      (walk-nodes (lambda (m) (when (and (typep m 'var-expr) (eq var (ir-binding m)))
                                                (setf found t)))
                                  n)))
                  s))))

(defun cl-loop-body (stmts &optional var)
  "Body forms of a loop; a CONTINUE inside needs a block around one iteration.
A loop variable captured by a closure is rebound per iteration (E3): LOOP
updates one binding, the other targets capture a fresh value."
  (let* ((forms (cl-stmt-forms stmts))
         ;; E2: LOOP DO needs a form; comments alone print as nothing
         (forms (if (every (lambda (s) (typep s 'comment-stmt)) stmts) (append forms (list '(values))) forms))
         (forms (if (contains-continue-p stmts)
                    `((block ,(local-sym "pg-continue") ,@forms))
                    forms)))
    (if (and var (captured-by-lambda-p var stmts))
        (let ((sym (local-sym var))) `((let ((,sym ,sym)) ,@forms)))
        forms)))

(defmethod cl-stmt ((s while-stmt) tail-p)
  (declare (ignore tail-p))
  (list `(loop ,(loop-kw "while") ,(cl-form (ir-test s)) do ,@(cl-loop-body (ir-body s)))))

(defmethod cl-stmt ((s for-range-stmt) tail-p)
  (declare (ignore tail-p))
  (list `(loop ,(loop-kw "for") ,(local-sym (ir-var s)) ,(loop-kw "from") ,(cl-form (ir-start s))
          ,(loop-kw "below") ,(cl-form (ir-end s)) do ,@(cl-loop-body (ir-body s) (ir-var s)))))

(defmethod cl-stmt ((s for-each-stmt) tail-p)
  (declare (ignore tail-p))
  (list `(loop ,(loop-kw "for") ,(local-sym (ir-var s)) ,(loop-kw "across") ,(cl-form (ir-seq s))
          do ,@(cl-loop-body (ir-body s) (ir-var s)))))

(defmethod cl-stmt ((s break-stmt) tail-p)
  (declare (ignore tail-p))
  (list '(return)))

(defmethod cl-stmt ((s continue-stmt) tail-p)
  (declare (ignore tail-p))
  (list `(return-from ,(local-sym "pg-continue"))))

(defmethod cl-stmt ((s comment-stmt) tail-p)
  (declare (ignore tail-p))
  (list `(cl-cl-generator:comments ,@(ir-lines s))))

(defmethod cl-stmt ((s raw-stmt) tail-p)
  (declare (ignore tail-p))
  (list `(cl-cl-generator:raw ,(ir-text s))))

(defmethod cl-stmt ((s if-let-stmt) tail-p)
  (let ((var (local-sym (ir-var s))))
    (list `(let ((,var ,(cl-form (ir-expr s))))
             (if ,var
                 ,(cl-progn (cl-stmt-forms (ir-then s) nil tail-p))
                 ,(cl-progn (cl-stmt-forms (ir-else s) nil tail-p)))))))

(defun tree-contains-p (sym tree)
  (cond ((eq sym tree) t)
        ((consp tree) (or (tree-contains-p sym (car tree)) (tree-contains-p sym (cdr tree))))
        (t nil)))

(defun cl-function-body (stmts &key block)
  "Body forms of a function. BLOCK is the implicit block of a DEFUN/DEFMETHOD;
for lambdas (BLOCK NIL) a BLOCK is added when a non-tail return needs one."
  (let* ((*cl-block* (or block (local-sym "pg-lambda")))
         (forms (cl-stmt-forms stmts nil t)))
    (if (and (null block) (tree-contains-p *cl-block* forms))
        `((block ,*cl-block* ,@forms))
        forms)))
