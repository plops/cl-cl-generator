(eval-when (:compile-toplevel :execute :load-toplevel)
  ;; Setup the registry path relative to this file so it can load the cl-cl-generator system.
  (let ((current-dir (make-pathname :directory (pathname-directory *load-pathname*))))
    (push (merge-pathnames "../../" current-dir) asdf:*central-registry*))
  (ql:quickload :cl-cl-generator))

(defpackage :cl-cl-generator/example-meta
  (:use :cl :cl-cl-generator))

(in-package :cl-cl-generator/example-meta)

;; =========================================================================
;; DETAILED SYSTEM EXPLANATIONS AND DESIGN COMMENTS (Generator-time only)
;; =========================================================================
;;
;; This script generates the complete source code for our cl-cl-generator/cl.lisp codebase.
;; By utilizing the pprint-dispatch mechanism, it prints standard CL forms natively, while using
;; custom predicates (like comment-form-p, comments-form-p, and raw-form-p) to recognize DSL forms
;; and format them cleanly.
;;

(let* ((output-dir (asdf:system-relative-pathname :cl-cl-generator "example/01_meta/"))
       (output-filename "run_meta")

       (code
         `(toplevel
            ;; The emitted file package declaration
            (in-package :cl-cl-generator)

            ;; Define the global state table to store hashes of generated files.
            (defparameter *file-hashes* (make-hash-table :test 'equal))

            ;; Copy the default pretty print table so we can safely add custom rules.
            (defparameter *cl-pprint-dispatch* (copy-pprint-dispatch nil))

            ;; -------------------------------------------------------------
            ;; PP-DISPATCH 1: pprint-toplevel
            ;; Formats top-level forms (toplevel/do0) separated by blank lines
            ;; without printing any enclosing parentheses.
            ;; -------------------------------------------------------------
            (defun pprint-toplevel (stream list)
              (pprint-logical-block (stream (cdr list))
                (loop
                  (pprint-exit-if-list-exhausted)
                  (let ((form (pprint-pop)))
                    (write form :stream stream)
                    (pprint-exit-if-list-exhausted)
                    ;; If the form we just wrote is a comment, we only print one newline.
                    ;; For other forms (like defun), we print two newlines to create a blank line.
                    (if (and (consp form) (member (car form) '(comment comments)))
                        (terpri stream)
                        (progn
                          (terpri stream)
                          (terpri stream)))))))

            (set-pprint-dispatch '(cons (member toplevel do0))
                                 'pprint-toplevel
                                 1
                                 *cl-pprint-dispatch*)

            ;; -------------------------------------------------------------
            ;; PP-DISPATCH 2: pprint-comment
            ;; Formats a single line comment (comment "text") into standard ;; formatting.
            ;; -------------------------------------------------------------
            (defun pprint-comment (stream list)
              (format stream ";; ~a" (second list)))

            ;; -------------------------------------------------------------
            ;; PP-DISPATCH 3: pprint-comments
            ;; Formats a multi-line comment form: (comments "line1" "line2")
            ;; -------------------------------------------------------------
            (defun pprint-comments (stream list)
              (let ((items (cdr list)))
                (loop for (c . rest) on items
                      do (format stream ";; ~a" c)
                         (when rest
                           (pprint-newline :mandatory stream)))))

            (defun comments-form-p (list)
              (and (consp list)
                   (eq (car list) 'comments)
                   (every #'stringp (cdr list))))

            ;; -------------------------------------------------------------
            ;; PP-DISPATCH 4: pprint-raw
            ;; Formats a raw code block: (raw "#+sbcl") -> #+sbcl without quotes.
            ;; -------------------------------------------------------------
            (defun pprint-raw (stream list)
              (write-string (second list) stream))

            ;; -------------------------------------------------------------
            ;; GENERATION-TIME DUP ELIMINATION: Single-String DSL Predicates
            ;; Generates 'comment-form-p' and 'raw-form-p' dynamically.
            ;; -------------------------------------------------------------
            ,@(loop for (op name) in '((comment comment-form-p)
                                       (raw raw-form-p))
                    collect `(defun ,name (list)
                               (and (consp list)
                                    (eq (car list) ',op)
                                    (consp (cdr list))
                                    (stringp (second list)))))

            ;; -------------------------------------------------------------
            ;; PP-DISPATCH REGISTRATION FOR DSL PREDICATES
            ;; -------------------------------------------------------------
            ,@(loop for (pred func) in '((comment-form-p pprint-comment)
                                         (comments-form-p pprint-comments)
                                         (raw-form-p pprint-raw))
                    collect `(set-pprint-dispatch ',(list 'satisfies pred) ',func 1 *cl-pprint-dispatch*))

            ;; -------------------------------------------------------------
            ;; HELPER: list-position-p
            ;; Identifies if a given block argument position expects a list.
            ;; -------------------------------------------------------------
            (defun list-position-p (op index)
              (case op
                ((defun defmacro defmethod) (= index 1))
                ((let let* flet labels destructuring-bind multiple-value-bind macrolet symbol-macrolet) (= index 0))
                (t nil)))

            ;; -------------------------------------------------------------
            ;; PP-DISPATCH 5: pprint-block-form
            ;; Universal block formatter.
            ;; -------------------------------------------------------------
            (defun pprint-block-form (stream list)
              (pprint-logical-block (stream list :prefix "(" :suffix ")")
                ;; Write the block operator
                (write (pprint-pop) :stream stream)
                (pprint-exit-if-list-exhausted)
                (write-char #\Space stream)
                ;; Print header elements (e.g. name and parameters)
                (let* ((op (car list))
                       (header-length
                         (case op
                           ((defun defmacro defmethod destructuring-bind multiple-value-bind) 2)
                           ((let let* flet labels when unless case macrolet symbol-macrolet) 1)
                           (t 0))))
                  (loop for i from 0 below header-length
                        do (let ((val (pprint-pop)))
                             ;; Print NIL as () if we are in a list position
                             (if (and (null val) (list-position-p op i))
                                 (write-string "()" stream)
                                 (write val :stream stream)))
                           (pprint-exit-if-list-exhausted)
                           (when (< (1+ i) header-length)
                             (write-char #\Space stream)))
                  ;; Indent by 1 unit offset
                  (pprint-indent :block 1 stream)
                  (pprint-newline :mandatory stream)
                  ;; Print the body forms on separate lines
                  (loop
                    (write (pprint-pop) :stream stream)
                    (pprint-exit-if-list-exhausted)
                    (pprint-newline :mandatory stream)))))

            ;; Register pprint-block-form for standard blocks using generation-time loop
            ,@(loop for sym in '(defun defmacro defmethod let let* flet labels
                                 progn locally macrolet symbol-macrolet
                                 when unless case cond multiple-value-bind destructuring-bind)
                    collect `(set-pprint-dispatch ',(list 'cons (list 'member sym)) 'pprint-block-form 1 *cl-pprint-dispatch*))

            ;; -------------------------------------------------------------
            ;; PP-DISPATCH 6: contains-comment-p
            ;; Custom predicate to detect if any nested list contains comments.
            ;; -------------------------------------------------------------
            (defun contains-comment-p (list)
              (and (consp list)
                   (alexandria:proper-list-p list)
                   (not (or (eq (car list) 'toplevel)
                            (eq (car list) 'do0)))
                   (some (lambda (x)
                           (and (consp x)
                                (member (car x) '(comment comments))))
                         list)))

            (set-pprint-dispatch '(satisfies contains-comment-p)
                                 'pprint-block-form
                                 2
                                 *cl-pprint-dispatch*)

            ;; -------------------------------------------------------------
            ;; PUBLIC API: emit-cl
            ;; Formats S-expressions to lowercase, pretty-printed Common Lisp code.
            ;; -------------------------------------------------------------
            (defun emit-cl (code)
              (let ((*print-pretty* t)
                    (*print-case* :downcase)
                    (*print-pprint-dispatch* *cl-pprint-dispatch*))
                (with-output-to-string (stream)
                  (write code :stream stream))))

            ;; -------------------------------------------------------------
            ;; PUBLIC API: write-source
            ;; Writes code to a file, using file hashing to preserve mtime.
            ;; -------------------------------------------------------------
            (defun write-source (name code &optional (dir (user-homedir-pathname)) ignore-hash)
              (let* ((filename (merge-pathnames (format nil "~a.lisp" name) dir))
                     (code-str (emit-cl code))
                     (fn-str (namestring filename))
                     (code-hash (sxhash code-str)))
                (multiple-value-bind (old-code-hash exists) (gethash fn-str *file-hashes*)
                  (when (or (not exists) ignore-hash (/= code-hash old-code-hash))
                    (setf (gethash fn-str *file-hashes*) code-hash)
                    (ensure-directories-exist filename)
                    (with-open-file (stream filename :direction :output :if-exists :supersede
                                           :if-does-not-exist :create)
                      (write-sequence code-str stream))))
                filename)))))

  ;; Write the generated code to example/01_meta/run_meta.lisp
  (let ((result-path (write-source output-filename code output-dir)))
    (format t "Successfully generated Meta Emitter at ~a~%" result-path)))
