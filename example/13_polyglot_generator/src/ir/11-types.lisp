;;;; 11-types.lisp --- type IR: parsing, predicates, borrow regions
;;;;
;;;; Types are plain data (not nodes):
;;;;   primitives  :i8 :i16 :i32 :i64 :u8 :u16 :u32 :u64 :f32 :f64 :bool
;;;;               :string :char :void          (:int is normalized to :i64)
;;;;   (:vec T) (:array T n) (:map K V) (:optional T) (:box T) (:dyn "name")
;;;;   (:fn (T...) R) (:named "name") (:raw backend "text")
;;;;   (:ref T region) (:mut-ref T region) (:view T region)
;;;;               region is NIL (anonymous), a keyword, or :static
;;;;   :unknown    set by resolve when no type could be derived

(in-package :polyglot)

(defparameter +int-types+ '(:i8 :i16 :i32 :i64 :u8 :u16 :u32 :u64))
(defparameter +float-types+ '(:f32 :f64))
(defparameter +primitive-types+
  (append +int-types+ +float-types+ '(:bool :string :char :void)))

(defun parse-region (form spec)
  (cond ((null spec) nil)
        ((keywordp spec) spec)
        (t (dsl-error form "region must be a keyword such as :a or :static, got ~s" spec))))

(defun parse-view-target (form inner)
  (let ((ty (parse-type inner)))
    (unless (or (eq ty :string) (and (consp ty) (eq (car ty) :vec)))
      (dsl-error form "view needs :string or (vec T), got ~s" inner))
    ty))

(defun parse-compound-type (form)
  (let ((head (form-name (car form)))
        (args (cdr form)))
    (flet ((arity (n)
             (unless (= n (length args))
               (dsl-error form "type ~a expects ~d argument~:p" head n))))
      (cond
        ((string= head "vec") (arity 1) (list :vec (parse-type (first args))))
        ((string= head "array")
         (arity 2)
         (unless (and (integerp (second args)) (plusp (second args)))
           (dsl-error form "array size must be a positive integer"))
         (list :array (parse-type (first args)) (second args)))
        ((string= head "map") (arity 2)
         (list :map (parse-type (first args)) (parse-type (second args))))
        ((string= head "optional") (arity 1) (list :optional (parse-type (first args))))
        ((string= head "box") (arity 1) (list :box (parse-type (first args))))
        ((string= head "dyn") (arity 1)
         (unless (and (symbolp (first args)) (not (keywordp (first args))))
           (dsl-error form "dyn needs an interface name"))
         (list :dyn (spelling (first args))))
        ((string= head "fn") (arity 2)
         (unless (listp (first args)) (dsl-error form "fn needs a parameter type list"))
         (list :fn (mapcar #'parse-type (first args)) (parse-type (second args))))
        ((member head '("ref" "mut-ref") :test #'string=)
         (unless (<= 1 (length args) 2) (dsl-error form "~a expects a type and a region" head))
         (list (if (string= head "ref") :ref :mut-ref)
               (parse-type (first args)) (parse-region form (second args))))
        ((string= head "view")
         (unless (<= 1 (length args) 2) (dsl-error form "view expects a type and a region"))
         (list :view (parse-view-target form (first args)) (parse-region form (second args))))
        (t (parse-target-type form))))))

(defun parse-target-type (form)
  "(rs:type \"...\") and friends: a raw type for one backend."
  (let ((pkg (and (symbolp (car form)) (symbol-package (car form)))))
    (if (and pkg (target-package-backend pkg) (form-is (car form) "type")
             (stringp (second form)))
        (list :raw (target-package-backend pkg) (second form))
        (dsl-error form "unknown type form"))))

(defun target-package-backend (package)
  "Backend keyword of an extension package (cpp: py: rs: go:), or NIL."
  (let ((name (package-name package)))
    (cdr (assoc name '(("POLYGLOT.CPP" . :cpp) ("POLYGLOT.PY" . :python)
                       ("POLYGLOT.RS" . :rust) ("POLYGLOT.GO" . :go))
                :test #'string=))))

(defun parse-type (form)
  "Parse the DSL type FORM into the normalized type representation."
  (cond ((eq form :int) :i64)
        ((keywordp form)
         (if (member form +primitive-types+)
             form
             (dsl-error form "unknown primitive type ~s" form)))
        ((and form (symbolp form)) (list :named (spelling form)))
        ((consp form) (parse-compound-type form))
        (t (dsl-error form "invalid type ~s" form))))

(defun type-head (ty) (if (consp ty) (car ty) ty))
(defun int-type-p (ty) (member ty +int-types+))
(defun float-type-p (ty) (member ty +float-types+))
(defun numeric-type-p (ty) (or (int-type-p ty) (float-type-p ty)))
(defun primitive-type-p (ty) (member ty +primitive-types+))
(defun named-type-p (ty) (and (consp ty) (eq (car ty) :named)))
(defun named-type-name (ty) (and (named-type-p ty) (second ty)))
(defun known-type-p (ty) (and ty (not (eq ty :unknown))))

(defun borrowed-type-p (ty)
  "True for (ref T), (mut-ref T) and (view T)."
  (member (type-head ty) '(:ref :mut-ref :view)))

(defun copy-type-p (ty)
  "Types with value semantics that are copied implicitly in every backend:
numbers, :bool, :char and shared borrows. :string is NOT a copy type."
  (or (numeric-type-p ty)
      (member ty '(:bool :char))
      (member (type-head ty) '(:ref :view))))

(defun borrow-target (ty)
  "T of a borrowed type, otherwise TY itself."
  (if (borrowed-type-p ty) (second ty) ty))

(defun type-regions (ty)
  "List of regions in TY in order of appearance, :anon for unnamed ones.
Duplicates are removed."
  (let ((out '()))
    (labels ((walk (x)
               (when (consp x)
                 (case (car x)
                   ((:ref :mut-ref :view)
                    (push (or (third x) :anon) out)
                    (walk (second x)))
                   (:fn (mapc #'walk (second x)) (walk (third x)))
                   ((:dyn :named :raw) nil)
                   (t (mapc #'walk (cdr x)))))))
      (walk ty))
    (remove-duplicates (nreverse out) :from-end t)))

(defun type-string (ty)
  "Readable DSL-like spelling of TY for messages."
  (cond ((keywordp ty) (format nil "~(~s~)" ty))
        ((named-type-p ty) (second ty))
        ((consp ty) (format nil "(~(~a~)~{ ~a~})" (car ty)
                            (mapcar (lambda (x) (if (or (keywordp x) (consp x))
                                                    (type-string x)
                                                    (princ-to-string x)))
                                    (remove nil (cdr ty)))))
        (t (princ-to-string ty))))
