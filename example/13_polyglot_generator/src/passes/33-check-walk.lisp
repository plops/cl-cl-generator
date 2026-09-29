;;;; 33-check-walk.lisp --- the check pass: walk all bodies

(in-package :polyglot)

(defun check-call-args (args params)
  (loop for a in args for p in params
        do (case (ir-mode p)
             (:sink (check-ownership a (format nil "argument ~a (:sink)" (ir-name p))))
             (:inout (unless (place-expr-p a)
                       (dsl-error (ir-source a) "argument ~a is :inout and needs a variable or place"
                                  (ir-name p)))
                     (check-mutable-place a (format nil "argument ~a (:inout)" (ir-name p)))))))

(defun check-node (n)
  (typecase n
    (decl-stmt (check-ownership (ir-init n) (format nil "initial value of ~a" (ir-name (ir-var n)))
                                (ir-ty (ir-var n))))
    (assign-stmt (check-mutable-place (ir-place n) "setf")
                 (check-ownership (ir-value n) "assigned value" (ir-ty (ir-place n))))
    (op-assign-stmt (check-mutable-place (ir-place n) "incf/decf"))
    (return-stmt (check-return-ownership n))
    (for-each-stmt (setf (gethash (ir-var n) *loop-seqs*) (ir-seq n)))
    (lit-expr (when (eq :nil (ir-ty n))
                (dsl-error (ir-source n) "nil needs a known optional or collection type (E7)")))
    (call-expr (case (ir-call-kind n)
                 (:intrinsic (check-intrinsic-call n))
                 ((:function :extern) (check-call-args (ir-args n) (ir-params (ir-target n))))))
    (method-call-expr (check-method-call n))
    (make-expr (dolist (i (ir-inits n))
                 (check-ownership (ir-value i) (format nil "field ~a" (ir-name i))
                                  (ir-ty (find-field (ir-target n) (ir-name i))))))
    (vec-expr (dolist (x (ir-elems n)) (check-ownership x "vec element")))
    (own-expr (when (eq :box (ir-kind n)) (check-ownership (ir-value n) "boxed value"))
              (when (eq :some (ir-kind n)) (check-ownership (ir-value n) "optional value")))
    (super-expr (check-call-args (ir-args n) (rest (ir-params (ir-method n)))))))

(defun check-method-call (n)
  (let* ((m (ir-target n)) (recv (method-receiver m)))
    (case (ir-mode recv)
      (:inout (when (place-expr-p (ir-receiver n))
                (check-mutable-place (ir-receiver n) (format nil "method ~a (:inout receiver)" (ir-name m)))))
      (:sink (check-ownership (ir-receiver n) (format nil "method ~a (:sink receiver)" (ir-name m)))))
    (check-call-args (ir-args n) (rest (ir-params m)))))

(defun all-paths-return-p (stmts)
  (let ((last (car (last stmts))))
    (typecase last
      (return-stmt t)
      ((or raw-stmt target-form-stmt) t)
      (if-stmt (and (all-paths-return-p (ir-then last)) (all-paths-return-p (ir-else last))))
      (if-let-stmt (and (all-paths-return-p (ir-then last)) (all-paths-return-p (ir-else last))))
      (block-stmt (all-paths-return-p (ir-stmts last)))
      (t nil))))

(defun reference-candidates (fn)
  "Parameters that are passed by reference in Rust: borrowed types and non-copy
:in/:inout parameters (the receiver is handled by elision)."
  (loop for p in (ir-params fn)
        when (and (not (ir-receiver-p p))
                  (or (borrowed-type-p (ir-ty p))
                      (and (member (ir-mode p) '(:in :inout)) (not (copy-type-p (ir-ty p))))))
        collect (ir-name p)))

(defun check-borrows (fn)
  "K1b: a borrowed result needs an unambiguous source."
  (dolist (b (ir-borrows-from fn))
    (unless (find b (ir-params fn) :key #'ir-name :test #'string=)
      (dsl-error (ir-source fn) "borrows-from ~a: no such parameter" b)))
  (when (and (borrowed-type-p (ir-ret fn)) (null (ir-borrows-from fn))
             (not (eq :static (third (ir-ret fn)))))
    (let ((recv (and (typep fn 'method-item) (method-receiver fn)))
          (cands (reference-candidates fn)))
      (unless (or (and recv (member (ir-mode recv) '(:in :inout)))
                  (= 1 (length cands)))
        (dsl-error (ir-source fn)
                   "~a returns a borrowed ~a but the source is ambiguous; add (declare (borrows-from ...)) with ~:[no reference parameter available~;one or more of: ~:*~{~a~^, ~}~]"
                   (ir-name fn) (type-string (ir-ret fn)) cands)))))

(defun check-function (fn)
  (check-borrows fn)
  (unless (or (eq :void (ir-ret fn)) (function-flag-p fn :abstract) (null (ir-body fn))
              (all-paths-return-p (ir-body fn)))
    (dsl-error (ir-source fn) "~a returns ~a but not every path ends in a return"
               (ir-name fn) (type-string (ir-ret fn))))
  (walk-nodes (lambda (n)
                (when (typep n 'lambda-expr)
                  (unless (or (eq :void (ir-ret n)) (all-paths-return-p (ir-body n)))
                    (dsl-error (ir-source n) "lambda does not return a value on every path")))
                (check-node n))
              fn))

(defun check-project (project)
  (let ((*loop-seqs* (make-hash-table)))
    (dolist (m (ir-modules project) project)
      (dolist (item (ir-items m))
        (typecase item
          (function-item (check-function item))
          ((or struct-item interface-item) (mapc #'check-function (ir-methods item)))
          (const-item (walk-nodes #'check-node item)))))))

(define-pass :check (:order 30) (project)
             "Semantic checks with messages that name the source form."
             (check-project project))
