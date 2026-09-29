;;;; 38-lower.lisp --- expression lowering for targets without block
;;;; expressions: if/let as value (E9), lambda lifting (E10), loop variable
;;;; captures (E3). E11 (comments in expressions) is handled by the parser.
;;;;
;;;; Capabilities used: :block-expressions (pass disabled when true),
;;;; :ternary (simple if-expr stays an expression), :multi-statement-lambda.

(in-package :polyglot)

(defvar *used-names* nil "Target names used in the current function.")

(defun collect-used-names (fn)
  (let ((table (make-hash-table :test 'equal)))
    (walk-nodes (lambda (n) (when (and (typep n 'var-def) (ir-target-name n))
                              (setf (gethash (ir-target-name n) table) t)))
                fn)
    table))

(defun fresh-temp (prefix ty source)
  (let ((name (loop for i from 1
                    for c = (target-name-for (format nil "~a-~d" prefix i) :variable)
                    unless (gethash c *used-names*) return c)))
    (setf (gethash name *used-names*) t)
    (make-var-def :name name :target-name name :ty ty :declared-ty ty :kind :local
                  :mutable t :source source)))

(defun var-ref (var)
  (make-var-expr :name (ir-name var) :binding var :ty (ir-ty var) :source (ir-name var)))

(defun hoist-if-p (e)
  "True when the if-expr E cannot stay an expression."
  (or (not (capability-p :ternary))
      (branch-needs-statements-p (ir-then e))
      (branch-needs-statements-p (ir-else e))))

(defun branch-needs-statements-p (e)
  (let ((found nil))
    (walk-nodes (lambda (n)
                  (cond ((typep n 'lambda-expr) :skip)
                        ((or (typep n 'block-expr) (and (typep n 'if-expr) (hoist-if-p n)))
                         (setf found t) :skip)))
                e)
    found))

(defun hoistable-p (e)
  (or (typep e 'block-expr) (and (typep e 'if-expr) (hoist-if-p e))))

(defun lower-into (e make-final)
  "Statements that compute E and hand the value to MAKE-FINAL (a function from
expression to statement). Hoistable forms become statements directly."
  (cond ((and (typep e 'if-expr) (hoist-if-p e))
         (multiple-value-bind (test pre) (lower-expr (ir-test e))
           (append pre (list (make-if-stmt :test test
                                           :then (lower-into (ir-then e) make-final)
                                           :else (lower-into (ir-else e) make-final)
                                           :source (ir-source e))))))
        ((typep e 'block-expr)
         (list (make-block-stmt :stmts (append (lower-stmt-list (ir-stmts e))
                                               (lower-into (ir-value e) make-final))
                                :scope t :source (ir-source e))))
        (t (multiple-value-bind (new pre) (lower-expr e)
             (append pre (list (funcall make-final new)))))))

(defun hoist-to-temp (e)
  "Replace the hoistable E by a temporary: (values temp-ref pre-statements)."
  (let ((tmp (fresh-temp "tmp" (ir-ty e) (ir-source e))))
    (unless (known-type-p (ir-ty e))
      (unsupported (ir-source e) "cannot lower this value: its type is unknown"))
    (values (var-ref tmp)
            (cons (make-decl-stmt :var tmp :source (ir-source e))
                  (lower-into e (lambda (v) (make-assign-stmt :place (var-ref tmp) :value v
                                                              :source (ir-source e))))))))

(defgeneric lower-expr (e)
  (:documentation "Lower E: (values new-expression statements-to-run-before)."))

(defun lower-child-slots (e)
  "Lower all expression children of E in slot order, collecting statements."
  (let ((pre '()))
    (loop for (slot kind) in (node-slot-specs e)
          do (case kind
               (:one (let ((v (slot-value e slot)))
                       (when (typep v 'expr)
                         (multiple-value-bind (new p) (lower-expr v)
                           (setf (slot-value e slot) new pre (append pre p))))))
               (:list (setf (slot-value e slot)
                            (loop for v in (slot-value e slot)
                                  collect (if (typep v '(or expr field-init))
                                              (multiple-value-bind (new p) (lower-expr v)
                                                (setf pre (append pre p))
                                                new)
                                              v))))))
    (values e pre)))

(defmethod lower-expr ((e node)) (lower-child-slots e))

(defmethod lower-expr ((e op-expr))
  (if (member (ir-op e) '(:and :or))
      (multiple-value-bind (left pre) (lower-expr (first (ir-args e)))
        (multiple-value-bind (right rpre) (lower-expr (second (ir-args e)))
          (when rpre
            (unsupported (ir-source e) "the right operand of ~(~a~) needs statements; bind it with let first"
                         (ir-op e)))
          (setf (ir-args e) (list left right))
          (values e pre)))
      (lower-child-slots e)))

(defmethod lower-expr ((e if-expr))
  (if (hoist-if-p e)
      (hoist-to-temp e)
      (multiple-value-bind (test pre) (lower-expr (ir-test e))
        (setf (ir-test e) test)
        (values e pre))))

(defmethod lower-expr ((e block-expr))
  (hoist-to-temp e))

(defun loop-vars-captured (lambda)
  "Loop var-defs referenced in the body of LAMBDA (defined outside of it)."
  (let ((own '()) (refs '()))
    (walk-nodes (lambda (n)
                  (when (typep n 'var-def) (push n own))
                  (when (and (typep n 'var-expr) (typep (ir-binding n) 'var-def)
                             (eq :loop (ir-kind (ir-binding n))))
                    (pushnew (ir-binding n) refs)))
                lambda)
    (reverse (set-difference refs own))))

(defun single-expression-body-p (lambda)
  (let ((body (ir-body lambda)))
    (and (= 1 (length body)) (typep (first body) '(or return-stmt expr-stmt))
         (not (branch-needs-statements-p (first body))))))

(defmethod lower-expr ((e lambda-expr))
  (setf (ir-captures e) (loop-vars-captured e)
        (ir-body e) (lower-stmt-list (ir-body e)))
  (if (or (capability-p :multi-statement-lambda) (single-expression-body-p e))
      (values e '())
      (let ((var (fresh-temp "local-fn" (ir-ty e) (ir-source e))))
        (setf (ir-mutable var) nil)
        (values (var-ref var) (list (make-local-fn-stmt :var var :fn e :source (ir-source e)))))))
