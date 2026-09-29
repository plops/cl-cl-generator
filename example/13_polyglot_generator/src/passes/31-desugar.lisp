;;;; 31-desugar.lisp --- when/unless/cond/dotimes/incf, target-case selection,
;;;; progn splicing and implicit tail returns

(in-package :polyglot)

(defun negate-expr (test source)
  (make-op-expr :op :not :args (list test) :source source))

(defun desugar-cond (node)
  (labels ((build (clauses)
             (when clauses
               (let ((c (car clauses)))
                 (if (null (ir-test c))
                     (ir-body c)
                     (list (make-if-stmt :test (ir-test c) :then (ir-body c)
                                         :else (build (cdr clauses))
                                         :source (ir-source c))))))))
    (let ((stmts (build (ir-clauses node))))
      (if (and stmts (null (cdr stmts)) (typep (car stmts) 'if-stmt))
          (car stmts)
          (make-block-stmt :stmts stmts :scope t :source (ir-source node))))))

(defun select-branch-or-fail (node)
  (let ((branch (select-target-branch node *current-backend*)))
    (unless branch
      (unsupported (ir-source node) "target-case has no branch for ~(~a~) and no t branch"
                   *current-backend*))
    branch))

(defun simplify-not (node)
  "(not (= a b)) -> (/= a b), (not (/= a b)) -> (= a b), (not (not x)) -> x
\(ruff SIM201/SIM202/SIM208, clippy nonminimal_bool)."
  (let ((arg (first (ir-args node))))
    (if (typep arg 'op-expr)
        (case (ir-op arg)
          (:eq (rebuild-node arg :op :ne))
          (:ne (rebuild-node arg :op :eq))
          (:not (first (ir-args arg)))
          (t node))
        node)))

(defun collapse-if (node)
  "(if a (if b body)) without else branches -> (if (and a b) body)
\(ruff SIM102, clippy collapsible_if)."
  (let ((then (ir-then node)))
    (if (and (null (ir-else node)) (= 1 (length then)) (typep (first then) 'if-stmt)
             (null (ir-else (first then))))
        (make-if-stmt :test (make-op-expr :op :and :args (list (ir-test node) (ir-test (first then)))
                                          :source (ir-source node))
                      :then (ir-then (first then)) :source (ir-source node))
        node)))

(defun desugar-node (node)
  (typecase node
    (op-expr (if (eq :not (ir-op node)) (simplify-not node) node))
    (if-stmt (collapse-if node))
    (when-stmt (collapse-if (make-if-stmt :test (if (ir-negate node)
                                                    (simplify-not (negate-expr (ir-test node) (ir-source node)))
                                                    (ir-test node))
                                          :then (ir-body node) :source (ir-source node))))
    (cond-stmt (desugar-cond node))
    (dotimes-stmt (make-for-range-stmt :var (ir-var node)
                                       :start (make-lit-expr :value 0 :kind :int :source 0)
                                       :end (ir-count node) :body (ir-body node)
                                       :source (ir-source node)))
    (incf-stmt (make-op-assign-stmt :op (ir-op node) :place (ir-place node)
                                    :value (ir-delta node) :source (ir-source node)))
    (target-case-stmt (make-block-stmt :stmts (ir-body (select-branch-or-fail node))
                                       :scope nil :source (ir-source node)))
    (target-case-expr (first (ir-body (select-branch-or-fail node))))
    (block-stmt (if (ir-scope node)
                    (rebuild-node node :stmts (splice-progns (ir-stmts node)))
                    node))
    ((or function-item lambda-expr) (add-tail-return node))
    (t node)))

(defun splice-progns (stmts)
  "Inline PROGN blocks (scope NIL) into the surrounding statement list."
  (loop for s in stmts
        if (and (typep s 'block-stmt) (not (ir-scope s)))
        append (splice-progns (ir-stmts s))
        else collect s))

(defun tail-return (stmts)
  "Turn the value of the last statement of STMTS into a return statement."
  (when stmts
    (let ((last (car (last stmts))))
      (append (butlast stmts)
              (list (typecase last
                      (expr-stmt (make-return-stmt :value (ir-expr last) :source (ir-source last)))
                      (if-stmt (rebuild-node last :then (tail-return (ir-then last))
                                             :else (tail-return (ir-else last))))
                      (if-let-stmt (rebuild-node last :then (tail-return (ir-then last))
                                                 :else (tail-return (ir-else last))))
                      (block-stmt (rebuild-node last :stmts (tail-return (ir-stmts last))))
                      (t last)))))))

(defun add-tail-return (fn)
  (let ((body (splice-progns (ir-body fn))))
    (if (eq :void (ir-ret fn))
        (rebuild-node fn :body body)
        (rebuild-node fn :body (tail-return body)))))

(defun desugar-list-slots (node)
  "Splice progn blocks in every statement list of NODE."
  (dolist (slot '(then else body))
    (when (and (slot-exists-p node slot) (slot-boundp node slot)
               (listp (slot-value node slot)))
      (setf (slot-value node slot) (splice-progns (slot-value node slot)))))
  node)

(define-pass :desugar (:order 10) (project)
             "Desugar surface conveniences into the core IR."
             (map-tree (lambda (n) (desugar-node (if (typep n 'stmt) (desugar-list-slots n) n)))
                       project))
