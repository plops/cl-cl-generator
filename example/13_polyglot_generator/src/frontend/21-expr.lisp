;;;; 21-expr.lisp --- parser: surface expressions -> expression nodes

(in-package :polyglot)

(defparameter +operators+
  '(("+" :add :nary) ("-" :sub :minus) ("*" :mul :nary) ("/" :div :nary2)
    ("=" :eq :binary) ("/=" :ne :binary) ("<" :lt :binary) ("<=" :le :binary)
    (">" :gt :binary) (">=" :ge :binary)
    ("and" :and :nary) ("or" :or :nary) ("not" :not :unary)
    ("logand" :bitand :nary) ("logior" :bitor :nary) ("logxor" :bitxor :nary)
    ("lognot" :bitnot :unary) ("shl" :shl :binary) ("shr" :shr :binary))
  "Surface operator name, abstract op keyword, arity class. The semantics
follow Common Lisp: and/or/not are logical, log* are bitwise.")

(defun operator-entry (head)
  (and (symbolp head) (assoc (form-name head) +operators+ :test #'string=)))

(defun parse-literal-atom (form)
  (etypecase form
    (integer (make-lit-expr :value form :kind :int :source form))
    (double-float (make-lit-expr :value form :kind :float :source form))
    (float (dsl-error form "single-float literal ~s: write ~sd0 (or use (pg:in-dsl))" form form))
    (string (make-lit-expr :value form :kind :string :source form))
    (character (make-lit-expr :value form :kind :char :source form))))

(defun parse-symbol-expr (form)
  (cond ((null form) (make-lit-expr :value nil :kind :nil :source form))
        ((keywordp form) (dsl-error form "keyword ~s is not an expression" form))
        ((eq form t) (dsl-error form "use true instead of t"))
        ((form-is form "true") (make-lit-expr :value t :kind :bool :source form))
        ((form-is form "false") (make-lit-expr :value nil :kind :bool :source form))
        (t (make-var-expr :name (spelling form) :source form))))

(defun parse-expr (form)
  "Parse FORM in value position."
  (cond ((symbolp form) (parse-symbol-expr form))
        ((atom form) (parse-literal-atom form))
        ((not (symbolp (car form)))
         (dsl-error form "form must start with a symbol"))
        (t (with-macro-expansion (f form)
             (if (atom f) (parse-expr f) (parse-compound-expr f))))))

(defun parse-compound-expr (form)
  (let* ((head (car form))
         (parser (gethash (form-name head) *expr-forms*))
         (backend (extension-form-backend form)))
    (cond (backend (make-target-form-expr :backend backend :form form :source form))
          (parser (funcall parser form))
          ((operator-entry head) (parse-operator form))
          ((make-form-p form) (parse-make form))
          (t (make-call-expr :name (spelling head)
                             :args (mapcar #'parse-expr (cdr form))
                             :source form)))))

(defun fold-left (op args source)
  (reduce (lambda (a b) (make-op-expr :op op :args (list a b) :source source))
          args))

(defun parse-operator (form)
  (destructuring-bind (name op arity) (operator-entry (car form))
    (let ((args (mapcar #'parse-expr (cdr form)))
          (n (length (cdr form))))
      (flet ((need (ok what)
               (unless ok (dsl-error form "~a expects ~a" name what))))
        (ecase arity
          (:nary (need (>= n 1) "at least one argument")
                 (if (= n 1) (first args) (fold-left op args form)))
          (:nary2 (need (>= n 2) "at least two arguments")
                  (fold-left op args form))
          (:minus (need (>= n 1) "at least one argument")
                  (if (= n 1)
                      (make-op-expr :op :neg :args args :source form)
                      (fold-left op args form)))
          (:binary (need (= n 2) "exactly two arguments")
                   (make-op-expr :op op :args args :source form))
          (:unary (need (= n 1) "exactly one argument")
                  (make-op-expr :op op :args args :source form)))))))

(defun keyword-plist-p (list)
  (and (evenp (length list))
       (loop for (k) on list by #'cddr always (keywordp k))))

(defun make-form-p (form)
  (let ((name (form-name (car form))))
    (and (> (length name) 5)
         (string= "make-" name :end2 5)
         (keyword-plist-p (cdr form)))))

(defun parse-make (form)
  (make-make-expr
   :type-name (subseq (spelling (car form)) 5)
   :inits (loop for (k v) on (cdr form) by #'cddr
                collect (make-field-init :name (spelling-of-keyword k)
                                         :value (parse-expr v) :source (list k v)))
   :source form))

(defun spelling-of-keyword (k)
  (source-spelling (symbol-name k)))

(defun check-arg-count (form min &optional (max min))
  (let ((n (length (cdr form))))
    (unless (and (>= n min) (or (null max) (<= n max)))
      (dsl-error form "~a expects ~:[~d to ~d~;~d~*~] argument~:p"
                 (form-name (car form)) (eql min max) min max))))
