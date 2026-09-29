;;;; split.lisp --- C++ backend: header/implementation split, type order,
;;;; include analysis (plan.md K2, after Haxe cppGenClassHeader.ml)

(in-package :polyglot)

(defun type-value-deps (ty)
  "Struct/interface items TY needs complete (by value, also inside containers)."
  (cond ((not (consp ty)) nil)
        ((member (car ty) '(:named :dyn)) (list (third ty)))
        ((member (car ty) '(:box :ref :mut-ref :view :fn :raw)) nil)
        ((eq (car ty) :array) (type-value-deps (second ty)))
        (t (loop for x in (cdr ty) append (type-value-deps x)))))

(defun struct-value-deps (item)
  (remove-duplicates
   (append (when (typep item 'struct-item)
             (append (alexandria:ensure-list (ir-base-item item)) (ir-implements-items item)
                     (loop for f in (ir-fields item) append (type-value-deps (ir-ty f)))))
           (when (typep item 'interface-item) (ir-extends-items item)))))

(defun topo-sort-types (items)
  "ITEMS ordered so that every type comes after the types it contains by value.
A cycle over values is a dsl-error; cycles through box need no order."
  (let ((done '()) (visiting '()))
    (labels ((visit (i)
               (when (member i visiting)
                 (dsl-error (ir-source i) "~a contains itself by value; use (box ...)" (ir-name i)))
               (when (and (member i items) (not (member i done)))
                 (push i visiting)
                 (mapc #'visit (struct-value-deps i))
                 (pop visiting)
                 (push i done))))
      (mapc #'visit items)
      (nreverse done))))

(defun module-types (module visibility)
  (topo-sort-types (remove-if-not (lambda (i) (and (typep i '(or struct-item interface-item))
                                                   (eq visibility (ir-visibility i))))
                                  (ir-items module))))

(defun module-functions (module visibility)
  (remove-if-not (lambda (i) (and (typep i 'function-item) (eq visibility (ir-visibility i))))
                 (ir-items module)))

(defun module-consts (module visibility)
  (remove-if-not (lambda (i) (and (typep i 'const-item) (eq visibility (ir-visibility i))))
                 (ir-items module)))

(defun cpp-forward-declarations (items)
  "struct X; for the types of ITEMS that are referenced before their definition."
  (let ((defined '()) (needed '()))
    (dolist (i items)
      (when (typep i 'struct-item)
        (dolist (f (ir-fields i))
          (dolist (ref (type-items-anywhere (ir-ty f)))
            (when (and (member ref items) (not (member ref defined)) (not (eq ref i)))
              (pushnew ref needed)))))
      (push i defined))
    (dolist (i (reverse needed)) (emit-line "struct ~a;" (ir-target-name i)))))

(defun type-items-anywhere (ty)
  (cond ((not (consp ty)) nil)
        ((member (car ty) '(:named :dyn)) (list (third ty)))
        ((eq (car ty) :raw) nil)
        (t (loop for x in (cdr ty) when (or (consp x)) append (type-items-anywhere x)))))

(defun cpp-include-lines (&key own-header)
  "Include lines from *IMPORTS*: own header, standard headers, prelude,
headers of other modules."
  (let ((std '()) (modules '()) (raw '()) (prelude nil))
    (loop for key being the hash-keys of *imports*
          do (case (first key)
               (:std (pushnew (second key) std :test #'string=))
               (:raw-include (pushnew (second key) raw :test #'string=))
               (:module (pushnew (second key) modules :test #'string=))
               (:prelude (setf prelude t))))
    (append (when own-header (list (format nil "#include \"~a.hpp\"" own-header) ""))
            (mapcar (lambda (h) (format nil "#include <~a>" h)) (sort std #'string<))
            (mapcar (lambda (h) (format nil "#include ~a" h)) (sort raw #'string<))
            (when (or prelude modules) (list ""))
            (when prelude (list "#include \"polyglot_rt.hpp\""))
            (mapcar (lambda (m) (format nil "#include \"~a.hpp\"" m)) (sort modules #'string<)))))

(defun cpp-foreign-forward-lines ()
  "namespace m { struct X; } for foreign types that are only named in signatures."
  (let ((included (loop for k being the hash-keys of *imports*
                        when (eq :module (first k)) collect (second k)))
        (fwd (make-hash-table :test 'equal)))
    (loop for k being the hash-keys of *imports*
          when (and (eq :forward (first k)) (not (member (second k) included :test #'string=)))
          do (pushnew (third k) (gethash (second k) fwd) :test #'string=))
    (loop for m in (sort (alexandria:hash-table-keys fwd) #'string<)
          collect (format nil "namespace ~a {~{~%struct ~a;~}~%}  // namespace ~a" m
                          (sort (gethash m fwd) #'string<) m))))
