(eval-when (:compile-toplevel :execute :load-toplevel)
  ;; Setup the registry path relative to this file so it can load the cl-cl-generator system.
  (let ((current-dir (make-pathname :directory (pathname-directory *load-pathname*))))
    (push (merge-pathnames "../../" current-dir) asdf:*central-registry*))
  (ql:quickload :cl-cl-generator))

(defpackage :cl-dockerfile-generator/meta
  (:use :cl :cl-cl-generator)
  (:documentation "Package for the meta-generator that constructs the Dockerfile generator."))

(defpackage :cl-dockerfile-generator
  (:use :cl)
  (:documentation "The main package of the generated Dockerfile generator library."))

(in-package :cl-dockerfile-generator/meta)

;; Register reader macro for raw strings during generator load.
;; This defines the #r reader macro for the compiler/reader parsing this meta-generator file itself.
;; Although this meta-generator doesn't directly use #r, we register it for consistency.
;; We use eval of a backquoted form with splicing to avoid repeating the bracket-reading loop.
(eval-when (:compile-toplevel :execute :load-toplevel)
  (setf (readtable-case *readtable*) :invert)
  (eval
    `(set-dispatch-macro-character #\# #\r
       (lambda (stream char arg)
         (declare (ignore char arg))
         (let ((delimiter (read-char stream t nil t)))
           (cond
             ,@(loop for (open close) in '((#\( #\)) (#\[ #\]) (#\{ #\}))
                     collect `((char= delimiter ,open)
                               (with-output-to-string (out)
                                 (loop with depth = 1
                                       for c = (read-char stream t nil t)
                                       do (cond
                                            ((char= c ,open) (incf depth) (write-char c out))
                                            ((char= c ,close) (decf depth) (if (zerop depth)
                                                                             (loop-finish)
                                                                             (write-char c out)))
                                            (t (write-char c out)))))))
             (t
              (with-output-to-string (out)
                (loop for c = (read-char stream t nil t)
                      until (char= c delimiter)
                      do (write-char c out))))))))))

