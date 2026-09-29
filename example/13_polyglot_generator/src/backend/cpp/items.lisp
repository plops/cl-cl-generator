;;;; items.lisp --- C++ backend: struct/class declarations, methods, functions

(in-package :polyglot)

(defvar *cpp-by-value* t
  "True while emitting code that needs complete types (fields, bases, bodies).")

(defun cpp-derived-p (item)
  (let ((project (ir-project (ir-module item))))
    (loop for m in (ir-modules project)
          thereis (some (lambda (i) (and (typep i 'struct-item) (eq item (ir-base-item i))))
                        (ir-items m)))))

(defun cpp-polymorphic-p (item)
  "Needs a constructor instead of aggregate initialization."
  (and (typep item 'struct-item)
       (or (ir-base-item item) (ir-implements-items item) (cpp-derived-p item)
           (some #'method-virtual-p (ir-methods item)))))

(defun cpp-param-list (params &key definition fn)
  (format nil "~{~a~^, ~}"
          (loop for p in params
                collect (format nil "~:[~;[[maybe_unused]] ~]~a ~a"
                                (and definition fn (not (param-used-p fn p)))
                                (cpp-param-type p) (ir-target-name p)))))

(defun param-used-p (fn param)
  (let ((used nil))
    (dolist (s (ir-body fn) used)
      (walk-nodes (lambda (n) (when (and (typep n 'var-expr) (eq param (ir-binding n))) (setf used t)))
                  s))))

(defun cpp-method-qualifiers (m)
  (let ((recv (method-receiver m)))
    (format nil "~:[~; const~]~:[~; override~]~:[~; = 0~]"
            (eq :in (ir-mode recv))
            (and (ir-super-target m) (method-virtual-p m))
            (function-flag-p m :abstract))))

(defun cpp-method-prototype (m)
  (let ((*cpp-by-value* nil))
    (format nil "~:[~;virtual ~]~a ~a(~a)~a;"
            (and (method-virtual-p m) (null (ir-super-target m)))
            (cpp-type (ir-ret m)) (ir-target-name m) (cpp-param-list (rest (ir-params m)))
            (cpp-method-qualifiers m))))

(defun cpp-field-decl (f)
  (let ((ty (cpp-type (ir-ty f) :field t)))
    (if (ir-default f)
        (format nil "~a ~a = ~a;" ty (ir-target-name f) (ex-str (ir-default f)))
        (format nil "~a ~a{};" ty (ir-target-name f)))))

(defun cpp-ctor-param (f)
  (let ((ty (ir-ty f)))
    (format nil "~a ~a" (cpp-type ty :field t) (ir-target-name f))))

(defun cpp-member-init (f)
  (let ((ty (ir-ty f)) (name (ir-target-name f)))
    (if (or (copy-type-p ty) (member (type-head ty) '(:ref :mut-ref)))
        (format nil "~a(~a)" name name)
        (progn (cpp-std-include "utility") (format nil "~a(std::move(~a))" name name)))))

(defun cpp-constructor (item)
  (let* ((fields (all-fields item))
         (own (ir-fields item))
         (base (ir-base-item item))
         (base-fields (and base (all-fields base)))
         (inits (append (when base-fields
                          (list (format nil "~a(~{~a~^, ~})" (cpp-item-ref base)
                                        (mapcar (lambda (f) (cpp-member-init-arg f)) base-fields))))
                        (mapcar #'cpp-member-init own))))
    (when fields
      (emit-line "~:[~;explicit ~]~a(~{~a~^, ~})~:[~; : ~:*~{~a~^, ~}~] {}"
                 (= 1 (length fields)) (ir-target-name item) (mapcar #'cpp-ctor-param fields) inits))))

(defun cpp-member-init-arg (f)
  (if (copy-type-p (ir-ty f))
      (ir-target-name f)
      (progn (cpp-std-include "utility") (format nil "std::move(~a)" (ir-target-name f)))))

(defun cpp-bases (item)
  (let ((bases (append (when (ir-base-item item) (list (ir-base-item item)))
                       (ir-implements-items item)
                       (when (typep item 'interface-item) (ir-extends-items item)))))
    (if bases (format nil " : ~{public ~a~^, ~}" (mapcar #'cpp-item-ref bases)) "")))

(defun cpp-needs-virtual-dtor-p (item)
  (and (or (typep item 'interface-item) (some #'method-virtual-p (ir-methods item)))
       (null (ir-base-item item)) (null (ir-implements-items item))
       (not (and (typep item 'interface-item) (ir-extends-items item)))))

(defun cpp-type-declaration (item)
  "struct Name : bases { fields; constructor; methods; };"
  (with-block ((format nil "struct ~a~a {" (ir-target-name item) (cpp-bases item)) "};")
    (when (typep item 'struct-item)
      (dolist (f (ir-fields item)) (emit-line (cpp-field-decl f)))
      (when (cpp-polymorphic-p item)
        (let ((*cpp-by-value* nil)) (cpp-constructor item))))
    (when (cpp-needs-virtual-dtor-p item)
      (emit-line "virtual ~~~a() = default;" (ir-target-name item)))
    (dolist (m (ir-methods item))
      (emit-line (cpp-method-prototype m)))))

(defun cpp-function-body (fn)
  (let ((*cpp-function* fn)
        (*cpp-local-names* (let ((out '()))
                             (walk-nodes (lambda (n) (when (typep n 'var-def) (push (ir-target-name n) out))) fn)
                             out)))
    (with-indent () (cpp-stmts (ir-body fn)))))

(defun cpp-function-definition (fn &key owner)
  (let ((name (cond (owner (format nil "~a::~a" (ir-target-name owner) (ir-target-name fn)))
                    (t (ir-target-name fn))))
        (params (if owner (rest (ir-params fn)) (ir-params fn))))
    (emit-line "~a ~a(~a)~:[~;~a~] {" (cpp-type (ir-ret fn)) name
               (cpp-param-list params :definition t :fn fn)
               owner (and owner (if (eq :in (ir-mode (method-receiver fn))) " const" "")))
    (cpp-function-body fn)
    (emit-line "}")))

(defun cpp-main-definition (fn)
  (emit-line "int main() {")
  (cpp-function-body fn)
  (emit-line "}"))

(defun cpp-function-prototype (fn)
  (let ((*cpp-by-value* nil))
    (format nil "~a ~a(~a);" (cpp-type (ir-ret fn)) (ir-target-name fn) (cpp-param-list (ir-params fn)))))

(defun cpp-const-definition (item &key header)
  (let ((simple (or (numeric-type-p (ir-ty item)) (member (ir-ty item) '(:bool :char)))))
    (emit-line "~:[~;inline ~]~:[const~;constexpr~] ~a ~a = ~a;" header simple
               (cpp-type (ir-ty item)) (ir-target-name item) (ex-str (ir-value item)))))
