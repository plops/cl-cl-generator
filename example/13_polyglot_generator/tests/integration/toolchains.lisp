;;;; toolchains.lisp --- per target: gate, build and run commands
;;;;
;;;; Every toolchain function receives the target directory and the project
;;;; and returns (values status stdout log): status :ok, :fail or :skipped.

(in-package :polyglot.integration)

(defun entry-module (project)
  (find (polyglot::project-spec-entry project) (polyglot::project-spec-modules project)
        :test #'string-equal))

(defun kebab (sym) (polyglot::spelling sym))

(defmacro with-steps ((log) &body steps)
  "Each step is (command-form &key directory env gate-name). The first failing
step makes the result :fail; the stdout of the last step is the output."
  `(let ((,log (make-string-output-stream)) (last-out ""))
     (block steps
       ,@(loop for (form . keys) in steps
               collect `(multiple-value-bind (code out err) (run ,form ,@keys)
                          (format ,log "$ ~{~a~^ ~}~%~a~a" ,form out err)
                          (setf last-out out)
                          (unless (zerop code)
                            (return-from steps (values :fail out (get-output-stream-string ,log))))))
       (values :ok last-out (get-output-stream-string ,log)))))

(defun cl-toolchain (dir project)
  (let* ((system (kebab (polyglot::project-spec-name project)))
         (pkg (format nil "~a.~a" system (kebab (entry-module project))))
         (load (format nil "(let ((err (make-string-output-stream))) (let ((*standard-output* (make-broadcast-stream)) (*error-output* err)) (handler-case (asdf:load-system ~s) (error (e) (format *error-output* \"~~a~~%~~a\" (get-output-stream-string err) e) (uiop:quit 4)))) (let ((text (get-output-stream-string err))) (when (or (search \"caught WARNING\" text) (search \"caught ERROR\" text)) (format *error-output* \"~~a\" text) (uiop:quit 3))))" system))
         (call (format nil "(~a::main)" pkg)))
    (with-steps (log)
      ((list "sbcl" "--noinform" "--non-interactive" "--no-userinit" "--no-sysinit"
             "--eval" "(require :asdf)"
             "--eval" (format nil "(push #p~s asdf:*central-registry*)" (namestring dir))
             "--eval" load "--eval" call)
       :directory dir))))

(defun python-toolchain (dir project)
  (let ((entry (format nil "~a.py" (polyglot::to-snake (kebab (entry-module project))))))
    (with-steps (log)
      ((list "ruff" "check" "--quiet" ".") :directory dir)
      ((list "python3" entry) :directory dir))))

(defun cpp-toolchain (dir project)
  (declare (ignore project))
  (let ((sources (mapcar #'namestring (directory (merge-pathnames "*.cpp" dir)))))
    (with-steps (log)
      ((append (list "g++" "-std=c++20" "-Wall" "-Wextra" "-Werror" "-O0" "-o" "prog") sources)
       :directory dir)
      ((list "./prog") :directory dir))))

(defun rust-toolchain (dir project)
  (declare (ignore project))
  (let ((env (list (format nil "CARGO_TARGET_DIR=~a" (namestring (merge-pathnames "_cargo/" (build-dir)))))))
    (with-steps (log)
      ((list "cargo" "clippy" "--quiet" "--" "-D" "warnings") :directory dir :env env)
      ((list "cargo" "run" "--quiet") :directory dir :env env))))

(defun go-toolchain (dir project)
  (declare (ignore project))
  (with-steps (log)
    ((list "go" "vet" "./...") :directory dir)
    ((list "go" "run" ".") :directory dir)))

(defparameter *toolchains*
  '((:cl "sbcl" cl-toolchain) (:python "python3" python-toolchain) (:cpp "g++" cpp-toolchain)
    (:rust "cargo" rust-toolchain) (:go "go" go-toolchain))
  "Target -> required tool, toolchain function.")

(defun target-dir-name (target)
  (polyglot::backend-directory (polyglot::find-backend target)))
