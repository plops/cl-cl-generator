;;;; gen.lisp --- generate examples/01_shapes/source01/{cl,python,cpp,rust,go}/
;;;;
;;;;   sbcl --non-interactive --load examples/01_shapes/gen.lisp

(eval-when (:compile-toplevel :execute :load-toplevel)
  ;; Load the generator systems relative to this file
  (let ((here (make-pathname :name nil :type nil :defaults *load-pathname*)))
    (push (merge-pathnames "../../../../" here) asdf:*central-registry*) ; cl-cl-generator
    (push (merge-pathnames "../../" here) asdf:*central-registry*))     ; polyglot-generator
  (ql:quickload :polyglot-generator :silent t))

(in-package :polyglot-user)

(let* ((here (make-pathname :name nil :type nil :defaults *load-pathname*))
       (project-file (merge-pathnames "project.lisp" here))
       (results (write-project (polyglot::load-project-file project-file)
                               :out (merge-pathnames "source01/" here)
                               :source-file project-file)))
  (format t "~&~d files, ~d written~%" (length results) (count :written results :key #'cdr)))
