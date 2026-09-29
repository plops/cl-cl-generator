;;;; 33-check.lisp --- semantic checks: ownership (E5), nil (E7), floats in
;;;; output (E14), string length (E1), missing returns, read-only parameters,
;;;; ambiguous borrows (K1b)

(in-package :polyglot)

(defvar *loop-seqs* nil "Hash table loop var-def -> sequence expression.")

(defun place-root (e)
  "The var-def a place expression is rooted at (through loop variables), or NIL."
  (typecase e
    (var-expr (let ((b (ir-binding e)))
                (when (typep b 'var-def)
                  (let ((seq (and *loop-seqs* (gethash b *loop-seqs*))))
                    (if seq (or (place-root seq) b) b)))))
    ((or field-expr aref-expr) (place-root (ir-object e)))))

(defun place-expr-p (e)
  (typep e '(or var-expr field-expr aref-expr)))

(defun check-ownership (e what &optional target-type)
  "E5: a non-copy value that is stored somewhere must be fresh or explicitly
cloned or moved. Storing into a borrowed TARGET-TYPE (view, ref) borrows."
  (when (and e (place-expr-p e) (known-type-p (ir-ty e)) (not (copy-type-p (ir-ty e)))
             (not (borrowed-type-p target-type))
             (not (typep (ir-binding-or-nil e) '(or function-item const-item))))
    (let ((src (form-string (ir-source e))))
      (dsl-error (ir-source e) "~a: ~a of type ~a is not a copy type; write (clone ~a) or (move ~a)"
                 what src (type-string (ir-ty e)) src src))))

(defun ir-binding-or-nil (e)
  (and (typep e 'var-expr) (ir-binding e)))

(defun check-mutable-place (e what)
  (let ((root (place-root e)))
    (cond ((typep (ir-binding-or-nil e) 'const-item)
           (dsl-error (ir-source e) "~a: constant ~a cannot be modified" what (ir-name e)))
          ((and root (member (ir-kind root) '(:param :receiver)) (eq :in (ir-mode root)))
           (dsl-error (ir-source e) "~a: parameter ~a is :in (read-only); declare (mode :inout ~a)"
                      what (ir-name root) (ir-name root))))))

(defun check-return-ownership (s)
  (let* ((v (ir-value s)) (root (and v (place-root v))))
    (when (and v (place-expr-p v) (known-type-p (ir-ty v)) (not (copy-type-p (ir-ty v)))
               (not (and (typep v 'var-expr) root
                         (or (eq :local (ir-kind root))
                             (and (eq :param (ir-kind root)) (eq :sink (ir-mode root)))))))
      (check-ownership v "return value"))))

(defun format-placeholders (fmt form)
  "List of placeholders in FMT: :plain for {} and the precision for {:.Nf}."
  (let ((out '()) (i 0) (n (length fmt)))
    (loop while (< i n)
          do (let ((ch (char fmt i)))
               (cond ((and (char= ch #\{) (< (1+ i) n) (char= #\{ (char fmt (1+ i)))) (incf i 2))
                     ((and (char= ch #\}) (< (1+ i) n) (char= #\} (char fmt (1+ i)))) (incf i 2))
                     ((char= ch #\{)
                      (let* ((end (or (position #\} fmt :start i)
                                      (dsl-error form "unterminated { in format string")))
                             (spec (subseq fmt (1+ i) end)))
                        (push (cond ((string= spec "") :plain)
                                    ((cl-ppcre:register-groups-bind ((#'parse-integer p))
                                                                    ("^:\\.(\\d+)f$" spec) p))
                                    (t (dsl-error form "unsupported format spec {~a}; use {} or {:.Nf}" spec)))
                              out)
                        (setf i (1+ end))))
                     ((char= ch #\}) (dsl-error form "single } in format string; write }}"))
                     (t (incf i)))))
    (nreverse out)))

(defun check-format-string (e)
  (let ((fmt (first (ir-args e))) (args (rest (ir-args e))) (form (ir-source e)))
    (unless (and (typep fmt 'lit-expr) (eq :string (ir-kind fmt)))
      (dsl-error form "format-string needs a literal format string"))
    (let ((specs (format-placeholders (ir-value fmt) form)))
      (unless (= (length specs) (length args))
        (dsl-error form "format string has ~d placeholder~:p but ~d argument~:p"
                   (length specs) (length args)))
      (loop for spec in specs for a in args for ty = (ir-ty a)
            do (cond ((eq ty :bool)
                      (dsl-error form "bool in format-string is not portable; use (if b \"true\" \"false\")"))
                     ((and (eq spec :plain) (float-type-p ty))
                      (dsl-error form "float with {} prints differently per target (E14); use {:.6f}"))
                     ((and (integerp spec) (known-type-p ty) (not (float-type-p ty)))
                      (dsl-error form "{:.~df} needs a float argument, got ~a" spec (type-string ty))))))))

(defun check-intrinsic-call (e)
  (let ((name (ir-name e)) (args (ir-args e)))
    (cond ((string= name "format-string") (check-format-string e))
          ((and (string= name "length") (eq :string (strip-indirection (ir-ty (first args)))))
           (dsl-error (ir-source e) "length of a string is not portable (E1); use string-byte-length or string-char-count"))
          ((string= name "push")
           (check-ownership (first args) "pushed item")
           (check-mutable-place (second args) "push"))
          ((string= name "map-set")
           (check-ownership (third args) "map value")
           (check-mutable-place (first args) "map-set")))))
