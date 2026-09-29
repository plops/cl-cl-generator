;;;; 24-modules.lisp --- defextern, defmodule, defproject

(in-package :polyglot)

(defun parse-extern-params (form specs)
  (loop for spec in specs
        do (unless (and (consp spec) (= 2 (length spec)) (symbolp (car spec)))
             (dsl-error form "extern parameter must be (name type), got ~s" spec))
        collect (make-var-def :name (spelling (car spec)) :kind :param
                              :declared-ty (parse-type (second spec)) :source spec)))

(defun parse-defextern (form)
  "(defextern name ((x :f64)) ret (:cpp \"std::sqrt\" :includes (\"<cmath>\")) ...)"
  (check-arg-count form 3 nil)
  (make-extern-item
   :name (require-name form)
   :params (parse-extern-params form (third form))
   :ret (parse-type (fourth form))
   :expansions (loop for spec in (nthcdr 4 form)
                     do (unless (and (consp spec) (keywordp (car spec)) (stringp (second spec)))
                          (dsl-error form "extern expansion must be (:backend \"name\" ...)"))
                     collect (list* (normalize-backend-key form (car spec)) (cdr spec)))
   :source form))

(defun parse-item (form)
  (with-macro-expansion (f form)
    (let ((head (item-head f)))
      (cond ((null head) (dsl-error f "item form expected"))
            ((string= head "defun") (parse-defun f))
            ((string= head "defmethod") (parse-method f nil))
            ((string= head "defstruct") (parse-defstruct f))
            ((string= head "defclass") (parse-defclass f))
            ((string= head "definterface") (parse-definterface f))
            ((string= head "defconst") (parse-defconst f))
            ((string= head "defextern") (parse-defextern f))
            (t (dsl-error f "unknown item form ~a" head))))))

(defun module-options (form)
  "Leading keyword lists of a defmodule. Returns (values plist items)."
  (let ((body (cddr form)) (exports '()) (imports '()) (std '()) (entry nil))
    (loop while (and (consp (car body)) (keywordp (caar body)))
          do (let ((opt (pop body)))
               (case (car opt)
                 (:export (setf exports (append exports (mapcar #'spelling (cdr opt)))))
                 (:import (dolist (i (cdr opt))
                            (if (and (consp i) (eq (car i) :std))
                                (setf std (append std (cdr i)))
                                (push (spelling i) imports))))
                 (:entry (setf entry (second opt)))
                 (t (dsl-error form "unknown defmodule option ~s" (car opt))))))
    (values (list :exports exports :imports (nreverse imports) :std std :entry entry)
            body)))

(defun attach-free-methods (form items)
  "Move top level defmethods into the struct or class they belong to."
  (let ((methods (remove-if-not (lambda (i) (typep i 'method-item)) items))
        (rest (remove-if (lambda (i) (typep i 'method-item)) items)))
    (dolist (m methods rest)
      (let ((owner (find-if (lambda (i) (and (typep i 'struct-item)
                                             (string= (ir-name i) (ir-owner m))))
                            rest)))
        (unless owner
          (dsl-error form "method ~a: type ~a is not defined in this module"
                     (ir-name m) (ir-owner m)))
        (setf (ir-methods owner) (append (ir-methods owner) (list m)))))))

(defun apply-exports (form module)
  (dolist (e (ir-exports module))
    (let ((item (find e (ir-items module) :key #'ir-name :test #'string=)))
      (unless item
        (dsl-error form "module ~a exports ~a, which it does not define"
                   (ir-name module) e))
      (setf (ir-visibility item) :public))))

(defun parse-module-form (form)
  "Parse a (defmodule name options... items...) form into a module-item."
  (unless (and (consp form) (form-is (car form) "defmodule"))
    (dsl-error form "defmodule form expected"))
  (let ((name (require-name form)))
    (multiple-value-bind (opts body) (module-options form)
      (let ((module (make-module-item
                     :name name :exports (getf opts :exports) :imports (getf opts :imports)
                     :std-imports (getf opts :std) :entry-p (getf opts :entry)
                     :items (attach-free-methods form (mapcar #'parse-item body))
                     :source form)))
        (apply-exports form module)
        module))))

(defvar *module-forms* (make-hash-table :test 'equal)
  "Module name -> defmodule form, filled by DEFMODULE and REGISTER-MODULE.")

(defun register-module (form)
  "Register the defmodule FORM (possibly built with backquote) under its name."
  (let ((name (require-name form)))
    (setf (gethash name *module-forms*) form)
    name))

(defun find-module-form (name)
  (or (gethash (spelling name) *module-forms*)
      (dsl-error name "module ~a is not defined (defmodule)" (spelling name))))

(defmacro defmodule (name &body body)
  "Define a module of the generated program; the body is DSL (not evaluated)."
  `(register-module '(defmodule ,name ,@body)))

(defstruct project-spec
  "Result of DEFPROJECT; modules are parsed when the project is written."
  name modules entry)

(defvar *last-project* nil "The value of the last DEFPROJECT that was evaluated.")

(defmacro defproject (name &body options)
  "(defproject demo (:modules geometry app) (:entry app)). The value is also
stored in *LAST-PROJECT* for the CLI and the integration runner."
  `(setf *last-project*
         (make-project-spec :name ',name
                            :modules ',(cdr (assoc :modules options))
                            :entry ',(second (assoc :entry options)))))

(defun parse-project (spec)
  "Parse all modules of the PROJECT-SPEC into a project-item."
  (let* ((names (mapcar #'spelling (project-spec-modules spec)))
         (entry (and (project-spec-entry spec) (spelling (project-spec-entry spec)))))
    (when (null names)
      (dsl-error (project-spec-name spec) "project without modules"))
    (when (and entry (not (member entry names :test #'string=)))
      (dsl-error entry "entry module ~a is not part of the project" entry))
    (let ((modules (mapcar (lambda (n) (parse-module-form (find-module-form n))) names)))
      (dolist (m modules)
        (when (and entry (string= entry (ir-name m)))
          (setf (ir-entry-p m) t)))
      (make-project-item :name (spelling (project-spec-name spec)) :modules modules
                         :entry entry :source spec))))
