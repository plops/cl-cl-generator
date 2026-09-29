;;;; 61-text.lisp --- helpers shared by the text backends (Python, C++, Rust, Go)

(in-package :polyglot)

(defgeneric backend-op-table (backend)
  (:documentation "The OP-TABLE of the backend for the precedence engine."))

(defvar *imports* nil
  "Hash table of import keys needed by the module being emitted (backend specific).")
(defvar *prelude-used* nil
  "List of prelude helper names used by the project being emitted.")

(defun note-import (key)
  (setf (gethash key *imports*) t)
  key)

(defun imports-list ()
  (sort (loop for k being the hash-keys of *imports* collect k) #'string< :key #'princ-to-string))

(defun note-prelude (name)
  (pushnew name *prelude-used* :test #'equal)
  name)

(defun ex (e)
  "Emit E with the current backend: (values string op)."
  (emit-expr *backend* e))

(defun ex-pair (e)
  (multiple-value-bind (s op) (ex e) (cons s op)))

(defun ex-str (e)
  (values (ex e)))

(defun operand (parent position e)
  "E emitted as an operand of PARENT at POSITION, parenthesized if needed."
  (let ((p (ex-pair e)))
    (operand-string (backend-op-table *backend*) parent position (car p) (cdr p) *mode*)))

(defun binary (op left right &optional token)
  (binary-string (backend-op-table *backend*) op (ex-pair left) (ex-pair right) *mode* :token token))

(defun unary (op e &optional token)
  (unary-string (backend-op-table *backend*) op (ex-pair e) *mode* :token token))

(defun receiver (e)
  "E as the receiver of a method call or field access."
  (postfix-receiver (backend-op-table *backend*) (ex-pair e) *mode*))

(defun comma-list (exprs)
  (format nil "~{~a~^, ~}" (mapcar #'ex-str exprs)))

(defun prim (string) (values string nil))

(defun template-bindings (e intrinsic)
  "Placeholder -> emitted argument (parenthesized unless primary) for E."
  (let* ((names (intrinsic-param-names intrinsic))
         (args (ir-args e))
         (fixed (loop for n in names for a in args
                      collect (cons n (operand :postfix :only a))))
         (rest (when (intrinsic-rest intrinsic)
                 (list (cons (intrinsic-rest intrinsic)
                             (comma-list (nthcdr (length names) args)))))))
    (append fixed rest)))

(defun apply-expansion-metadata (plist)
  (dolist (i (getf plist :imports)) (note-import i))
  (dolist (i (getf plist :includes)) (note-import i))
  (dolist (p (getf plist :prelude)) (note-prelude p)))

(defun emit-intrinsic (e)
  "Expand the intrinsic call E with the expansion of the current backend."
  (let* ((intrinsic (ir-target e))
         (plist (intrinsic-expansion intrinsic *current-backend* (ir-source e))))
    (apply-expansion-metadata plist)
    (cond ((getf plist :function) (funcall (getf plist :function) e))
          ((getf plist :op)
           (if (= 1 (length (ir-args e)))
               (unary (getf plist :op) (first (ir-args e)))
               (binary (getf plist :op) (first (ir-args e)) (second (ir-args e)))))
          (t (values (expand-template (getf plist :template) (template-bindings e intrinsic))
                     (getf plist :result-op))))))

(defun define-expansions (backend specs)
  "SPECS: list of (intrinsic-name . plist) for BACKEND."
  (loop for (name . plist) in specs
        do (apply #'define-intrinsic-expansion name backend plist)))

(defun intrinsic-name-is (e &rest names)
  (and (typep e 'call-expr) (eq :intrinsic (ir-call-kind e))
       (member (ir-name e) names :test #'string=)))

(defun format-pieces (fmt)
  "Split a DSL format string into literal strings and placeholders
\(:plain or the precision integer). {{ and }} become { and }."
  (let ((pieces '()) (lit (make-string-output-stream)) (i 0) (n (length fmt)))
    (flet ((flush () (let ((s (get-output-stream-string lit)))
                       (when (plusp (length s)) (push s pieces)))))
      (loop while (< i n)
            do (let ((ch (char fmt i)))
                 (cond ((and (member ch '(#\{ #\})) (< (1+ i) n) (char= ch (char fmt (1+ i))))
                        (write-char ch lit) (incf i 2))
                       ((char= ch #\{)
                        (flush)
                        (let* ((end (position #\} fmt :start i))
                               (spec (subseq fmt (1+ i) end)))
                          (push (if (string= spec "") :plain
                                    (parse-integer spec :start 2 :end (1- (length spec))))
                                pieces)
                          (setf i (1+ end))))
                       (t (write-char ch lit) (incf i)))))
      (flush))
    (nreverse pieces)))

(defun method-call-target-name (method)
  (ir-target-name (root-method method)))
