;;;; 25-intrinsics.lisp --- portable intrinsics (Haxe @:coreApi + _std model)
;;;;
;;;; An intrinsic has ONE signature (declared here) and one expansion per
;;;; backend (declared in src/backend/<lang>/intrinsics.lisp). An expansion is
;;;; a plist:
;;;;   :template "text with $param placeholders"  (CL: an s-expression)
;;;;   :op KEYWORD      emit as binary/unary operator through the precedence engine
;;;;   :function FN     (lambda (backend call args) ...) for special cases
;;;;   :includes :imports :uses   what the generated file must import
;;;;   :prelude (names...)        runtime helpers from the backend prelude
;;;;   :result-op KEYWORD         precedence class of a template result

(in-package :polyglot)

(defstruct intrinsic
  name          ; spelling
  params        ; list of (name spec)
  optional      ; list of (name spec) after &optional
  rest          ; name of the &rest parameter or NIL
  ret           ; type or (:type-of p) (:elem-of p) (:map-value-optional p) (:map-keys p)
  (expansions (make-hash-table)))

(defvar *intrinsics* (make-hash-table :test 'equal))

(defun parse-intrinsic-params (lambda-list)
  (let ((mode :required) (req '()) (opt '()) (rest nil))
    (dolist (p lambda-list)
      (cond ((eq p '&optional) (setf mode :optional))
            ((eq p '&rest) (setf mode :rest))
            ((eq mode :rest) (setf rest (spelling p)))
            (t (let ((entry (list (spelling (first p)) (second p))))
                 (if (eq mode :optional) (push entry opt) (push entry req))))))
    (values (nreverse req) (nreverse opt) rest)))

(defun register-intrinsic (name lambda-list ret)
  (multiple-value-bind (req opt rest) (parse-intrinsic-params lambda-list)
    (let* ((key (spelling name))
           (old (gethash key *intrinsics*))
           (new (make-intrinsic :name key :params req :optional opt :rest rest :ret ret)))
      (when old
        (setf (intrinsic-expansions new) (intrinsic-expansions old)))
      (setf (gethash key *intrinsics*) new))))

(defun define-intrinsic-expansion (name backend &rest plist)
  "Register the expansion PLIST of intrinsic NAME for BACKEND."
  (let ((intrinsic (or (gethash (spelling name) *intrinsics*)
                       (error "intrinsic ~a has no signature" name))))
    (setf (gethash backend (intrinsic-expansions intrinsic)) plist)
    name))

(defmacro define-intrinsic (name lambda-list ret &body expansions)
  "Declare the portable intrinsic NAME with parameters ((p spec)... [&optional
...] [&rest r]) and result type RET. EXPANSIONS are optional (backend template
&rest plist) entries; usually they live in the backend files."
  `(progn
     (register-intrinsic ',name ',lambda-list ',ret)
     ,@(loop for (backend template . plist) in expansions
             collect `(define-intrinsic-expansion
                          ',name ,backend :template ',template
                          ,@(loop for (k v) on plist by #'cddr append (list k `',v))))
     ',name))

(defun find-intrinsic (name)
  (gethash name *intrinsics*))

(defun intrinsic-expansion (intrinsic backend form)
  "The expansion plist of INTRINSIC for BACKEND; unsupported-construct if missing."
  (or (gethash backend (intrinsic-expansions intrinsic))
      (error 'unsupported-construct :form form :backend backend
             :message (format nil "intrinsic ~a has no expansion for ~(~a~)"
                              (intrinsic-name intrinsic) backend))))

(defun intrinsic-param-names (intrinsic)
  (append (mapcar #'first (intrinsic-params intrinsic))
          (mapcar #'first (intrinsic-optional intrinsic))))

(defun check-intrinsic-arity (intrinsic form nargs)
  (let ((min (length (intrinsic-params intrinsic)))
        (max (unless (intrinsic-rest intrinsic)
               (+ (length (intrinsic-params intrinsic)) (length (intrinsic-optional intrinsic))))))
    (unless (and (>= nargs min) (or (null max) (<= nargs max)))
      (dsl-error form "~a expects ~d~@[ to ~d~] argument~:p, got ~d"
                 (intrinsic-name intrinsic) min max nargs))))

(defun placeholder-char-p (ch)
  (or (alphanumericp ch) (member ch '(#\- #\_))))

(defun expand-template (template bindings)
  "Replace $name in the string TEMPLATE by the string bound to name in the
alist BINDINGS. $$ is a literal dollar sign."
  (with-output-to-string (out)
    (let ((i 0) (n (length template)))
      (loop while (< i n)
            do (let ((ch (char template i)))
                 (cond ((and (char= ch #\$) (< (1+ i) n) (char= #\$ (char template (1+ i))))
                        (write-char #\$ out) (incf i 2))
                       ((char= ch #\$)
                        (let* ((end (or (position-if-not #'placeholder-char-p template :start (1+ i)) n))
                               (key (subseq template (1+ i) end))
                               (value (assoc key bindings :test #'string=)))
                          (unless value (error "template ~s: unknown placeholder $~a" template key))
                          (write-string (cdr value) out)
                          (setf i end)))
                       (t (write-char ch out) (incf i))))))))

(defun expand-sexp-template (template bindings)
  "Substitute symbols named $name in the s-expression TEMPLATE."
  (cond ((and (symbolp template) template
              (char= #\$ (char (symbol-name template) 0)))
         (let ((value (assoc (string-downcase (subseq (symbol-name template) 1)) bindings
                             :test #'string=)))
           (if value (cdr value) (error "template: unknown placeholder ~a" template))))
        ((consp template)
         (cons (expand-sexp-template (car template) bindings)
               (expand-sexp-template (cdr template) bindings)))
        (t template)))

;;; The portable minimum set (plan.md K4). Expansions: src/backend/*/intrinsics.lisp.
(define-intrinsic print-line ((x :string)) :void)
(define-intrinsic format-string ((fmt :string) &rest args) :string)
(define-intrinsic length ((x :collection)) :i64)
(define-intrinsic string-byte-length ((s :string)) :i64)
(define-intrinsic string-char-count ((s :string)) :i64)
(define-intrinsic push ((item :any) (place :vec)) :void)
(define-intrinsic map-get ((m :map) (k :any)) (:map-value-optional m))
(define-intrinsic map-set ((m :map) (k :any) (v :any)) :void)
(define-intrinsic map-contains ((m :map) (k :any)) :bool)
(define-intrinsic map-keys-sorted ((m :map)) (:map-keys m))
(define-intrinsic string-concat (&rest parts) :string)
(define-intrinsic sqrt ((x :f64)) :f64)
(define-intrinsic abs ((x :number)) (:type-of x))
(define-intrinsic min ((a :number) (b :number)) (:type-of a))
(define-intrinsic max ((a :number) (b :number)) (:type-of a))
(define-intrinsic truncate ((a :number) &optional (b :integer)) :i64)
(define-intrinsic floor ((a :number) &optional (b :integer)) :i64)
(define-intrinsic mod ((a :integer) (b :integer)) (:type-of a))
(define-intrinsic rem ((a :integer) (b :integer)) (:type-of a))
(define-intrinsic to-float ((x :integer)) :f64)
(define-intrinsic int-to-string ((x :integer)) :string)
;; ASCII byte offsets; a slice borrows from its string (K1b)
(define-intrinsic string-find ((s :string) (ch :char) (start :integer)) :i64)
(define-intrinsic string-slice ((s :string) (start :integer) (end :integer)) (:view :string nil))
