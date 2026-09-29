;;;; main.lisp --- integration runner: loop over programs and targets

(in-package :polyglot.integration)

(defvar *bless* nil "--bless: write a missing expected.txt from the CL output.")

(defun backend-available-p (target)
  (gethash target polyglot::*backends*))

(defun run-one (program target)
  "Generate PROGRAM for TARGET, run its toolchain and compare with expected.txt."
  (let* ((start (get-internal-real-time))
         (entry (assoc target *toolchains*))
         (result (make-result :program program :target target)))
    (flet ((done (status note)
             (setf (result-status result) status (result-note result) note
                   (result-seconds result) (/ (- (get-internal-real-time) start)
                                              internal-time-units-per-second))
             result))
      (cond ((not (backend-available-p target)) (done :skipped "no backend"))
            ((not (tool-available-p (second entry))) (done :skipped (format nil "~a missing" (second entry))))
            (t (run-generated program target (third entry) #'done))))))

(defun run-generated (program target toolchain done)
  (multiple-value-bind (project file) (load-program program)
    (let* ((out (merge-pathnames (format nil "~a/" program) (build-dir)))
           (dir (merge-pathnames (format nil "~a/" (target-dir-name target)) out))
           (expected-file (merge-pathnames (format nil "~a/expected.txt" program) (programs-dir)))
           (expected (and (probe-file expected-file) (uiop:read-file-string expected-file :external-format :utf-8))))
      (uiop:delete-file-if-exists (merge-pathnames "failure.log" dir))
      (handler-case
          (handler-bind ((warning #'muffle-warning))
            (polyglot:write-project project :targets (list target) :out out :source-file file))
        (polyglot:dsl-error (e)
          (write-failure-log dir (or expected "") "" (princ-to-string e))
          (return-from run-generated (funcall done :fail "generation error"))))
      (multiple-value-bind (status actual log) (funcall toolchain dir project)
        (cond ((eq status :fail)
               (write-failure-log dir (or expected "") actual log)
               (funcall done :fail "tool failed"))
              ((and (null expected) *bless* (eq target :cl))
               (with-open-file (s expected-file :direction :output :external-format :utf-8)
                 (write-string actual s))
               (funcall done :pass "expected.txt written from the CL oracle"))
              ((null expected)
               (write-failure-log dir "" actual log)
               (funcall done :fail "no expected.txt (actual output in failure.log)"))
              ((string/= expected actual)
               (write-failure-log dir expected actual log)
               (funcall done :fail "output differs"))
              (t (funcall done :pass "")))))))

(defun print-summary (results)
  (format t "~&~%~20a ~8a ~8a ~7a ~a~%" "program" "target" "status" "seconds" "note")
  (dolist (r results)
    (format t "~20a ~8a ~8a ~7,2f ~a~%" (result-program r)
            (string-downcase (symbol-name (result-target r)))
            (result-status r) (float (result-seconds r)) (result-note r)))
  (format t "~&PASS ~d  FAIL ~d  SKIPPED ~d~%"
          (count :pass results :key #'result-status)
          (count :fail results :key #'result-status)
          (count :skipped results :key #'result-status)))

(defun parse-args (args)
  (let ((programs '()) (targets *all-targets*) (determinism nil))
    (loop while args
          do (let ((a (pop args)))
               (cond ((string= a "--targets")
                      (setf targets (mapcar (lambda (s) (polyglot::normalize-backend-key
                                                         nil (intern (string-upcase s) :keyword)))
                                            (uiop:split-string (pop args) :separator ","))))
                     ((string= a "--determinism") (setf determinism t))
                     ((string= a "--bless") (setf *bless* t))
                     (t (push a programs)))))
    (values (or (nreverse programs) (all-programs)) targets determinism)))

(defun main (args)
  "Entry point of run-integration.sh. Returns the process exit code."
  (multiple-value-bind (programs targets determinism) (parse-args args)
    (if determinism
        (run-determinism programs targets)
        (let ((results (loop for p in programs
                             append (loop for tg in targets
                                          collect (let ((r (run-one p tg)))
                                                    (format t "~&~a/~(~a~): ~a~%" p tg (result-status r))
                                                    (finish-output)
                                                    r)))))
          (print-summary results)
          (if (find :fail results :key #'result-status) 1 0)))))
