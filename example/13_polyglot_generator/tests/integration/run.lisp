;;;; run.lisp --- integration runner (V-INT): generate, compile, run, compare
;;;;
;;;; For every program tests/integration/programs/pNN_name/{project.lisp,expected.txt}
;;;; and every target: write-project to build/<prog>/, run the idiomatic gate
;;;; and the program, compare stdout with expected.txt. Missing tools give
;;;; SKIPPED, never PASS. On FAIL, build/<prog>/<target>/failure.log holds the
;;;; diff and the tool output.

(defpackage :polyglot.integration
  (:use :cl)
  (:export #:main))

(in-package :polyglot.integration)

(defvar *root* (uiop:pathname-parent-directory-pathname
                (uiop:pathname-directory-pathname (or *load-truename* *compile-file-truename*))))
(defvar *project-dir* (uiop:pathname-parent-directory-pathname *root*))
(defparameter *all-targets* '(:cl :python :cpp :rust :go))

(defun programs-dir () (merge-pathnames "tests/integration/programs/" *project-dir*))
(defun build-dir () (merge-pathnames "build/" *project-dir*))

(defun all-programs ()
  (sort (mapcar (lambda (d) (car (last (pathname-directory d))))
                (uiop:subdirectories (programs-dir)))
        #'string<))

(defun load-program (name)
  "Load project.lisp of program NAME; returns (values project-spec path)."
  (let ((file (merge-pathnames (format nil "~a/project.lisp" name) (programs-dir))))
    (clrhash polyglot::*module-forms*)
    (setf polyglot:*last-project* nil)
    (let ((*package* (find-package :polyglot-user))
          (*readtable* (copy-readtable nil))
          (*read-default-float-format* 'single-float))
      (load file))
    (values polyglot:*last-project* file)))

(defun run (command &key directory env)
  "Run COMMAND (list) in DIRECTORY: (values exit-code stdout stderr)."
  (let ((cmd (if env (append (list "env") env command) command)))
    (multiple-value-bind (out err code)
        (uiop:run-program cmd :directory directory :output :string :error-output :string
                          :ignore-error-status t :external-format :utf-8)
      (values code out err))))

(defun tool-available-p (name) (polyglot::find-executable name))

(defstruct result program target status (seconds 0) (note ""))

(defun write-failure-log (dir expected actual log)
  (let ((path (merge-pathnames "failure.log" dir)))
    (ensure-directories-exist path)
    (with-open-file (s path :direction :output :if-exists :supersede :external-format :utf-8)
      (format s "=== expected ===~%~a~%=== actual ===~%~a~%=== tool output ===~%~a~%"
              expected actual log))
    path))
