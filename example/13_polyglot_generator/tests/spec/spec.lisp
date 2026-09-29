;;;; spec.lisp --- spec table: expected output per backend, doc generator
;;;;
;;;; (define-spec name
;;;;   :tags (:expr ...) :doc "text"
;;;;   :params ((a :i64) ...) :ret :i64 :items ("(defstruct ...)")
;;;;   :lisp <DSL form, the body of a function spec-f>
;;;;   :expect (:cl "..." :python "..." ...)       ; substring after whitespace normalization
;;;;   :expect-error (:python unsupported-construct ...))

(in-package :polyglot.tests)

(defvar *specs* '() "List of spec plists in definition order.")

(defmacro define-spec (name &rest plist)
  `(progn
     (setf *specs* (append (remove ',name *specs* :key (lambda (s) (getf s :name)))
                           (list (list* :name ',name ',plist))))
     ',name))

(defun normalize-ws (string)
  (string-trim " " (cl-ppcre:regex-replace-all "\\s+" string " ")))

(defun spec-module-string (spec)
  (let ((*print-case* :downcase))
    (format nil "(defmodule spec-m (:entry t) ~{~a ~} (defun spec-f ~a (declare ~{(type ~a ~a)~^ ~} ~{(mode ~s ~a)~^ ~} ~@[(values ~a)~]) ~a))"
            (getf spec :items)
            (mapcar #'first (getf spec :params))
            (loop for (n ty) in (getf spec :params) append (list (dsl-string ty) n))
            (loop for (n m) in (getf spec :modes) append (list m n))
            (and (getf spec :ret) (dsl-string (getf spec :ret)))
            (dsl-string (getf spec :lisp)))))

(defun dsl-string (form)
  "Print FORM so that READ-DSL reads it back (lower case, strings escaped)."
  (let ((*readtable* (named-readtables:find-readtable 'polyglot:polyglot-syntax))
        (*print-pretty* nil) (*read-default-float-format* 'double-float))
    (prin1-to-string form)))

(defun spec-output (spec backend)
  "Generated text of the spec module for BACKEND (all artifacts, unformatted)."
  (let* ((module (parse-module-form (read-dsl (spec-module-string spec))))
         (project (make-project-item :name "spec" :modules (list module) :entry "spec-m")))
    (handler-bind ((warning #'muffle-warning))
      (format nil "~{~a~%~}" (mapcar #'artifact-content
                                     (generate-artifacts (find-backend backend) project))))))

(defun check-spec (spec backend expected)
  (let ((out (normalize-ws (spec-output spec backend))))
    (is (search (normalize-ws expected) out)
        "spec ~(~a~) [~(~a~)]: expected~%  ~a~%in~%  ~a" (getf spec :name) backend expected out)))

(defun check-spec-error (spec backend condition)
  (let ((signalled (handler-case (progn (spec-output spec backend) nil)
                     (error (c) (typep c condition)))))
    (is-true signalled "spec ~(~a~) [~(~a~)]: expected ~(~a~)" (getf spec :name) backend condition)))

(in-suite :polyglot.spec)

(test spec-table
  (dolist (spec *specs*)
    (loop for (backend expected) on (getf spec :expect) by #'cddr
          when (gethash backend *backends*)
          do (check-spec spec backend expected))
    (loop for (backend condition) on (getf spec :expect-error) by #'cddr
          when (gethash backend *backends*)
          do (check-spec-error spec backend condition))))
