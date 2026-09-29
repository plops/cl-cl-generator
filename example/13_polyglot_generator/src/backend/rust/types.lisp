;;;; types.lisp --- Rust backend: type spelling, parameter types, lifetimes

(in-package :polyglot)

(defvar *rs-module* nil "Module being emitted.")
(defvar *rs-regions* nil
  "Alist region keyword (or :anon) -> lifetime name for the signature or struct
being emitted; NIL means elided.")

(defun rs-item-ref (item)
  "Name of ITEM as seen from *RS-MODULE*; notes a use declaration for foreign items."
  (let ((module (ir-module item)))
    (unless (or (null module) (eq module *rs-module*))
      (note-import (list :use (ir-target-name module) (ir-target-name item))))
    (ir-target-name item)))

(defun rs-lifetime (region)
  "'a for REGION when the current signature names it, else NIL (elided)."
  (cond ((eq region :static) "'static")
        (t (cdr (assoc (or region :anon) *rs-regions*)))))

(defun rs-ref (inner region &key mut)
  (let ((lt (rs-lifetime region)))
    (format nil "&~@[~a ~]~:[~;mut ~]~a" lt mut inner)))

(defun rs-struct-generics (item)
  "<'a> of a struct with borrowed fields, '_ in paths without names."
  (let ((regions (struct-regions item)))
    (when regions
      (format nil "<~{~a~^, ~}>" (mapcar (lambda (r) (or (cdr (assoc r *rs-regions*)) "'_")) regions)))))

(defun rs-type (ty)
  "Rust spelling of TY."
  (cond ((member ty '(:i8 :i16 :i32 :i64 :u8 :u16 :u32 :u64 :f32 :f64 :bool :char))
         (string-downcase (symbol-name ty)))
        ((eq ty :string) "String")
        ((eq ty :void) "()")
        ((not (consp ty)) "_")
        (t (ecase (car ty)
             (:vec (format nil "Vec<~a>" (rs-type (second ty))))
             (:array (format nil "[~a; ~d]" (rs-type (second ty)) (third ty)))
             (:map (note-import (list :std "std::collections::HashMap"))
                   (format nil "HashMap<~a, ~a>" (rs-type (second ty)) (rs-type (third ty))))
             (:optional (format nil "Option<~a>" (rs-type (second ty))))
             (:box (format nil "Box<~a>" (rs-type (second ty))))
             (:dyn (format nil "dyn ~a" (rs-item-ref (third ty))))
             (:named (format nil "~a~@[~a~]" (rs-item-ref (third ty))
                             (and (typep (third ty) 'struct-item) (rs-struct-generics (third ty)))))
             (:fn (format nil "Box<dyn Fn(~{~a~^, ~}) -> ~a>" (mapcar #'rs-type (second ty)) (rs-type (third ty))))
             (:ref (rs-ref (rs-type (second ty)) (third ty)))
             (:mut-ref (rs-ref (rs-type (second ty)) (third ty) :mut t))
             (:view (rs-ref (if (eq :string (second ty)) "str" (format nil "[~a]" (rs-type (second (second ty)))))
                            (third ty)))
             (:raw (if (eq (second ty) :rust) (third ty) (unsupported ty "raw type for another backend")))))))

(defun rs-borrow-type (ty &key mut region)
  "The borrowed form of a non-copy TY for parameters: &str, &[T], &dyn I, &T."
  (let ((inner (cond ((and (eq ty :string) (not mut)) "str")
                     ((and (eq :vec (type-head ty)) (not mut)) (format nil "[~a]" (rs-type (second ty))))
                     ;; clippy::borrowed_box: &Box<T> -> &T
                     ((eq :box (type-head ty)) (rs-type (second ty)))
                     (t (rs-type ty)))))
    (rs-ref inner region :mut mut)))

(defvar *rs-param-regions* nil
  "Alist var-def -> region keyword for implicit parameter borrows (borrows-from).")

(defun rs-param-type (var &key pushes)
  "K1: :in -> T for copy types, else a shared borrow; :inout -> &mut T (a
vec that is pushed to stays &mut Vec<T>); :sink -> T."
  (let ((ty (ir-ty var)) (region (cdr (assoc var *rs-param-regions*))))
    (ecase (ir-mode var)
      (:in (cond ((or (copy-type-p ty) (borrowed-type-p ty)) (rs-type ty))
                 ((eq :fn (type-head ty))
                  (format nil "impl Fn(~{~a~^, ~}) -> ~a" (mapcar #'rs-type (second ty)) (rs-type (third ty))))
                 (t (rs-borrow-type ty :region region))))
      (:inout (if (and (eq :vec (type-head ty)) (not pushes))
                  (rs-ref (format nil "[~a]" (rs-type (second ty))) region :mut t)
                  (rs-ref (rs-type ty) region :mut t)))
      (:sink (rs-type ty)))))

(defun struct-regions (item)
  "Distinct regions used by the fields of ITEM, :anon for unnamed ones."
  (and (typep item 'struct-item)
       (remove-duplicates (loop for f in (ir-fields item) append (type-regions (ir-ty f)))
                          :from-end t)))

(defun rs-zero-value (ty)
  "Value of a field without default."
  (cond ((int-type-p ty) "0")
        ((float-type-p ty) "0.0")
        ((eq ty :bool) "false")
        ((eq ty :char) "' '")
        ((eq ty :string) "String::new()")
        ((eq :vec (type-head ty)) "Vec::new()")
        ((eq :map (type-head ty)) (note-import (list :std "std::collections::HashMap")) "HashMap::new()")
        ((eq :optional (type-head ty)) "None")
        (t nil)))
