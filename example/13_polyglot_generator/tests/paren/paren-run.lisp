;;;; paren-run.lisp --- build and run the precedence programs per backend

(in-package :polyglot.tests)

(defun paren-dir (backend mode)
  (asdf:system-relative-pathname :polyglot-generator
                                 (format nil "build/_paren/~(~a~)-~(~a~)/" backend mode)))

(defun run-command (command dir &optional env)
  (multiple-value-bind (out err code)
      (uiop:run-program (if env (append (list "env") env command) command)
                        :directory dir :output :string :error-output :string
                        :ignore-error-status t :external-format :utf-8)
    (values code out err)))

(defun paren-build-and-run (backend dir)
  "Compile and run the generated program in DIR/<backend dir>; stdout or NIL."
  (let* ((root (merge-pathnames (format nil "~a/" (backend-directory (find-backend backend))) dir))
         (cargo (format nil "CARGO_TARGET_DIR=~a"
                        (namestring (asdf:system-relative-pathname :polyglot-generator "build/_cargo/"))))
         (steps (ecase backend
                  (:cl (list (list "sbcl" "--noinform" "--non-interactive" "--no-userinit" "--eval" "(require :asdf)"
                                   "--eval" (format nil "(push #p~s asdf:*central-registry*)" (namestring root))
                                   "--eval" "(let ((*standard-output* (make-broadcast-stream))) (asdf:load-system \"paren\"))"
                                   "--eval" "(paren.paren::main)")))
                  (:python (list (list "python3" "paren.py")))
                  (:cpp (list (list "g++" "-std=c++20" "-O0" "-o" "prog" "paren.cpp") (list "./prog")))
                  (:rust (list (list "cargo" "run" "--quiet")))
                  (:go (list (list "go" "run" "."))))))
    (loop for step in steps
          for last = (null (cdr (member step steps)))
          do (multiple-value-bind (code out err) (run-command step root (when (eq backend :rust) (list cargo)))
               (unless (zerop code)
                 (format t "~&  ~(~a~) failed: ~a~%" backend (subseq err 0 (min 400 (length err))))
                 (return nil))
               (when last (return out))))))

(defparameter *paren-tools* '((:cl . "sbcl") (:python . "python3") (:cpp . "g++") (:rust . "cargo") (:go . "go")))

(defun run-paren-tests (&key (count 400))
  "Entry point of ./run-tests.sh --paren. Returns T when every available
backend prints the oracle values in both modes."
  (let* ((exprs (paren-expressions count))
         (expected (append (mapcar #'oracle-value exprs) (list 17)))
         (project (paren-project exprs))
         (ok t))
    (dolist (entry *paren-tools* ok)
      (destructuring-bind (backend . tool) entry
        (if (not (find-executable tool))
            (format t "~&~(~a~): SKIPPED (~a missing)~%" backend tool)
            (dolist (mode '(:full :minimal))
              (let ((dir (paren-dir backend mode)))
                (handler-bind ((warning #'muffle-warning))
                  (write-project project :targets (list backend) :out dir :mode mode :format nil))
                (let* ((out (paren-build-and-run backend dir))
                       (values (and out (mapcar #'parse-integer (cl-ppcre:split "\\n" (string-trim '(#\Newline) out)))))
                       (bad (if values (count nil (mapcar #'eql values expected)) (length expected))))
                  (format t "~&~(~a~) ~(~a~): ~:[FAIL (~d of ~d differ)~;PASS (~*~d values)~]~%"
                          backend mode (and values (= (length values) (length expected)) (zerop bad))
                          bad (length expected))
                  (unless (and values (zerop bad)) (setf ok nil))))))))))
