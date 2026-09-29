;;;; items.lisp --- Rust backend: structs, impl blocks, traits, functions

(in-package :polyglot)

(defvar *derivable* nil "Hash table struct item -> can derive Debug and Clone.")

(defun type-derivable-p (ty)
  (cond ((not (consp ty)) t)
        ((member (car ty) '(:dyn :fn :raw)) nil)
        ((eq (car ty) :named) (let ((i (third ty))) (and (typep i 'struct-item) (struct-derivable-p i))))
        ((member (car ty) '(:ref :mut-ref :view :box :optional :vec :array))
         (type-derivable-p (second ty)))
        ((eq (car ty) :map) (and (type-derivable-p (second ty)) (type-derivable-p (third ty))))
        (t t)))

(defun struct-derivable-p (item)
  (multiple-value-bind (v found) (gethash item *derivable*)
    (if found
        v
        (progn (setf (gethash item *derivable*) t)
               (setf (gethash item *derivable*)
                     (every (lambda (f) (type-derivable-p (ir-ty f))) (ir-fields item)))))))

(defun rs-pub (item) (and (eq :public (ir-visibility item)) (not (ir-entry-p (ir-module item)))))

(defun rs-struct-lifetimes (item)
  (mapcar (lambda (r) (cons r (lifetime-name r))) (struct-regions item)))

(defun rs-body (fn)
  (let ((*rs-ret* (ir-ret fn)))
    (with-indent () (rs-stmts (ir-body fn) t))))

(defun rs-function (fn &key struct-regions pub)
  (mark-used-params fn)
  (when (ir-doc fn) (emit-line "/// ~a" (ir-doc fn)))
  (emit-line "~a {" (rs-signature fn :struct-regions struct-regions :pub pub))
  (rs-body fn)
  (emit-line "}"))

(defun rs-struct (item)
  (let* ((*rs-regions* (rs-struct-lifetimes item))
         (pub (rs-pub item))
         (generics (and *rs-regions* (format nil "<~{~a~^, ~}>" (mapcar #'cdr *rs-regions*)))))
    (when (ir-doc item) (emit-line "/// ~a" (ir-doc item)))
    (when (struct-derivable-p item) (emit-line "#[derive(Debug, Clone)]"))
    (if (ir-fields item)
        (with-block ((format nil "~:[~;pub ~]struct ~a~@[~a~] {" pub (ir-target-name item) generics) "}")
          (dolist (f (ir-fields item))
            (emit-line "~:[~;pub ~]~a: ~a," pub (ir-target-name f) (rs-type (ir-ty f)))))
        (emit-line "~:[~;pub ~]struct ~a;" pub (ir-target-name item)))))

(defun trait-of-method (m)
  (let ((owner (ir-owner-item (root-method m))))
    (and (typep owner 'interface-item) owner)))

(defun rs-impl-header (item trait)
  (let* ((regions (rs-struct-lifetimes item))
         (uses (and regions (some (lambda (m) (borrowed-type-p* (ir-ret m))) (ir-methods item))))
         (self-type (format nil "~a~@[<~{~a~^, ~}~]>" (ir-target-name item)
                            (and regions (mapcar (lambda (r) (if uses (cdr r) "'_")) regions)))))
    (format nil "impl~@[<~{~a~^, ~}>~] ~@[~a for ~]~a {"
            (and uses (mapcar #'cdr regions))
            (and trait (rs-item-ref trait))
            (if regions self-type (ir-target-name item)))))

(defun rs-impl-block (item methods trait)
  "impl block; for a trait it is written even without methods (the struct
must implement every trait it declares, also supertraits and default-only
traits)."
  (when (and trait (null methods))
    (emit-blank-line)
    (emit-line "~a}" (rs-impl-header item trait))
    (return-from rs-impl-block))
  (when methods
    (emit-blank-line)
    (emit-line (rs-impl-header item trait))
    (with-indent ()
      (loop for (m . rest) on methods
            do (let ((*rs-regions* (rs-struct-lifetimes item)))
                 (rs-function m :struct-regions (struct-regions item)
                              :pub (and (null trait) (rs-pub item))))
            (when rest (emit-blank-line))))
    (emit-line "}")))

(defun rs-struct-with-impls (item)
  (rs-struct item)
  (let ((inherent (remove-if #'trait-of-method (ir-methods item))))
    (rs-impl-block item inherent nil)
    (dolist (trait (type-interfaces item))
      (rs-impl-block item (remove-if-not (lambda (m) (eq trait (trait-of-method m))) (ir-methods item))
                     trait))))

(defun rs-trait (item)
  (when (ir-doc item) (emit-line "/// ~a" (ir-doc item)))
  (emit-line "~:[~;pub ~]trait ~a~@[: ~{~a~^ + ~}~] {" (rs-pub item) (ir-target-name item)
             (mapcar #'rs-item-ref (ir-extends-items item)))
  (with-indent ()
    (loop for (m . rest) on (ir-methods item)
          do (if (function-flag-p m :abstract)
                 (progn (mark-used-params m) (dolist (p (ir-params m)) (setf (ir-used p) t))
                        (emit-line "~a;" (rs-signature m)))
                 (rs-function m))
          (when rest (emit-blank-line))))
  (emit-line "}"))

(defun rs-const (item)
  (let ((ty (if (eq :string (ir-ty item)) "&str" (rs-type (ir-ty item)))))
    (emit-line "~:[~;pub ~]const ~a: ~a = ~a;" (rs-pub item) (ir-target-name item) ty
               (ex-str (ir-value item)))))

(defmethod emit-item ((b rust-backend) item)
  (etypecase item
    (function-item (rs-function item :pub (rs-pub item)))
    (struct-item (rs-struct-with-impls item))
    (interface-item (rs-trait item))
    (const-item (rs-const item))
    (extern-item nil)))
