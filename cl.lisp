(in-package :cl-cl-generator)

(defparameter *file-hashes* (make-hash-table :test 'equal))

(defparameter *cl-pprint-dispatch* (copy-pprint-dispatch nil))

;; 1. Pretty print toplevel / do0 forms (separated by blank lines, without outer parentheses)
(defun pprint-toplevel (stream list)
  (pprint-logical-block (stream (cdr list))
    (loop
      (pprint-exit-if-list-exhausted)
      (let ((form (pprint-pop)))
        (write form :stream stream)
        (pprint-exit-if-list-exhausted)
        ;; For comments at the top level, only print a single newline.
        ;; Otherwise, print two newlines to separate top-level definitions with a blank line.
        (if (and (consp form) (member (car form) '(comment comments)))
            (terpri stream)
            (progn
              (terpri stream)
              (terpri stream)))))))

(set-pprint-dispatch '(cons (member toplevel do0))
                     'pprint-toplevel
                     1
                     *cl-pprint-dispatch*)

;; 2. Pretty print single-line comments
(defun pprint-comment (stream list)
  (format stream ";; ~a" (second list)))

(set-pprint-dispatch '(cons (member comment))
                     'pprint-comment
                     1
                     *cl-pprint-dispatch*)

;; 3. Pretty print multi-line comments
(defun pprint-comments (stream list)
  (let ((items (cdr list)))
    (loop for (c . rest) on items
          do (format stream ";; ~a" c)
             (when rest
               (pprint-newline :mandatory stream)))))

(set-pprint-dispatch '(cons (member comments))
                     'pprint-comments
                     1
                     *cl-pprint-dispatch*)

;; 4. Pretty print raw strings directly (raw code insertion / custom formatting)
(defun pprint-raw (stream list)
  (write-string (second list) stream))

(set-pprint-dispatch '(cons (member raw))
                     'pprint-raw
                     1
                     *cl-pprint-dispatch*)

;; Helper to identify if a block header position expects a list (where NIL should print as '()')
(defun list-position-p (op index)
  (case op
    ((defun defmacro defmethod) (= index 1))
    ((let let* flet labels destructuring-bind multiple-value-bind macrolet symbol-macrolet) (= index 0))
    (t nil)))

;; 5. Pretty print blocks (defun, let, progn, etc.) to force newlines and proper 2-space indent
(defun pprint-block-form (stream list)
  (pprint-logical-block (stream list :prefix "(" :suffix ")")
    ;; Print the operator
    (write (pprint-pop) :stream stream)
    (pprint-exit-if-list-exhausted)
    (write-char #\Space stream)
    ;; Print header elements (e.g. name and lambda list for defun)
    (let* ((op (car list))
           (header-length
             (case op
               ((defun defmacro defmethod destructuring-bind multiple-value-bind) 2)
               ((let let* flet labels when unless case macrolet symbol-macrolet) 1)
               (t 0))))
      (loop for i from 0 below header-length
            do (let ((val (pprint-pop)))
                 (if (and (null val) (list-position-p op i))
                     (write-string "()" stream)
                     (write val :stream stream)))
               (pprint-exit-if-list-exhausted)
               (when (< (1+ i) header-length)
                 (write-char #\Space stream)))
      ;; 1 block indentation unit (offset) relative to the start of inside the prefix "(" is column 2
      (pprint-indent :block 1 stream)
      (pprint-newline :mandatory stream)
      ;; Print the body forms, each on its own line
      (loop
        (write (pprint-pop) :stream stream)
        (pprint-exit-if-list-exhausted)
        (pprint-newline :mandatory stream)))))

;; Register all standard block-like symbols to use our block-form pretty printer
(dolist (sym '(defun defmacro defmethod let let* flet labels
               progn locally macrolet symbol-macrolet
               when unless case cond multiple-value-bind destructuring-bind))
  (set-pprint-dispatch `(cons (member ,sym))
                       'pprint-block-form
                       1
                       *cl-pprint-dispatch*))

;; Predicate to identify any list containing a comment or comments form, excluding top-level forms
(defun contains-comment-p (list)
  (and (consp list)
       (not (member (car list) '(toplevel do0)))
       (some (lambda (x)
               (and (consp x)
                    (member (car x) '(comment comments))))
             list)))

;; Register pprint-block-form for any list containing comments to force multi-line formatting
(set-pprint-dispatch '(satisfies contains-comment-p)
                     'pprint-block-form
                     2
                     *cl-pprint-dispatch*)

;; --- Public API ---

(defun emit-cl (code)
  "Convert S-expression code into a formatted Common Lisp string."
  (let ((*print-pretty* t)
        (*print-case* :downcase)
        (*print-pprint-dispatch* *cl-pprint-dispatch*))
    (with-output-to-string (stream)
      (write code :stream stream))))

(defun write-source (name code &optional (dir (user-homedir-pathname)) ignore-hash)
  "Write the S-expression code as a formatted Lisp file.
If the file exists and its content is identical (verified via hashing),
writing is skipped to avoid touching the file's modification time."
  (let* ((filename (merge-pathnames (format nil "~a.lisp" name) dir))
         (code-str (emit-cl code))
         (fn-str (namestring filename))
         (code-hash (sxhash code-str)))
    (multiple-value-bind (old-code-hash exists) (gethash fn-str *file-hashes*)
      (when (or (not exists) ignore-hash (/= code-hash old-code-hash))
        (setf (gethash fn-str *file-hashes*) code-hash)
        (ensure-directories-exist filename)
        (with-open-file (stream filename
                               :direction :output
                               :if-exists :supersede
                               :if-does-not-exist :create)
          (write-sequence code-str stream))))
    filename))
