;;;; 83-cli.lisp --- entry point of polyglot-gen.sh

(in-package :polyglot)

(defparameter +cli-help+
  "usage: polyglot-gen.sh PROJECT.lisp [--targets cpp,rust,python,go,cl] [--out DIR]
                        [--mode minimal|full] [--no-format]

PROJECT.lisp defines modules with defmodule and ends with a defproject form.
The generated files are written to DIR/<target>/ (default ./out/); a file is
only rewritten when its content changes. Exit code 1 on a DSL error.")

(defun parse-cli-args (args)
  "Plist :file :targets :out :mode :format :help."
  (let ((result (list :targets +default-targets+ :out "out/" :mode :minimal :format t)))
    (loop while args
          do (let ((a (pop args)))
               (cond ((member a '("-h" "--help") :test #'string=) (setf (getf result :help) t))
                     ((string= a "--targets")
                      (setf (getf result :targets)
                            (mapcar (lambda (s) (normalize-backend-key s (intern (string-upcase s) :keyword)))
                                    (uiop:split-string (pop args) :separator ","))))
                     ((string= a "--out") (setf (getf result :out) (pop args)))
                     ((string= a "--mode") (setf (getf result :mode) (intern (string-upcase (pop args)) :keyword)))
                     ((string= a "--no-format") (setf (getf result :format) nil))
                     (t (setf (getf result :file) a)))))
    result))

(defun load-project-file (file)
  "Load FILE (a DSL project file) with a clean module registry; returns the
value of its DEFPROJECT."
  (clrhash *module-forms*)
  (setf *last-project* nil)
  (let ((*package* (find-package :polyglot-user))
        (*readtable* (copy-readtable nil))
        (*read-default-float-format* 'single-float))
    (load file))
  (or *last-project* (dsl-error file "~a contains no defproject form" file)))

(defun run-cli (args)
  "Generate the project named in ARGS; returns the process exit code."
  (let ((opts (parse-cli-args args)))
    (when (or (getf opts :help) (null (getf opts :file)))
      (format t "~a~%" +cli-help+)
      (return-from run-cli (if (getf opts :help) 0 2)))
    (handler-case
        (let* ((file (getf opts :file))
               (results (write-project (load-project-file file)
                                       :targets (getf opts :targets) :out (getf opts :out)
                                       :mode (getf opts :mode) :format (getf opts :format)
                                       :source-file file)))
          (dolist (r results)
            (format t "~&~(~a~)  ~a~%" (cdr r) (car r)))
          (format t "~&~d files, ~d written, ~d unchanged~%" (length results)
                  (count :written results :key #'cdr) (count :unchanged results :key #'cdr))
          0)
      (dsl-error (e)
        (format *error-output* "~&~a~%" e)
        1))))
