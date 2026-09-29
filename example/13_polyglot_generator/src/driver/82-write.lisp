;;;; 82-write.lisp --- write-project: idempotent, deterministic output

(in-package :polyglot)

(defparameter +default-targets+ '(:cpp :rust :python :go :cl))

(defun source-info (source-file)
  "File name and git blob hash of SOURCE-FILE. The blob hash depends only on
the content, so regenerating never changes the header by itself."
  (if (and source-file (probe-file source-file))
      (list :file (file-namestring source-file)
            :hash (multiple-value-bind (out err code)
                      (ignore-errors
                        (uiop:run-program (list "git" "-c" "safe.directory=*" "hash-object"
                                                (namestring source-file))
                                          :output :string :error-output :string
                                          :ignore-error-status t))
                    (declare (ignore err))
                    (if (and out (eql code 0))
                        (subseq (string-trim '(#\Newline #\Space) out) 0 10)
                        "unknown")))
      (list :file "unknown" :hash "unknown")))

(defun read-file-or-nil (path)
  (when (probe-file path)
    (uiop:read-file-string path :external-format :utf-8)))

(defun write-if-changed (path text)
  "Write TEXT to PATH unless the file already has exactly this content.
Returns :written or :unchanged."
  (if (equal text (read-file-or-nil path))
      :unchanged
      (progn
        (ensure-directories-exist path)
        (with-open-file (s path :direction :output :if-exists :supersede
                           :if-does-not-exist :create :external-format :utf-8)
          (write-string text s))
        :written)))

(defun final-text (artifact info format)
  (let ((text (concatenate 'string (or (header-comment artifact info) "")
                           (artifact-content artifact))))
    (if format (format-artifact-text artifact text) text)))

(defun write-artifacts (backend artifacts out info format)
  (loop for a in artifacts
        for path = (merge-pathnames (concatenate 'string (backend-directory backend) "/"
                                                 (artifact-path a))
                                    (uiop:ensure-directory-pathname out))
        collect (cons (namestring path) (write-if-changed path (final-text a info format)))))

(defun coerce-project (project)
  (etypecase project
    (project-item project)
    (project-spec (parse-project project))))

(defun write-project (project &key (targets +default-targets+) (out "out/") (format t)
                                (mode :minimal) source-file)
  "Generate PROJECT (a DEFPROJECT value or project-item) for TARGETS below OUT.
Every file gets a header comment; a file is only written when its content
changed (the comparison happens after formatting). Returns a list of
(path . :written|:unchanged)."
  (let ((project (coerce-project project))
        (info (source-info source-file))
        (*warned-formatters* '()))
    (loop for key in targets
          for backend = (find-backend key)
          append (write-artifacts backend (generate-artifacts backend project :mode mode)
                                  out info format))))

(defun generate-project (project &key (targets +default-targets+) (mode :minimal))
  "Like WRITE-PROJECT but returns an alist target -> artifacts without writing."
  (let ((project (coerce-project project)))
    (loop for key in targets
          collect (cons key (generate-artifacts (find-backend key) project :mode mode)))))
