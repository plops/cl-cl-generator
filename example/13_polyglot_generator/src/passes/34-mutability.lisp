;;;; 34-mutability.lisp --- local mutability inference (K1)
;;;;
;;;; A local (or :sink parameter) is MUTABLE when it is assigned after its
;;;; initialization, when one of its fields or elements is assigned, when it is
;;;; the container of push/map-set, when it is passed as :inout or is the
;;;; receiver of an :inout method. A dolist gets ITER-MODE :mut when the loop
;;;; variable is mutated through, :ref when it iterates over a place and :move
;;;; when it iterates over a fresh value.

(in-package :polyglot)

(defvar *loop-stmts* nil "Hash table loop var-def -> for-each-stmt.")

(defun mark-mutable-var (var)
  (when (member (ir-kind var) '(:local :param))
    (unless (and (eq :param (ir-kind var)) (member (ir-mode var) '(:in :inout)))
      (setf (ir-mutable var) t))))

(defun mark-place (e &key direct)
  "Mark the root of the place E as mutable. DIRECT is true when E itself (not a
field or element of it) is assigned."
  (typecase e
    (var-expr
     (let* ((b (ir-binding e))
            (loop-stmt (and (typep b 'var-def) *loop-stmts* (gethash b *loop-stmts*))))
       (cond ((not (typep b 'var-def)) nil)
             ((and loop-stmt direct)
              (dsl-error (ir-source e) "cannot assign to the loop variable ~a" (ir-name b)))
             (loop-stmt (setf (ir-iter-mode loop-stmt) :mut)
              (mark-place (ir-seq loop-stmt)))
             (t (mark-mutable-var b)))))
    ((or field-expr aref-expr) (mark-place (ir-object e)))))

(defun mark-inout-args (args params)
  (loop for a in args for p in params
        when (or (eq :inout (ir-mode p)) (eq :mut-ref (type-head (ir-ty p))))
        do (mark-place a)))

(defun mutability-node (n)
  (typecase n
    (for-each-stmt (setf (gethash (ir-var n) *loop-stmts*) n))
    ((or assign-stmt op-assign-stmt) (mark-place (ir-place n) :direct t))
    (call-expr
     (case (ir-call-kind n)
       (:intrinsic (cond ((string= (ir-name n) "push") (mark-place (second (ir-args n))))
                         ((string= (ir-name n) "map-set") (mark-place (first (ir-args n))))))
       ((:function :extern) (mark-inout-args (ir-args n) (ir-params (ir-target n))))))
    (method-call-expr
     (let ((m (ir-target n)))
       (when (eq :inout (ir-mode (method-receiver m)))
         (mark-place (ir-receiver n)))
       (mark-inout-args (ir-args n) (rest (ir-params m)))))
    (super-expr (mark-inout-args (ir-args n) (rest (ir-params (ir-method n)))))))

(defun finish-iter-modes (node)
  (walk-nodes (lambda (n)
                (when (and (typep n 'for-each-stmt) (not (eq :mut (ir-iter-mode n))))
                  (setf (ir-iter-mode n) (if (place-expr-p (ir-seq n)) :ref :move))))
              node))

(defun infer-mutability (project)
  (let ((*loop-stmts* (make-hash-table)))
    (walk-nodes (lambda (n)
                  (when (typep n 'var-def) (setf (ir-mutable n) nil))
                  (when (typep n 'for-each-stmt) (setf (ir-iter-mode n) nil))
                  (mutability-node n))
                project)
    (finish-iter-modes project)))

(define-pass :mutability (:order 40) (project)
             "Infer which locals must be mutable (let mut / non-const)."
             (infer-mutability project))
