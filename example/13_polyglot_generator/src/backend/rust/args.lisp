;;;; args.lisp --- Rust backend: references at call sites and owned values (K1)

(in-package :polyglot)

(defun rs-ref-kind (e)
  "How the Rust value of E is held: :shared (&T), :mut (&mut T) or NIL (owned
value or place)."
  (let ((ty (ir-ty e)))
    (cond ((eq :mut-ref (type-head ty)) :mut)
          ((borrowed-type-p ty) :shared)
          ((and (typep e 'var-expr) (typep (ir-binding e) 'var-def)) (rs-var-ref-kind (ir-binding e)))
          (t nil))))

(defvar *rs-loop-modes* nil "Hash table loop var-def -> iteration mode.")

(defun rs-var-ref-kind (var)
  (let ((ty (ir-ty var)))
    (case (ir-kind var)
      ((:param :receiver)
       (case (ir-mode var)
         (:in (unless (copy-type-p ty) :shared))
         (:inout :mut)))
      (:loop (let ((mode (and *rs-loop-modes* (gethash var *rs-loop-modes*))))
               (unless (copy-type-p ty)
                 (case mode (:ref :shared) (:mut :mut)))))
      (t nil))))

(defun string-literal-p (e) (and (typep e 'lit-expr) (eq :string (ir-kind e))))

(defun rs-owned (e expected)
  "E in a context that needs an owned value of type EXPECTED."
  (let ((ty (ir-ty e)))
    (cond ((and (eq expected :string) (string-literal-p e))
           (prim (format nil "~a.to_string()" (ex-str e))))
          ((and (eq expected :string) (consp ty) (eq :view (car ty)) (eq :string (second ty)))
           (prim (format nil "~a.to_string()" (receiver e))))
          ((and (eq :optional (type-head expected)) (typep e 'own-expr) (eq :some (ir-kind e)))
           (prim (format nil "Some(~a)" (ex-str-for (ir-value e) (second expected)))))
          (t (ex e)))))

(defun rs-borrowed (e &key mut)
  "E where a reference is expected."
  (cond ((and (not mut) (string-literal-p e)) (ex-str e))
        ((and (not mut) (typep e 'vec-expr)) (format nil "&[~a]" (comma-list (ir-elems e))))
        ((eq (rs-ref-kind e) (if mut :mut :shared)) (ex-str e))
        ((and (not mut) (eq :mut (rs-ref-kind e))) (ex-str e))
        (t (format nil "&~:[~;mut ~]~a" mut (operand :ref :only e)))))

(defun ex-str-for (e expected)
  "E converted for a slot of type EXPECTED (owned string, borrow, value)."
  (cond ((not (known-type-p expected)) (ex-str e))
        ((borrowed-type-p expected) (rs-borrowed e :mut (eq :mut-ref (type-head expected))))
        (t (values (rs-owned e expected)))))

(defun rs-arg (a p)
  "Argument A for parameter P according to the parameter mode."
  (let ((ty (ir-ty p)))
    (ecase (ir-mode p)
      (:sink (values (rs-owned a ty)))
      (:inout (rs-borrowed a :mut t))
      (:in (cond ((and (member (type-head ty) '(:ref :mut-ref)) (eq :dyn (type-head (second ty)))
                       (eq :box (type-head (ir-ty a))))
                  ;; &mut Box<dyn T> does not coerce to &mut dyn T (unsizing wins)
                  (format nil "~a.~:[as_ref~;as_mut~]()" (receiver a) (eq :mut-ref (type-head ty))))
                 ((borrowed-type-p ty) (ex-str-for a ty))
                 ((copy-type-p ty) (ex-str a))
                 ((eq :fn (type-head ty)) (if (typep a 'lambda-expr) (ex-str a) (format nil "&~a" (ex-str a))))
                 (t (rs-borrowed a)))))))

(defun rs-args (args params)
  (format nil "~{~a~^, ~}" (loop for a in args for p in params collect (rs-arg a p))))

(defun rs-place (e)
  "E as the target of an assignment: through &mut references the place is *x."
  (if (and (typep e 'var-expr) (typep (ir-binding e) 'var-def)
           (eq :mut (rs-var-ref-kind (ir-binding e))) (not (ir-receiver-p (ir-binding e)))
           (not (copy-type-p (ir-ty e))))       ; copy :inout params already print as *x
      (format nil "*~a" (ex-str e))
      (ex-str e)))
