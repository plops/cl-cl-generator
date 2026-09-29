;;;; p06_borrows --- borrow relations (K1b): longest with borrows-from, a
;;;; parser struct over (view :string) with next-token, a slice iterator over
;;;; (view (vec :i64))

(in-package :polyglot-user)
(in-dsl)

(defmodule borrows (:entry t)
  (defun longest (x y)
    (declare (type (view :string) x y) (values (view :string)) (borrows-from x y))
    (if (> (string-byte-length x) (string-byte-length y)) x y))

  (defun first-word (s)
    "Elision: exactly one reference parameter."
    (declare (type (view :string) s) (values (view :string)))
    (let ((space (string-find s #\Space 0)))
      (if (< space 0) s (string-slice s 0 space))))

  (defstruct parser (input (view :string)) (pos :i64 0)
    (defmethod next-token ((p :inout))
      (declare (values (optional (view :string))))
      (let ((n (string-byte-length (dot p input))))
        (when (>= (dot p pos) n)
          (return nil))
        (let* ((start (dot p pos))
               (space (string-find (dot p input) #\Space start))
               (end (if (< space 0) n space)))
          (setf (dot p pos) (+ end 1))
          (some (string-slice (dot p input) start end))))))

  (defstruct window (data (view (vec :i64))) (index :i64 0)
    (defmethod next-value ((w :inout))
      (declare (values (optional :i64)))
      (if (< (dot w index) (length (dot w data)))
          (progn
            (incf (dot w index))
            (some (aref (dot w data) (- (dot w index) 1))))
          nil)))

  (defun main ()
    (let ((a "hello") (b "polyglot!"))
      (print-line (format-string "longest: {}" (longest a b)))
      (print-line (format-string "first word: {}" (first-word "borrowed views everywhere"))))
    (let ((p (make-parser :input "the quick brown fox"))
          (running true))
      (while running
        (if-let (tok (next-token p))
          (print-line (format-string "token: {}" tok))
          (setf running false))))
    (let* ((nums (vec-of :i64 3 1 4 1 5))
           (w (make-window :data nums))
           (sum 0)
           (running true))
      (while running
        (if-let (v (next-value w))
          (incf sum v)
          (setf running false)))
      (print-line (format-string "sum = {}" sum)))))

(defproject borrows (:modules borrows) (:entry borrows))