(let* ((output-dir (asdf:system-relative-pathname :cl-cl-generator "example/05_dockerfile_meta/source01/"))
       (output-filename "dock")
       (code
         `(toplevel
            (defpackage :cl-dockerfile-generator
              (:use :cl)
              (:export :emit-df :write-df)
              (:documentation "Main package for the generated cl-dockerfile-generator library.
Defines DSL emission (emit-df) and file-writing utilities (write-df)."))
            (in-package :cl-dockerfile-generator)

            ;; Register reader macro for raw strings during runtime of the generated library.
            ;; This is crucial so that target scripts/templates using cl-dockerfile-generator
            ;; can read multi-line shell command blocks without having to escape double quotes.
            (eval-when (:compile-toplevel :execute :load-toplevel)
              (setf (readtable-case *readtable*) :invert)
              (set-dispatch-macro-character #\# #\r
                (lambda (stream char arg)
                  (declare (ignore char arg))
                  (let ((delimiter (read-char stream t nil t)))
                    (cond
                      ,@(loop for (open close) in '((#\( #\)) (#\[ #\]) (#\{ #\}))
                              collect `((char= delimiter ,open)
                                        (with-output-to-string (out)
                                          (loop with depth = 1
                                                for c = (read-char stream t nil t)
                                                do (cond
                                                     ((char= c ,open) (incf depth) (write-char c out))
                                                     ((char= c ,close) (decf depth) (if (zerop depth)
                                                                                      (loop-finish)
                                                                                      (write-char c out)))
                                                     (t (write-char c out)))))))
                      (t
                       (with-output-to-string (out)
                         (loop for c = (read-char stream t nil t)
                               until (char= c delimiter)
                               do (write-char c out)))))))))

            (defparameter *file-hashes* (make-hash-table :test 'equal)
              "A global hash table storing the hashes of written files to optimize build times.
Keys are file names (namestrings), and values are their corresponding sxhash values.")

            (declaim (ftype (function (t) string) emit-df))

            (defun emit-val (x)
              "Convert a literal Lisp value into its equivalent Dockerfile string representation.
- Strings are emitted directly as raw text.
- Lists are recursively compiled by calling `emit-df`.
- Symbols and numbers are formatted into their string counterparts."
              (cond
                ((stringp x) x)
                ((listp x) (emit-df x))
                (t (format nil "~a" x))))

            (defun parse-copy-add-args (args allowed-options)
              "Separate the positional path arguments (sources and destination) from the keyword options
(like :from or :chown) in COPY and ADD instructions.
Returns two values:
1. A list of positional path arguments.
2. A plist (property list) containing the recognized keyword options."
              (let (paths plist (lst args))
                (loop while lst
                      do (if (and (keywordp (car lst)) (member (car lst) allowed-options))
                             (progn
                               ;; Recognized option: store in plist and advance by 2
                               (setf (getf plist (car lst)) (cadr lst))
                               (setf lst (cddr lst)))
                             (progn
                               ;; Positional path argument: collect and advance by 1
                               (push (car lst) paths)
                               (setf lst (cdr lst)))))
                (values (nreverse paths) plist)))

            (defun emit-df (code)
              "The central compiler for the Dockerfile DSL. Recurses through the AST and formats each
form to produce clean, well-formatted Dockerfile instructions."
              (cond
                ((null code) "")
                ((listp code)
                 (case (car code)
                   ;; Group top-level forms without extra wrapping
                   (cl-dockerfile-generator::toplevel
                    (with-output-to-string (s)
                      (loop for form in (cdr code)
                            do (format s "~a~%" (emit-df form)))))
                   ;; Directive comment: # key=value
                   (directive
                    (destructuring-bind (name val) (cdr code)
                      (format nil "# ~a=~a" (emit-val name) (emit-val val))))
                   ;; FROM instruction: FROM <image> [AS <name>]
                   (from
                    (destructuring-bind (image &key as) (cdr code)
                      (if as
                          (format nil "FROM ~a AS ~a" (emit-val image) (emit-val as))
                          (format nil "FROM ~a" (emit-val image)))))
                   ;; ARG instruction: ARG <name>[=<default>]
                   (arg
                    (destructuring-bind (name &optional val) (cdr code)
                      (if val
                          (format nil "ARG ~a=~a" (emit-val name) (emit-val val))
                          (format nil "ARG ~a" (emit-val name)))))
                   ;; ENV instruction: ENV <key>=<val> ... (newline-separated)
                   (env
                    (let ((args (cdr code)))
                      (format nil "ENV ~{~a=~a~^ \\~%    ~}"
                              (loop for (k v) on args by #'cddr
                                    collect (emit-val k) collect (emit-val v)))))
                   ;; RUN instruction: supports normal commands, heredocs, and mount binds
                   (run
                    (let ((args (cdr code)))
                      (cond
                        ((eq (first args) :heredoc)
                         (format nil "RUN <<EOF~%~a~%EOF" (emit-val (second args))))
                        ((eq (first args) :mount)
                         (format nil "RUN --mount=~a ~a" (emit-val (second args)) (emit-df (caddr args))))
                        (t
                         (format nil "RUN ~a" (emit-df (first args)))))))
                   ;; && operator: concatenates shell commands with ' && ' and line continuation
                   (and
                    (format nil "~{~a~^ \\~% && ~}" (mapcar #'emit-df (cdr code))))
                   ;; ; operator: concatenates shell commands sequentially with ';'
                   (seq
                    (format nil "~{~a~^ \\~%; ~}" (mapcar #'emit-df (cdr code))))
                   ;; Pipe operator: joins commands with '|'
                   (pipe
                    (format nil "~{~a~^ | ~}" (mapcar #'emit-df (cdr code))))
                   ;; COPY instruction: supports options (--from, --chown) or heredoc format
                   (copy
                    (let ((args (cdr code)))
                      (if (eq (first args) :heredoc)
                          (destructuring-bind (dest content) (cdr args)
                            (format nil "COPY <<EOF ~a~%~a~%EOF" (emit-val dest) (emit-val content)))
                          (multiple-value-bind (paths options) (parse-copy-add-args args '(:from :chown))
                            (let ((dest (car (last paths)))
                                  (srcs (butlast paths))
                                  (from (getf options :from))
                                  (chown (getf options :chown)))
                              (format nil "COPY~@[ --from=~a~]~@[ --chown=~a~] ~{~a~^ ~} ~a"
                                      (and from (emit-val from))
                                      (and chown (emit-val chown))
                                      (mapcar #'emit-val srcs)
                                      (emit-val dest)))))))
                   ;; ADD instruction: supports --chown options
                   (add
                    (let ((args (cdr code)))
                      (multiple-value-bind (paths options) (parse-copy-add-args args '(:chown))
                        (let ((dest (car (last paths)))
                              (srcs (butlast paths))
                              (chown (getf options :chown)))
                          (format nil "ADD~@[ --chown=~a~] ~{~a~^ ~} ~a"
                                  (and chown (emit-val chown))
                                  (mapcar #'emit-val srcs)
                                  (emit-val dest))))))
                   ;; EXPOSE instruction: EXPOSE port1 port2 ...
                   (expose
                    (format nil "EXPOSE ~{~a~^ ~}" (mapcar #'emit-val (cdr code))))
                   ;; LABEL instruction: LABEL key="val" (newline-separated)
                   (label
                    (format nil "LABEL ~{~a=~s~^ \\~%      ~}"
                            (loop for (k v) on (cdr code) by #'cddr
                                  collect (emit-val k) collect (emit-val v))))
                   ;; ONBUILD wrapper
                   (onbuild
                    (format nil "ONBUILD ~a" (emit-df (second code))))
                   ;; Comments: # comment-text
                   (comment
                    (format nil "# ~a" (emit-val (second code))))
                   ;; SHELL instruction: SHELL ["/bin/bash", "-c"]
                   (shell
                    (format nil "SHELL [~{~s~^, ~}]" (mapcar #'emit-val (second code))))
                   ;; STOPSIGNAL instruction
                   (stopsignal
                    (format nil "STOPSIGNAL ~a" (emit-val (second code))))
                   ;; HEALTHCHECK instruction: supports options and CMD
                   (healthcheck
                    (let ((args (cdr code)))
                      (multiple-value-bind (cmds options)
                          (parse-copy-add-args args '(:interval :timeout :start-period :retries))
                        (let ((cmd (car cmds))
                              (interval (getf options :interval))
                              (timeout (getf options :timeout))
                              (start-period (getf options :start-period))
                              (retries (getf options :retries)))
                          (format nil "HEALTHCHECK~@[ --interval=~a~]~@[ --timeout=~a~]~@[ --start-period=~a~]~@[ --retries=~a~] ~a"
                                  (and interval (emit-val interval))
                                  (and timeout (emit-val timeout))
                                  (and start-period (emit-val start-period))
                                  (and retries (emit-val retries))
                                  (if (listp cmd)
                                      (let ((val (second cmd)))
                                        (if (listp val)
                                            (format nil "~a [~{~s~^, ~}]" (emit-val (first cmd)) (mapcar #'emit-val val))
                                            (format nil "~a ~a" (emit-val (first cmd)) (emit-val val))))
                                      (emit-val cmd)))))))
                   ;; Splicing for standard instructions that support both array-json and shell modes
                   ,@(loop for (sym inst) in '((cmd "CMD")
                                               (entrypoint "ENTRYPOINT")
                                               (volume "VOLUME"))
                            collect `(,sym
                                      (let ((val (second code)))
                                        (if (listp val)
                                            (format nil "~a [~{~s~^, ~}]" ,inst (mapcar #'emit-val val))
                                            (format nil "~a ~a" ,inst (emit-val val))))))
                   ;; Splicing for standard single-parameter commands
                   ,@(loop for (sym inst) in '((workdir "WORKDIR")
                                               (user "USER"))
                             collect `(,sym (format nil "~a ~a" ,inst (emit-val (second code)))))
                  (t (format nil "~a ~{~a~^ ~}" (emit-val (car code)) (mapcar #'emit-val (cdr code))))))
                (t (emit-val code))))

            (defun write-df (filename code &optional ignore-hash)
              "Write the compiled S-expression AST to the specified file path.
It calculates the sxhash of the resulting Dockerfile content and checks against `*file-hashes*`
to determine if the file needs writing. This avoids updating the file modification time (mtime)
unnecessarily, speeding up builds."
              (let* ((code-str (emit-df code))
                     (fn-str (namestring filename))
                     (code-hash (sxhash code-str)))
                (multiple-value-bind (old-code-hash exists) (gethash fn-str *file-hashes*)
                  (when (or (not exists) ignore-hash (/= code-hash old-code-hash))
                    (setf (gethash fn-str *file-hashes*) code-hash)
                    (ensure-directories-exist filename)
                    (with-open-file (stream filename :direction :output :if-exists :supersede :if-does-not-exist :create)
                      (write-sequence code-str stream))))
                filename)))))
  (let ((result-path (write-source output-filename code output-dir)))
    (format t "Successfully generated cl-dockerfile-generator at ~a~%" result-path)))
