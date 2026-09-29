;;;; docs.lisp --- SUPPORTED_FORMS.md from the spec table (R11)

(in-package :polyglot.tests)

(defparameter *doc-backends* '(:cl :python :cpp :rust :go))

(defun supported-forms-path ()
  (asdf:system-relative-pathname :polyglot-generator "SUPPORTED_FORMS.md"))

(defun md-code (string)
  "STRING as inline code for a Markdown table cell."
  (if (or (null string) (string= string ""))
      ""
      (format nil "`~a`" (cl-ppcre:regex-replace-all "\\|" (normalize-ws string) "\\\\|"))))

(defun spec-cell (spec backend)
  (let ((expected (getf (getf spec :expect) backend))
        (err (getf (getf spec :expect-error) backend)))
    (cond (expected (md-code expected))
          (err (format nil "*~(~a~)*" err))
          (t "—"))))

(defun spec-tags ()
  (let ((tags '()))
    (dolist (s *specs*) (dolist (tg (getf s :tags)) (pushnew tg tags)))
    (sort tags #'string< :key #'symbol-name)))

(defun supported-forms-text ()
  (with-output-to-string (out)
    (format out "# Supported forms~%~%")
    (format out "Generated from the spec table in `tests/spec/` by `./run-tests.sh --docs`.~%")
    (format out "Do not edit by hand; `./run-tests.sh --docs-check` fails when this file is outdated.~%~%")
    (format out "Every cell is a fragment of the generated code (whitespace normalized) that the~%")
    (format out "spec test checks; *unsupported-construct* means the backend rejects the form (R4).~%")
    (format out "~%~d entries, ~d tags.~%" (length *specs*) (length (spec-tags)))
    (dolist (tag (spec-tags))
      (format out "~%## ~:(~a~)~%~%| Name | DSL | ~{~a~^ | ~} |~%|---|---|~{~*---|~}~%"
              (substitute #\Space #\- (symbol-name tag))
              '("Common Lisp" "Python" "C++" "Rust" "Go") *doc-backends*)
      (dolist (s *specs*)
        (when (member tag (getf s :tags))
          (format out "| ~(~a~) | ~a | ~{~a~^ | ~} |~%" (getf s :name)
                  (md-code (dsl-string (getf s :lisp)))
                  (mapcar (lambda (b) (spec-cell s b)) *doc-backends*)))))))

(defun write-supported-forms ()
  (with-open-file (s (supported-forms-path) :direction :output :if-exists :supersede
                     :external-format :utf-8)
    (write-string (supported-forms-text) s))
  (format t "~&wrote ~a~%" (supported-forms-path)))

(defun supported-forms-current-p ()
  (let* ((path (supported-forms-path))
         (current (and (probe-file path) (uiop:read-file-string path :external-format :utf-8))))
    (if (equal current (supported-forms-text))
        (progn (format t "~&SUPPORTED_FORMS.md is up to date~%") t)
        (progn (format t "~&SUPPORTED_FORMS.md is outdated; run ./run-tests.sh --docs~%") nil))))
