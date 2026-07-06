(defpackage :cl-dockerfile-generator
  (:use :cl)
  (:export :emit-df :write-df)
  (:documentation "Main package for the generated cl-dockerfile-generator library.
Defines DSL emission (emit-df) and file-writing utilities (write-df)."))

(in-package :cl-dockerfile-generator)

(eval-when (:compile-toplevel :execute :load-toplevel)
  (setf (readtable-case *readtable*) :invert)
  (set-dispatch-macro-character #\# #\r
                                (lambda (stream char arg)
                                  (declare (ignore char arg))
                                  (let ((delimiter (read-char stream t nil t)))
                                    (cond
                                      ((char= delimiter #\()
                                       (with-output-to-string (out)
                                         (loop with depth = 1
                                               for c = (read-char stream t nil
                                                                  t)
                                               do (cond
                                                    ((char= c #\() (incf depth)
                                                     (write-char c out))
                                                    ((char= c #\)) (decf depth)
                                                     (if (zerop depth)
                                                         (loop-finish)
                                                         (write-char c out)))
                                                    (t (write-char c out))))))
                                      ((char= delimiter #\[)
                                       (with-output-to-string (out)
                                         (loop with depth = 1
                                               for c = (read-char stream t nil
                                                                  t)
                                               do (cond
                                                    ((char= c #\[) (incf depth)
                                                     (write-char c out))
                                                    ((char= c #\]) (decf depth)
                                                     (if (zerop depth)
                                                         (loop-finish)
                                                         (write-char c out)))
                                                    (t (write-char c out))))))
                                      ((char= delimiter #\{)
                                       (with-output-to-string (out)
                                         (loop with depth = 1
                                               for c = (read-char stream t nil
                                                                  t)
                                               do (cond
                                                    ((char= c #\{) (incf depth)
                                                     (write-char c out))
                                                    ((char= c #\}) (decf depth)
                                                     (if (zerop depth)
                                                         (loop-finish)
                                                         (write-char c out)))
                                                    (t (write-char c out))))))
                                      (t
                                       (with-output-to-string (out)
                                         (loop for c = (read-char stream t nil
                                                                  t)
                                               until (char= c delimiter)
                                               do (write-char c out)))))))))

(defparameter *file-hashes*
  (make-hash-table :test 'equal)
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
                   (setf (getf plist (car lst)) (cadr lst))
                   (setf lst (cddr lst)))
                 (progn
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
       (cl-dockerfile-generator::toplevel
        (with-output-to-string (s)
          (loop for form in (cdr code)
                do (format s "~a~%" (emit-df form)))))
       (directive
        (destructuring-bind (name val) (cdr code)
          (format nil "# ~a=~a" (emit-val name) (emit-val val))))
       (from
        (destructuring-bind (image &key as) (cdr code)
          (if as
              (format nil "FROM ~a AS ~a" (emit-val image) (emit-val as))
              (format nil "FROM ~a" (emit-val image)))))
       (arg
        (destructuring-bind (name &optional val) (cdr code)
          (if val
              (format nil "ARG ~a=~a" (emit-val name) (emit-val val))
              (format nil "ARG ~a" (emit-val name)))))
       (env
        (let ((args (cdr code)))
          (format nil "ENV ~{~a=~a~^ \\~%    ~}"
                  (loop for (k v) on args by #'cddr
                        collect (emit-val k)
                        collect (emit-val v)))))
       (run
        (let ((args (cdr code)))
          (cond
            ((eq (first args) :heredoc)
             (format nil "RUN <<'EOF'~%~a~%EOF" (emit-val (second args))))
            ((eq (first args) :mount)
             (format nil "RUN --mount=~a ~a" (emit-val (second args))
                     (emit-df (caddr args))))
            (t (format nil "RUN ~a" (emit-df (first args)))))))
       (and (format nil "~{~a~^ \\~% && ~}" (mapcar #'emit-df (cdr code))))
       (seq (format nil "~{~a~^ \\~%; ~}" (mapcar #'emit-df (cdr code))))
       (pipe (format nil "~{~a~^ | ~}" (mapcar #'emit-df (cdr code))))
       (copy
        (let ((args (cdr code)))
          (if (eq (first args) :heredoc)
              (destructuring-bind (dest content) (cdr args)
                (format nil "COPY <<'EOF' ~a~%~a~%EOF" (emit-val dest)
                        (emit-val content)))
              (multiple-value-bind (paths options) (parse-copy-add-args args
                                                    '(:from :chown))
                (let ((dest (car (last paths))) (srcs (butlast paths))
                      (from (getf options :from)) (chown (getf options :chown)))
                  (format nil
                          "COPY~@[ --from=~a~]~@[ --chown=~a~] ~{~a~^ ~} ~a"
                          (and from (emit-val from))
                          (and chown (emit-val chown)) (mapcar #'emit-val srcs)
                          (emit-val dest)))))))
       (add
        (let ((args (cdr code)))
          (multiple-value-bind (paths options) (parse-copy-add-args args
                                                '(:chown))
            (let ((dest (car (last paths))) (srcs (butlast paths))
                  (chown (getf options :chown)))
              (format nil "ADD~@[ --chown=~a~] ~{~a~^ ~} ~a"
                      (and chown (emit-val chown)) (mapcar #'emit-val srcs)
                      (emit-val dest))))))
       (expose (format nil "EXPOSE ~{~a~^ ~}" (mapcar #'emit-val (cdr code))))
       (label
        (format nil "LABEL ~{~a=~s~^ \\~%      ~}"
                (loop for (k v) on (cdr code) by #'cddr
                      collect (emit-val k)
                      collect (emit-val v))))
       (onbuild (format nil "ONBUILD ~a" (emit-df (second code))))
       (comment (format nil "# ~a" (emit-val (second code))))
       (shell
        (format nil "SHELL [~{~s~^, ~}]" (mapcar #'emit-val (second code))))
       (stopsignal (format nil "STOPSIGNAL ~a" (emit-val (second code))))
       (healthcheck
        (let ((args (cdr code)))
          (multiple-value-bind (cmds options) (parse-copy-add-args args
                                               '(:interval :timeout
                                                 :start-period :retries))
            (let ((cmd (car cmds)) (interval (getf options :interval))
                  (timeout (getf options :timeout))
                  (start-period (getf options :start-period))
                  (retries (getf options :retries)))
              (format nil
                      "HEALTHCHECK~@[ --interval=~a~]~@[ --timeout=~a~]~@[ --start-period=~a~]~@[ --retries=~a~] ~a"
                      (and interval (emit-val interval))
                      (and timeout (emit-val timeout))
                      (and start-period (emit-val start-period))
                      (and retries (emit-val retries))
                      (if (listp cmd)
                          (let ((val (second cmd)))
                            (if (listp val)
                                (format nil "~a [~{~s~^, ~}]"
                                        (emit-val (first cmd))
                                        (mapcar #'emit-val val))
                                (format nil "~a ~a" (emit-val (first cmd))
                                        (emit-val val))))
                          (emit-val cmd)))))))
       (cmd
        (let ((val (second code)))
          (if (listp val)
              (format nil "~a [~{~s~^, ~}]" "CMD" (mapcar #'emit-val val))
              (format nil "~a ~a" "CMD" (emit-val val)))))
       (entrypoint
        (let ((val (second code)))
          (if (listp val)
              (format nil "~a [~{~s~^, ~}]" "ENTRYPOINT"
                      (mapcar #'emit-val val))
              (format nil "~a ~a" "ENTRYPOINT" (emit-val val)))))
       (volume
        (let ((val (second code)))
          (if (listp val)
              (format nil "~a [~{~s~^, ~}]" "VOLUME" (mapcar #'emit-val val))
              (format nil "~a ~a" "VOLUME" (emit-val val)))))
       (workdir (format nil "~a ~a" "WORKDIR" (emit-val (second code))))
       (user (format nil "~a ~a" "USER" (emit-val (second code))))
       (t
        (format nil "~a ~{~a~^ ~}" (emit-val (car code))
                (mapcar #'emit-val (cdr code))))))
    (t (emit-val code))))

(defun write-df (filename code &optional ignore-hash)
  "Write the compiled S-expression AST to the specified file path.
It calculates the sxhash of the resulting Dockerfile content and checks against `*file-hashes*`
to determine if the file needs writing. This avoids updating the file modification time (mtime)
unnecessarily, speeding up builds."
  (let* ((code-str (emit-df code)) (fn-str (namestring filename))
         (code-hash (sxhash code-str)))
    (multiple-value-bind (old-code-hash exists) (gethash fn-str *file-hashes*)
      (when (or (not exists) ignore-hash (/= code-hash old-code-hash))
        (setf (gethash fn-str *file-hashes*) code-hash)
        (ensure-directories-exist filename)
        (with-open-file
            (stream filename :direction :output :if-exists :supersede
             :if-does-not-exist :create)
          (write-sequence code-str stream))))
    filename))