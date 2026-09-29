;;;; symbols.lisp --- CL backend: scratch packages for printing symbols
;;;;
;;;; Every generated module gets a temporary scratch package (using CL) while
;;;; it is printed. DSL names are interned there; names that clash with
;;;; COMMON-LISP are shadowed, so CL's own symbols print as common-lisp:x when
;;;; needed. Symbols of other modules and of the runtime prelude are imported,
;;;; which makes them print unqualified; the matching :import-from clauses are
;;;; recorded for DEFPACKAGE.

(in-package :polyglot)

(defvar *cl-scratch* nil "Hash table module (or :rt) -> scratch package.")
(defvar *cl-module* nil "Module being emitted.")
(defvar *cl-imports* nil "Hash table package name -> list of imported symbols.")
(defvar *cl-shadows* nil "Hash table module -> list of shadowed names.")
(defvar *cl-rt-used* nil "List of runtime helper names used by the project.")

(defun cl-package-name (module)
  "Name of the generated package of MODULE (the pseudo module :rt is the prelude)."
  (let ((project (ir-name (ir-project (or (and (typep module 'module-item) module) *cl-module*)))))
    (if (eq module :rt)
        (format nil "~a.polyglot-rt" project)
        (format nil "~a.~a" project (ir-target-name module)))))

(defun scratch-package (module)
  (or (gethash module *cl-scratch*)
      (setf (gethash module *cl-scratch*)
            (make-package (symbol-name (gensym "PG-CL-SCRATCH-")) :use '(:cl)))))

(defun cl-symbol-string (name)
  "Symbol name for the DSL spelling NAME (verbatim names keep their case)."
  (if (verbatim-name-p name) name (string-upcase name)))

(defun cl-external-p (string)
  (multiple-value-bind (sym status) (find-symbol string :cl)
    (declare (ignore sym))
    (eq status :external)))

(defun module-sym (module name)
  "The symbol NAME of MODULE, shadowing a COMMON-LISP symbol of that name."
  (let* ((pkg (scratch-package module))
         (string (cl-symbol-string name)))
    (when (and (cl-external-p string)
               (not (member string (gethash module *cl-shadows*) :test #'string=)))
      (shadow string pkg)
      (push string (gethash module *cl-shadows*)))
    (intern string pkg)))

(defun import-into-current (sym owner-package-name)
  "Make SYM accessible (unqualified) in the scratch package of *CL-MODULE*."
  (let* ((pkg (scratch-package *cl-module*))
         (present (find-symbol (symbol-name sym) pkg)))
    (unless (eq present sym)
      (if present (shadowing-import sym pkg) (import sym pkg))
      (pushnew sym (gethash owner-package-name *cl-imports*)))
    sym))

(defun item-sym (item &optional (name (ir-target-name item)))
  "Symbol of ITEM (defined in some module) as seen from *CL-MODULE*."
  (let* ((module (ir-module item))
         (sym (module-sym module name)))
    (if (eq module *cl-module*)
        sym
        (import-into-current sym (cl-package-name module)))))

(defun local-sym (var)
  "Symbol of a var-def (or a plain name) in the current module."
  (module-sym *cl-module* (if (stringp var) var (ir-target-name var))))

(defun rt-sym (name)
  "Symbol of the runtime helper NAME, imported into the current module."
  (pushnew name *cl-rt-used* :test #'string=)
  (import-into-current (module-sym :rt name) (cl-package-name :rt)))

(defun accessor-sym (field)
  "Accessor <struct>-<field> of FIELD, defined in the module of its struct."
  (let ((owner (ir-owner field)))
    (item-sym owner (format nil "~a-~a" (ir-target-name owner) (ir-target-name field)))))

(defun generic-sym (method)
  "The generic function of METHOD: the name of its root method."
  (let ((root (root-method method)))
    (item-sym (ir-owner-item root) (ir-target-name root))))

(defun field-keyword (field)
  (intern (cl-symbol-string (ir-target-name field)) :keyword))

(defmacro with-cl-scratch (() &body body)
  "Fresh scratch state for one project; the scratch packages are deleted afterwards."
  `(let ((*cl-scratch* (make-hash-table))
         (*cl-shadows* (make-hash-table))
         (*cl-rt-used* '()))
     (unwind-protect (progn ,@body)
       (loop for pkg being the hash-values of *cl-scratch*
             do (delete-package pkg)))))
