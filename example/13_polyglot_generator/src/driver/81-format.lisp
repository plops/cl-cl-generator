;;;; 81-format.lisp --- formatter registry (stdin -> stdout, portable via uiop)

(in-package :polyglot)

(defvar *formatters* (make-hash-table :test 'equal)
  "File extension -> command list; the text is passed on stdin.")

(defvar *warned-formatters* nil
  "Formatters already reported as missing in the current run.")

(defun register-formatter (extension command)
  (setf (gethash extension *formatters*) command))

(register-formatter "hpp" '("clang-format" "--style=llvm" "--assume-filename=x.hpp"))
(register-formatter "cpp" '("clang-format" "--style=llvm" "--assume-filename=x.cpp"))
(register-formatter "rs" '("rustfmt" "--edition" "2021"))
(register-formatter "py" '("ruff" "format" "--quiet" "--stdin-filename" "x.py" "-"))
(register-formatter "go" '("gofmt"))

(defun find-executable (name)
  "Absolute path of NAME in PATH, or NIL."
  (if (find #\/ name)
      (and (probe-file name) name)
      (loop for dir in (uiop:split-string (or (uiop:getenv "PATH") "") :separator ":")
            for candidate = (concatenate 'string (string-right-trim "/" dir) "/" name)
            when (and (plusp (length dir)) (probe-file candidate))
            return candidate)))

(defun warn-missing-formatter (name)
  (unless (member name *warned-formatters* :test #'string=)
    (push name *warned-formatters*)
    (dsl-warn nil "formatter ~a not found; files are written unformatted" name)))

(defun run-formatter (command text)
  "Formatted TEXT, or TEXT itself (with a warning) when the formatter fails."
  (multiple-value-bind (out err code)
      (uiop:run-program command :input (make-string-input-stream text)
                        :output :string :error-output :string
                        :ignore-error-status t :external-format :utf-8)
    (if (zerop code)
        out
        (progn (dsl-warn nil "~a failed (~d): ~a" (first command) code err)
               text))))

(defun format-artifact-text (artifact text)
  "Apply the formatter registered for the extension of ARTIFACT to TEXT."
  (let ((command (gethash (artifact-extension artifact) *formatters*)))
    (cond ((null command) text)
          ((not (find-executable (first command)))
           (warn-missing-formatter (first command))
           text)
          (t (run-formatter command text)))))
