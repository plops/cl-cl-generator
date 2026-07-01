(defpackage :cl-cl-generator/tests
  (:use :cl :cl-cl-generator)
  (:export :run-tests))

(in-package :cl-cl-generator/tests)

(defparameter *test-cases*
  '((:name "basic-toplevel"
     :input (toplevel
             (in-package :test-package)
             (defun hello ()
               (print "hello")))
     :expected "(in-package :test-package)

(defun hello ()
  (print \"hello\"))")

    (:name "comments-formatting"
     :input (toplevel
             (comment "this is a top-level comment")
             (defun foo (x)
               (comment "inside a defun")
               (let ((y (1+ x)))
                 (comments "first line of comment"
                           "second line of comment")
                 (* y y))))
     :expected ";; this is a top-level comment
(defun foo (x)
  ;; inside a defun
  (let ((y (1+ x)))
    ;; first line of comment
    ;; second line of comment
    (* y y)))")

    (:name "raw-code-insertion"
     :input (toplevel
             (defun bar ()
               (raw "#+sbcl")
               (print "sbcl only")))
     :expected "(defun bar ()
  #+sbcl
  (print \"sbcl only\"))")

    (:name "standard-nested-forms"
     :input (toplevel
             (defun test-nested (a b)
               (cond
                 ((< a b) (let ((val (* a 2)))
                            val))
                 (t b))))
     :expected "(defun test-nested (a b)
  (cond
    ((< a b)
     (let ((val (* a 2)))
       val))
    (t b)))")

    (:name "nested-comment-in-cond"
     :input (toplevel
              (defun compute-power (base &optional (exponent 2))
                (let ((result (expt base exponent)))
                  (cond
                    ((> result 1000)
                     (comment "Scale down huge values")
                     (/ result 10))
                    (t result)))))
     :expected "(defun compute-power (base &optional (exponent 2))
  (let ((result (expt base exponent)))
    (cond
      ((> result 1000)
        ;; Scale down huge values
        (/ result 10))
      (t result))))")

    (:name "multiline-comment-string"
     :input (toplevel
             (defun greet ()
               (comment "hello
world
wide")
               (print "hi")))
     :expected "(defun greet ()
  ;; hello
  ;; world
  ;; wide
  (print \"hi\"))")

    (:name "new-block-forms"
     :input (toplevel
             (lambda (x y)
               (comment "lambda body")
               (+ x y))
             (eval-when (:compile-toplevel :load-toplevel :execute)
               (defclass my-class ()
                 ((slot :initarg :slot))))
             (dolist (item list)
               (print item)))
     :expected "(lambda (x y)
  ;; lambda body
  (+ x y))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defclass my-class ()
    ((slot :initarg :slot))))

(dolist (item list)
  (print item))")))

(defun run-tests ()
  (let ((*package* (find-package :cl-cl-generator/tests)))
    (format t "Running cl-cl-generator tests...~%")
    (let ((failed 0)
          (passed 0))
      (dolist (tc *test-cases*)
        (let* ((name (getf tc :name))
               (input (getf tc :input))
               (expected (getf tc :expected))
               ;; Force a standard right-margin of 80 to ensure consistent line breaks across test environments
               (actual (let ((*print-right-margin* 80))
                         (emit-cl input)))
               ;; Trim trailing newlines and whitespace for a clean comparison
               (actual-trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) actual))
               (expected-trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) expected)))
          (if (string= actual-trimmed expected-trimmed)
              (progn
                (incf passed)
                (format t "  [PASS] ~a~%" name))
              (progn
                (incf failed)
                (format t "  [FAIL] ~a~%" name)
                (format t "    Expected:~%~S~%" expected-trimmed)
                (format t "    Actual:~%~S~%" actual-trimmed)))))
      
      ;; Test file hashing & mtime preservation
      (let* ((test-dir (merge-pathnames "scratch/" (user-homedir-pathname)))
             (test-file-base "hash-test")
             (test-file-path (merge-pathnames "hash-test.lisp" test-dir))
             (code1 '(toplevel (defun test-hash () 1)))
             (code2 '(toplevel (defun test-hash () 2))))
        
        (format t "Testing write-source hashing behavior...~%")
        (ensure-directories-exist test-file-path)
        
        ;; Delete file if it exists to start fresh
        (when (probe-file test-file-path)
          (delete-file test-file-path))
        
        ;; First write (file should be created)
        (write-source test-file-base code1 test-dir)
        (let ((mtime1 (file-write-date test-file-path)))
          (unless mtime1
            (format t "  [FAIL] File was not created by write-source~%")
            (incf failed))
          
          ;; Wait a small fraction of a second to ensure different file-write-date if written
          (sleep 1)
          
          ;; Second write with same code (should NOT rewrite, keeping same mtime)
          (write-source test-file-base code1 test-dir)
          (let ((mtime2 (file-write-date test-file-path)))
            (if (= mtime1 mtime2)
                (format t "  [PASS] file-write-date preserved (hashing works)~%")
                (progn
                  (format t "  [FAIL] file-write-date changed despite identical contents~%")
                  (incf failed))))
          
          ;; Third write with different code (should rewrite, updating mtime)
          (sleep 1)
          (write-source test-file-base code2 test-dir)
          (let ((mtime3 (file-write-date test-file-path)))
            (if (/= mtime1 mtime3)
                (format t "  [PASS] file-write-date updated for changed contents~%")
                (progn
                  (format t "  [FAIL] file-write-date failed to update for changed contents~%")
                  (incf failed))))))
      
      (format t "~%Passed: ~a, Failed: ~a~%" passed failed)
      (if (> failed 0)
          (sb-ext:exit :code 1)
          (sb-ext:exit :code 0)))))
