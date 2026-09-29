;;;; test-backends.lisp --- intrinsic completeness and on-demand preludes

(in-package :polyglot.tests)

(def-suite :polyglot.unit.backends :in :polyglot.unit)
(in-suite :polyglot.unit.backends)

(defparameter *all-backends* '(:cl :python :cpp :rust :go))

(test every-intrinsic-has-every-expansion
  (loop for name being the hash-keys of *intrinsics* using (hash-value intrinsic)
        unless (search "test-" name)
        do (dolist (b *all-backends*)
             (is (gethash b (intrinsic-expansions intrinsic)) "~a has no expansion for ~(~a~)" name b))))

(defun artifacts-for (backend module-string)
  (let ((m (parse-module-form (read-dsl module-string))))
    (setf (ir-entry-p m) t)
    (generate-artifacts (find-backend backend)
                        (make-project-item :name "t" :modules (list m) :entry (ir-name m)))))

(defun prelude-artifact (artifacts)
  (find :prelude artifacts :key #'artifact-kind))

(test no-prelude-when-not-needed
  (dolist (b *all-backends*)
    (is (null (prelude-artifact (artifacts-for b "(defmodule m (defun main () (print-line \"hi\")))")))
        "~(~a~) wrote a prelude for hello world" b)))

(test prelude-when-needed
  (loop for (b op) in '((:python "rem") (:cpp "mod") (:rust "mod") (:go "mod") (:cl "string-byte-length"))
        do (let ((a (artifacts-for b (if (string= op "string-byte-length")
                                         "(defmodule m (defun main () (print-line (format-string \"{}\" (string-byte-length \"ä\")))))"
                                         (format nil "(defmodule m (defun main () (print-line (format-string \"{}\" (~a -7 2)))))" op)))))
             (is (prelude-artifact a) "~(~a~) needs a prelude for ~a" b op)))
  (is (search "floor_div" (artifact-content (prelude-artifact
                                             (artifacts-for :rust "(defmodule m (defun main () (print-line (format-string \"{}\" (floor -7 2)))))")))))
  (is (not (search "floor_div" (artifact-content (prelude-artifact
                                                  (artifacts-for :rust "(defmodule m (defun main () (print-line (format-string \"{}\" (mod -7 2)))))")))))))
