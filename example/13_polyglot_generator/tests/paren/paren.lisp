;;;; paren.lisp --- randomized precedence differential tests (R7)
;;;;
;;;; 400 random integer expressions of depth <= 3 (LCG, seed 42) over
;;;; a=7 b=3 c=2 d=5 are printed by one program per backend, generated once
;;;; with full parentheses (the oracle mode) and once with minimal ones. Both
;;;; runs must print the value that SBCL computes for the expression.

(in-package :polyglot.tests)

(defvar *lcg-state* 42)

(defun lcg-next ()
  (setf *lcg-state* (mod (+ (* *lcg-state* 1103515245) 12345) (expt 2 31))))

(defun lcg-below (n) (mod (floor (lcg-next) 16) n))

(defun random-leaf ()
  (case (lcg-below 3)
    (0 (nth (lcg-below 4) '(a b c d)))
    (1 (1+ (lcg-below 9)))
    (t (- (1+ (lcg-below 9))))))

(defun random-expr (depth)
  (if (or (zerop depth) (< (lcg-below 10) 2))
      (random-leaf)
      (flet ((sub () (random-expr (1- depth))))
        (case (lcg-below 12)
          ((0 1) `(+ ,(sub) ,(sub)))
          ((2 3) `(- ,(sub) ,(sub)))
          (4 `(* ,(sub) ,(sub)))
          (5 `(- ,(sub)))
          (6 `(logand ,(sub) ,(sub)))
          (7 `(logior ,(sub) ,(sub)))
          (8 `(logxor ,(sub) ,(sub)))
          (9 `(,(nth (lcg-below 4) '(truncate floor mod rem)) ,(sub) (+ 1 (abs ,(sub)))))
          (10 `(shl ,(sub) ,(1+ (lcg-below 3))))
          (t `(shr ,(sub) ,(1+ (lcg-below 3))))))))

(defun oracle-form (form)
  "FORM as a CL form (shl/shr -> ash, truncate/floor -> primary value)."
  (cond ((atom form) form)
        ((string-equal (symbol-name (car form)) "shl") `(ash ,(oracle-form (second form)) ,(third form)))
        ((string-equal (symbol-name (car form)) "shr") `(ash ,(oracle-form (second form)) (- ,(third form))))
        (t (cons (car form) (mapcar #'oracle-form (cdr form))))))

(defun oracle-value (form)
  (eval `(let ((a 7) (b 3) (c 2) (d 5)) (declare (ignorable a b c d)) (values ,(oracle-form form)))))

(defun paren-expressions (&optional (n 400))
  (let ((*lcg-state* 42))
    (loop repeat n collect (random-expr 3))))

(defun paren-module (exprs)
  `(polyglot:defmodule paren (:entry t)
                       (defun main ()
                         (let ((a 7) (b 3) (c 2) (d 5))
                           ,@(loop for e in exprs collect `(print-line (format-string "{}" ,e)))
                           (print-line (format-string "{}" (+ a b c d)))))))

(defun paren-project (exprs)
  (let ((module (parse-module-form (paren-module exprs))))
    (setf (ir-entry-p module) t)
    (make-project-item :name "paren" :modules (list module) :entry "paren")))
