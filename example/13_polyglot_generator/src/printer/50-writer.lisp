;;;; 50-writer.lisp --- line and indentation builder for the text backends

(in-package :polyglot)

(defstruct writer
  (lines (make-array 16 :adjustable t :fill-pointer 0))
  (indent 0)
  (unit "    "))

(defvar *writer* nil "The writer that EMIT-LINE appends to.")

(defun current-indent-string ()
  (with-output-to-string (s)
    (dotimes (i (writer-indent *writer*))
      (write-string (writer-unit *writer*) s))))

(defun emit-line (control &rest args)
  "Append one line (FORMAT CONTROL ARGS) at the current indentation. Embedded
newlines start new lines at the same indentation; empty lines stay empty."
  (let ((text (if args (apply #'format nil control args) control))
        (prefix (current-indent-string)))
    (dolist (line (cl-ppcre:split "\\n" text :limit most-positive-fixnum))
      (vector-push-extend (if (string= line "") "" (concatenate 'string prefix line))
                          (writer-lines *writer*)))))

(defun emit-blank-line ()
  "Append an empty line unless the previous line is already empty."
  (let ((lines (writer-lines *writer*)))
    (unless (or (zerop (length lines)) (string= "" (aref lines (1- (length lines)))))
      (vector-push-extend "" lines))))

(defmacro with-indent (() &body body)
  `(progn (incf (writer-indent *writer*))
          (unwind-protect (progn ,@body)
            (decf (writer-indent *writer*)))))

(defmacro with-block ((open close) &body body)
  "Emit OPEN, the indented BODY and CLOSE (CLOSE NIL emits nothing)."
  `(progn (emit-line ,open)
          (with-indent () ,@body)
          (let ((c ,close)) (when c (emit-line c)))))

(defun writer-string (writer)
  "All lines joined with newlines, trailing blank lines removed and exactly one
final newline."
  (let* ((lines (coerce (writer-lines writer) 'list))
         (trimmed (reverse (member-if (lambda (l) (string/= l "")) (reverse lines)))))
    (format nil "~{~a~%~}" trimmed)))

(defmacro with-output-lines ((&key (unit "    ")) &body body)
  "Run BODY with a fresh *WRITER* and return the produced text."
  `(let ((*writer* (make-writer :unit ,unit)))
     ,@body
     (writer-string *writer*)))
