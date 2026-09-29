;;;; 39-order-args.lisp --- deterministic argument evaluation order (E8)
;;;;
;;;; C++ does not specify the order in which function arguments (and the
;;;; operands of most binary operators) are evaluated. When more than one
;;;; argument has side effects, those arguments are moved into temporaries in
;;;; left to right order. Enabled by the config key :unspecified-arg-order.

(in-package :polyglot)

(defparameter +impure-intrinsics+ '("print-line" "push" "map-set"))

(defun impure-p (e)
  "E may have side effects: calls of functions not declared (pure), methods,
funcall, and the mutating intrinsics."
  (let ((found nil))
    (walk-nodes (lambda (n)
                  (typecase n
                    (lambda-expr :skip)
                    (call-expr (when (case (ir-call-kind n)
                                       (:intrinsic (member (ir-name n) +impure-intrinsics+ :test #'string=))
                                       (:function (not (function-flag-p (ir-target n) :pure)))
                                       (t t))
                                 (setf found t)))
                    ((or method-call-expr funcall-expr super-expr)
                     (unless (and (typep n 'method-call-expr) (function-flag-p (ir-target n) :pure))
                       (setf found t)))))
                e)
    found))

(defun ordered-arg-slot (e)
  "The accessor of the argument list whose order matters, or NIL."
  (typecase e
    ((or call-expr method-call-expr funcall-expr super-expr) 'args)
    (vec-expr 'elems)
    (op-expr (unless (member (ir-op e) '(:and :or)) 'args))))

(defun hoist-impure-args (e)
  "Move the impure arguments of E into temporaries: returns the declarations."
  (let* ((slot (ordered-arg-slot e))
         (args (and slot (slot-value e slot))))
    (when (> (count-if #'impure-p args) 1)
      (let ((pre '()))
        (setf (slot-value e slot)
              (loop for a in args
                    collect (if (impure-p a)
                                (let ((tmp (fresh-temp "arg" (ir-ty a) (ir-source a))))
                                  (setf (ir-mutable tmp) nil)
                                  (push (make-decl-stmt :var tmp :init a :source (ir-source a)) pre)
                                  (var-ref tmp))
                                a)))
        (nreverse pre)))))

(defun order-expr (e)
  "Post-order: (values e statements). Conditional parts are left alone."
  (if (or (not (typep e 'expr)) (typep e '(or lambda-expr if-expr)))
      (values e '())
      (let ((pre '()))
        (unless (and (typep e 'op-expr) (member (ir-op e) '(:and :or)))
          (loop for (slot kind) in (node-slot-specs e)
                do (case kind
                     (:one (multiple-value-bind (new p) (order-expr (slot-value e slot))
                             (setf (slot-value e slot) new pre (append pre p))))
                     (:list (setf (slot-value e slot)
                                  (loop for v in (slot-value e slot)
                                        collect (multiple-value-bind (new p) (order-expr v)
                                                  (setf pre (append pre p))
                                                  new)))))))
        (values e (append pre (hoist-impure-args e))))))

(defun order-stmt-exprs (s)
  "Order the expression slots of S; returns the statements to run before S."
  (let ((pre '()))
    (unless (typep s 'while-stmt)           ; the test runs on every iteration
      (loop for (slot kind) in (node-slot-specs s)
            for v = (slot-value s slot)
            when (and (eq kind :one) (typep v 'expr))
            do (multiple-value-bind (new p) (order-expr v)
                 (setf (slot-value s slot) new pre (append pre p)))))
    pre))

(defun order-stmt-list (stmts)
  (loop for s in stmts
        append (let ((pre (order-stmt-exprs s)))
                 (loop for (slot kind) in (node-slot-specs s)
                       for v = (slot-value s slot)
                       when (and (eq kind :list) (every (lambda (x) (typep x 'stmt)) v))
                       do (setf (slot-value s slot) (order-stmt-list v)))
                 (append pre (list s)))))

(defun order-args-project (project)
  (dolist (m (ir-modules project) project)
    (dolist (item (ir-items m))
      (dolist (fn (typecase item
                    (function-item (list item))
                    ((or struct-item interface-item) (ir-methods item))))
        (let ((*used-names* (collect-used-names fn)))
          (setf (ir-body fn) (order-stmt-list (ir-body fn))))))))

(define-pass :order-args (:order 85 :when (config-get :unspecified-arg-order)) (project)
             "Evaluate side effecting arguments left to right via temporaries (E8)."
             (order-args-project project))
