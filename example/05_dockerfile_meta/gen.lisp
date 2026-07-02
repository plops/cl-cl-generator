(eval-when (:compile-toplevel :execute :load-toplevel)
  ;; Setup the registry path relative to this file so it can load the cl-cl-generator system.
  (let ((current-dir (make-pathname :directory (pathname-directory *load-pathname*))))
    (push (merge-pathnames "../../" current-dir) asdf:*central-registry*))
  (ql:quickload :cl-cl-generator))

(defpackage :cl-dockerfile-generator/meta
  (:use :cl :cl-cl-generator))

(defpackage :cl-dockerfile-generator
  (:use :cl))

(in-package :cl-dockerfile-generator/meta)

;; Register reader macro for raw strings during generator load
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
                   for c = (read-char stream t nil t)
                   do (cond
                        ((char= c #\() (incf depth) (write-char c out))
                        ((char= c #\)) (decf depth) (if (zerop depth)
                                                         (loop-finish)
                                                         (write-char c out)))
                        (t (write-char c out))))))
          ((char= delimiter #\[)
           (with-output-to-string (out)
             (loop with depth = 1
                   for c = (read-char stream t nil t)
                   do (cond
                        ((char= c #\[) (incf depth) (write-char c out))
                        ((char= c #\]) (decf depth) (if (zerop depth)
                                                         (loop-finish)
                                                         (write-char c out)))
                        (t (write-char c out))))))
          ((char= delimiter #\{)
           (with-output-to-string (out)
             (loop with depth = 1
                   for c = (read-char stream t nil t)
                   do (cond
                        ((char= c #\{) (incf depth) (write-char c out))
                        ((char= c #\}) (decf depth) (if (zerop depth)
                                                         (loop-finish)
                                                         (write-char c out)))
                        (t (write-char c out))))))
          (t
           (with-output-to-string (out)
             (loop for c = (read-char stream t nil t)
                   until (char= c delimiter)
                   do (write-char c out)))))))))

(let* ((output-dir (asdf:system-relative-pathname :cl-cl-generator "example/05_dockerfile_meta/source01/"))
       (output-filename "dock")
       (code
         `(toplevel
            (defpackage :cl-dockerfile-generator
              (:use :cl)
              (:export :emit-df :write-df))
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
                               for c = (read-char stream t nil t)
                               do (cond
                                    ((char= c #\() (incf depth) (write-char c out))
                                    ((char= c #\)) (decf depth) (if (zerop depth)
                                                                     (loop-finish)
                                                                     (write-char c out)))
                                    (t (write-char c out))))))
                      ((char= delimiter #\[)
                       (with-output-to-string (out)
                         (loop with depth = 1
                               for c = (read-char stream t nil t)
                               do (cond
                                    ((char= c #\[) (incf depth) (write-char c out))
                                    ((char= c #\]) (decf depth) (if (zerop depth)
                                                                     (loop-finish)
                                                                     (write-char c out)))
                                    (t (write-char c out))))))
                      ((char= delimiter #\{)
                       (with-output-to-string (out)
                         (loop with depth = 1
                               for c = (read-char stream t nil t)
                               do (cond
                                    ((char= c #\{) (incf depth) (write-char c out))
                                    ((char= c #\}) (decf depth) (if (zerop depth)
                                                                     (loop-finish)
                                                                     (write-char c out)))
                                    (t (write-char c out))))))
                      (t
                       (with-output-to-string (out)
                         (loop for c = (read-char stream t nil t)
                               until (char= c delimiter)
                               do (write-char c out)))))))))

            (defparameter *file-hashes* (make-hash-table :test 'equal))

            (declaim (ftype (function (t) string) emit-df))

            (defun emit-val (x)
              (cond
                ((stringp x) x)
                ((symbolp x) (format nil "~a" x))
                ((numberp x) (format nil "~a" x))
                ((listp x) (emit-df x))
                (t (format nil "~a" x))))

            (defun parse-copy-add-args (args allowed-options)
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
                      (if (and (cdr args) (cddr args))
                          (format nil "ENV ~{~a=~a~^ \\~%    ~}"
                                  (loop for (k v) on args by #'cddr
                                        collect (emit-val k) collect (emit-val v)))
                          (format nil "ENV ~a=~a" (emit-val (first args)) (emit-val (second args))))))
                   (run
                    (let ((args (cdr code)))
                      (cond
                        ((eq (first args) :heredoc)
                         (format nil "RUN <<EOF~%~a~%EOF" (emit-val (second args))))
                        ((eq (first args) :mount)
                         (format nil "RUN --mount=~a ~a" (emit-val (second args)) (emit-df (caddr args))))
                        (t
                         (format nil "RUN ~a" (emit-df (first args)))))))
                   (and
                    (format nil "~{~a~^ \\~% && ~}" (mapcar #'emit-df (cdr code))))
                   (seq
                    (format nil "~{~a~^ \\~%; ~}" (mapcar #'emit-df (cdr code))))
                   (pipe
                    (format nil "~{~a~^ | ~}" (mapcar #'emit-df (cdr code))))
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
                   (expose
                    (format nil "EXPOSE ~{~a~^ ~}" (mapcar #'emit-val (cdr code))))
                   (label
                    (format nil "LABEL ~{~a=~s~^ \\~%      ~}"
                            (loop for (k v) on (cdr code) by #'cddr
                                  collect (emit-val k) collect (emit-val v))))
                   (onbuild
                    (format nil "ONBUILD ~a" (emit-df (second code))))
                   (comment
                    (format nil "# ~a" (emit-val (second code))))
                   (shell
                    (format nil "SHELL [~{~s~^, ~}]" (mapcar #'emit-val (second code))))
                   (stopsignal
                    (format nil "STOPSIGNAL ~a" (emit-val (second code))))
                   (healthcheck
                    (let ((args (cdr code)))
                      (multiple-value-bind (cmd interval timeout start-period retries)
                          (let (cmd interval timeout start-period retries (lst args))
                            (loop while lst
                                  do (cond
                                       ((eq (car lst) :interval) (setf interval (cadr lst) lst (cddr lst)))
                                       ((eq (car lst) :timeout) (setf timeout (cadr lst) lst (cddr lst)))
                                       ((eq (car lst) :start-period) (setf start-period (cadr lst) lst (cddr lst)))
                                       ((eq (car lst) :retries) (setf retries (cadr lst) lst (cddr lst)))
                                       (t (setf cmd (car lst) lst (cdr lst)))))
                            (values cmd interval timeout start-period retries))
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
                                    (emit-val cmd))))))
                   ,@(loop for (sym inst) in '((cmd "CMD")
                                               (entrypoint "ENTRYPOINT")
                                               (volume "VOLUME"))
                           collect `(,sym
                                     (let ((val (second code)))
                                       (if (listp val)
                                           (format nil "~a [~{~s~^, ~}]" ,inst (mapcar #'emit-val val))
                                           (format nil "~a ~a" ,inst (emit-val val))))))
                   ,@(loop for (sym inst) in '((workdir "WORKDIR")
                                               (user "USER"))
                            collect `(,sym (format nil "~a ~a" ,inst (emit-val (second code)))))
                 (t (format nil "~a ~{~a~^ ~}" (emit-val (car code)) (mapcar #'emit-val (cdr code))))))
                (t (emit-val code))))

            (defun write-df (filename code &optional ignore-hash)
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
