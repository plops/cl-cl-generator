;;;; test-check.lisp --- tests of the check pass (one positive and one negative
;;;; case per rule)

(in-package :polyglot.tests)

(def-suite :polyglot.unit.check :in :polyglot.unit)
(in-suite :polyglot.unit.check)

(defun checked (module-string)
  (let* ((m (parse-module-form (read-dsl module-string)))
         (p (make-project-item :name "t" :modules (list m) :entry (ir-name m))))
    (run-passes p (list :backend :test) :until :check)))

(defmacro check-ok (string)
  `(finishes (checked ,string)))

(defmacro check-fails (string &optional (needle nil))
  `(let ((c (handler-case (progn (checked ,string) nil) (dsl-error (e) e))))
     (is (typep c 'dsl-error))
     ,@(when needle `((is (search ,needle (princ-to-string c)))))))

(test e5-ownership
  (check-ok "(defmodule m (defun f () (let* ((a (vec-of :i64 1)) (b (clone a))) (push 2 b))))")
  (check-ok "(defmodule m (defun f () (let* ((a (vec-of :i64 1)) (b (move a))) (push 2 b))))")
  (check-fails "(defmodule m (defun f () (let* ((a (vec-of :i64 1)) (b a)) (push 2 b))))" "(clone a)")
  (check-ok "(defmodule m (defun f () (let* ((a 1) (b a)) (print-line (format-string \"{}\" b)))))"))

(test e5-sink-arguments
  (check-ok "(defmodule m (defun g (s) (declare (type :string s) (mode :sink s)) (print-line s))
                          (defun f () (let ((s \"x\")) (g (move s)))))")
  (check-fails "(defmodule m (defun g (s) (declare (type :string s) (mode :sink s)) (print-line s))
                          (defun f () (let ((s \"x\")) (g s))))"))

(test e7-nil
  (check-ok "(defmodule m (defun f () (declare (values (optional :i64))) nil))")
  (check-fails "(defmodule m (defun f () (let ((x nil)) (print-line \"a\"))))" "E7"))

(test e14-floats
  (check-ok "(defmodule m (defun f () (print-line (format-string \"{:.6f}\" 1.5))))")
  (check-fails "(defmodule m (defun f () (print-line (format-string \"{}\" 1.5))))" "E14")
  (check-fails "(defmodule m (defun f () (print-line (format-string \"{:.2f}\" 1))))")
  (check-fails "(defmodule m (defun f () (print-line (format-string \"{} {}\" 1))))")
  (check-fails "(defmodule m (defun f () (print-line (format-string \"{}\" true))))"))

(test e1-length
  (check-ok "(defmodule m (defun f (v) (declare (type (vec :i64) v) (values :i64)) (length v)))")
  (check-fails "(defmodule m (defun f (s) (declare (type :string s) (values :i64)) (length s)))" "E1"))

(test missing-return
  (check-ok "(defmodule m (defun f (x) (declare (type :i64 x) (values :i64)) (if (> x 0) x 0)))")
  (check-fails "(defmodule m (defun f (x) (declare (type :i64 x) (values :i64)) (when (> x 0) (return x))))"
               "not every path"))

(test read-only-parameters
  (check-ok "(defmodule m (defstruct p (x :i64)) (defun f (a) (declare (type p a) (mode :inout a)) (setf (dot a x) 1)))")
  (check-fails "(defmodule m (defstruct p (x :i64)) (defun f (a) (declare (type p a)) (setf (dot a x) 1)))"
               ":in (read-only)"))

(test k1b-borrows
  (check-ok "(defmodule m (defun first-word (s) (declare (type (view :string) s) (values (view :string))) s))")
  (check-ok "(defmodule m (defun longest (x y) (declare (type (view :string) x y) (values (view :string))
                                                         (borrows-from x y))
                           (if (> (string-byte-length x) (string-byte-length y)) x y)))")
  (check-fails "(defmodule m (defun longest (x y) (declare (type (view :string) x y) (values (view :string)))
                           (if (> (string-byte-length x) (string-byte-length y)) x y)))"
               "one or more of: x, y")
  (check-fails "(defmodule m (defun f (x) (declare (type (view :string) x) (values (view :string))
                                                   (borrows-from z)) x))"
               "no such parameter"))
