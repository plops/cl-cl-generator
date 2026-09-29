;;;; lisp-check.lisp --- syntax gate: read every form, then load the system
;;;;
;;;; Invoked by tools/lisp-check.sh as
;;;;   sbcl --script-like ... --load tools/lisp-check.lisp --eval '(lisp-check:main (list "f1" ...))'
;;;; The files are read form by form with the POLYGLOT-SYNTAX readtable; on a
;;;; reader error the file, the number of the form and the start line of the
;;;; last form that could be read are printed. Afterwards the whole system is
;;;; loaded with :force t; every warning that is not a style warning, and
;;;; every style warning about undefined functions or variables, is an error.

(defpackage :lisp-check
  (:use :cl)
  (:export #:main))

(in-package :lisp-check)

(defvar *failed* nil)

(defun line-of (text position)
  "1-based line number of POSITION in TEXT."
  (1+ (count #\Newline text :end (min position (length text)))))

(defun switch-package (form)
  "Evaluate IN-PACKAGE forms whose package exists so symbols go to the right place."
  (when (and (consp form) (symbolp (car form))
             (string= (symbol-name (car form)) "IN-PACKAGE")
             (find-package (second form)))
    (setf *package* (find-package (second form)))))

(defun check-read (file)
  "Read FILE form by form, report the first reader error."
  (let* ((text (uiop:read-file-string file))
         (*readtable* (named-readtables:find-readtable 'polyglot:polyglot-syntax))
         (*package* (find-package :cl-user))
         (*read-default-float-format* 'double-float)
         (count 0)
         (last-start 0))
    (with-input-from-string (in text)
      (handler-case
          (loop
           (let ((start (progn (peek-char t in nil) (file-position in)))
                 (form (read in nil in)))
             (when (eq form in) (return t))
             (incf count)
             (setf last-start start)
             (switch-package form)))
        (error (e)
          (setf *failed* t)
          (format t "~&READ ERROR in ~a, form #~d (last good form started at line ~d):~%  ~a~%"
                  file (1+ count) (line-of text last-start) e)
          nil)))))

(defun undefined-style-warning-p (c)
  (search "undefined" (string-downcase (princ-to-string c))))

(defun check-load (systems)
  "Load SYSTEMS with :force t and turn real warnings into failures."
  (handler-bind ((warning
                  (lambda (c)
                    (when (or (not (typep c 'style-warning))
                              (undefined-style-warning-p c))
                      (setf *failed* t)
                      (format t "~&LOAD WARNING: ~a~%" c)))))
    (handler-case
        (let ((*compile-verbose* nil) (*load-verbose* nil))
          ;; :force t forces the dependencies too, so the last system suffices
          (asdf:load-system (car (last systems)) :force t))
      (error (e)
        (setf *failed* t)
        (format t "~&LOAD ERROR: ~a~%" e)))))

(defun main (files &key (systems '("polyglot-generator")))
  "Check FILES, then load SYSTEMS. Exit 0 on success."
  (dolist (f files)
    (check-read f))
  (unless *failed*
    (check-load systems))
  (cond (*failed* (format t "~&SBCL CHECK FAILED~%") (uiop:quit 1))
        (t (format t "~&SBCL CHECK OK~%") (uiop:quit 0))))
