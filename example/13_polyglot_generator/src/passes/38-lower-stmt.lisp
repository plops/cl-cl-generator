;;;; 38-lower-stmt.lisp --- statement side of the lower pass

(in-package :polyglot)

(defun lower-stmt-list (stmts)
  (loop for s in stmts append (lower-stmt s)))

(defun lower-expr-slot (s accessor setter)
  "Lower the expression (ACCESSOR S); returns the statements to run before S."
  (let ((e (funcall accessor s)))
    (if (null e)
        '()
        (multiple-value-bind (new pre) (lower-expr e)
          (funcall setter new s)
          pre))))

(defgeneric lower-stmt (s)
  (:documentation "Lower S; returns the list of statements replacing it."))

(defmethod lower-stmt ((s stmt)) (list s))

(defmethod lower-stmt ((s decl-stmt))
  (let ((init (ir-init s)))
    (cond ((and init (hoistable-p init))
           (setf (ir-init s) nil (ir-mutable (ir-var s)) t)
           (cons s (lower-into init (lambda (v) (make-assign-stmt :place (var-ref (ir-var s))
                                                                  :value v :source (ir-source s))))))
          (t (append (lower-expr-slot s #'ir-init #'(setf ir-init)) (list s))))))

(defmethod lower-stmt ((s assign-stmt))
  (let ((pre (lower-expr-slot s #'ir-place #'(setf ir-place))))
    (append pre (lower-into (ir-value s)
                            (lambda (v) (make-assign-stmt :place (ir-place s) :value v
                                                          :source (ir-source s)))))))

(defmethod lower-stmt ((s op-assign-stmt))
  (append (lower-expr-slot s #'ir-place #'(setf ir-place))
          (lower-expr-slot s #'ir-value #'(setf ir-value))
          (list s)))

(defmethod lower-stmt ((s return-stmt))
  (if (ir-value s)
      (lower-into (ir-value s) (lambda (v) (make-return-stmt :value v :source (ir-source s))))
      (list s)))

(defmethod lower-stmt ((s expr-stmt))
  (lower-into (ir-expr s) (lambda (v) (make-expr-stmt :expr v :source (ir-source s)))))

(defmethod lower-stmt ((s block-stmt))
  (setf (ir-stmts s) (lower-stmt-list (ir-stmts s)))
  (list s))

(defmethod lower-stmt ((s if-stmt))
  (let ((pre (lower-expr-slot s #'ir-test #'(setf ir-test))))
    (setf (ir-then s) (lower-stmt-list (ir-then s))
          (ir-else s) (lower-stmt-list (ir-else s)))
    (append pre (list s))))

(defmethod lower-stmt ((s while-stmt))
  (when (lower-expr-slot s #'ir-test #'(setf ir-test))
    (unsupported (ir-source s) "the while test needs statements; compute it in the body"))
  (setf (ir-body s) (lower-stmt-list (ir-body s)))
  (list s))

(defmethod lower-stmt ((s for-range-stmt))
  (let ((pre (append (lower-expr-slot s #'ir-start #'(setf ir-start))
                     (lower-expr-slot s #'ir-end #'(setf ir-end)))))
    (setf (ir-body s) (lower-stmt-list (ir-body s)))
    (append pre (list s))))

(defmethod lower-stmt ((s for-each-stmt))
  (let ((pre (lower-expr-slot s #'ir-seq #'(setf ir-seq))))
    (setf (ir-body s) (lower-stmt-list (ir-body s)))
    (append pre (list s))))

(defmethod lower-stmt ((s if-let-stmt))
  (let ((pre (lower-expr-slot s #'ir-expr #'(setf ir-expr))))
    (setf (ir-then s) (lower-stmt-list (ir-then s))
          (ir-else s) (lower-stmt-list (ir-else s)))
    (append pre (list s))))

(defun lower-function (fn)
  (let ((*used-names* (collect-used-names fn)))
    (setf (ir-body fn) (lower-stmt-list (ir-body fn)))))

(defun lower-module-expr (e)
  (multiple-value-bind (new pre) (lower-expr e)
    (when pre
      (unsupported (ir-source e) "this module level value needs statements"))
    new))

(defun lower-project (project)
  (dolist (m (ir-modules project) project)
    (dolist (item (ir-items m))
      (typecase item
        (function-item (lower-function item))
        ((or struct-item interface-item) (mapc #'lower-function (ir-methods item)))
        (const-item (let ((*used-names* (make-hash-table :test 'equal)))
                      (setf (ir-value item) (lower-module-expr (ir-value item)))))))))

(define-pass :lower (:order 80 :when (not (capability-p :block-expressions))) (project)
             "Lower if/let in value position, lift multi-statement lambdas (E9, E10, E3)."
             (lower-project project))
