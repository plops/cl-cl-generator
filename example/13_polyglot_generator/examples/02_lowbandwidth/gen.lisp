;;;; gen.lisp --- generate examples/02_lowbandwidth/source01/rust/
;;;;
;;;;   sbcl --non-interactive --load examples/02_lowbandwidth/gen.lisp
;;;; (run from example/13_polyglot_generator/)
;;;;
;;;; Steps: write-project (rust only), then assemble the crate:
;;;; replace Cargo.toml, build src/lib.rs from the generated modules,
;;;; append *append-to* entries, write *extra-files*. Every write is
;;;; write-if-changed, so a second run reports 0 written.

(eval-when (:compile-toplevel :execute :load-toplevel)
  ;; Load the generator systems relative to this file
  (let ((here (make-pathname :name nil :type nil :defaults *load-pathname*)))
    (push (merge-pathnames "../../../../" here) asdf:*central-registry*) ; cl-cl-generator
    (push (merge-pathnames "../../" here) asdf:*central-registry*))     ; polyglot-generator
  (ql:quickload :polyglot-generator :silent t))

(in-package :polyglot-user)

;;; Provided by project.lisp at load time (defparameter there assigns).
(defvar *cargo-toml*)
(defvar *append-to*)
(defvar *extra-files*)

(defun pg-read-file-or-nil (path)
  (when (probe-file path)
    (with-open-file (s path :direction :input :external-format :utf-8)
      (let ((seq (make-string (file-length s))))
        (read-sequence seq s)
        seq))))

(defun pg-write-if-changed (path text)
  "Write TEXT to PATH unless identical. Returns :written/:unchanged."
  (if (equal text (pg-read-file-or-nil path))
      :unchanged
      (progn
        (ensure-directories-exist path)
        (with-open-file (s path :direction :output :if-exists :supersede
                            :if-does-not-exist :create :external-format :utf-8)
          (write-string text s))
        :written)))

(defun pg-lib-rs (rust-dir)
  "lib.rs content: one pub mod per generated module file."
  (let ((mods (sort (loop for p in (uiop:directory-files rust-dir "src/*.rs")
                          for name = (pathname-name p)
                          unless (member name '("main" "lib") :test #'string=)
                          collect name)
                    #'string<)))
    (with-output-to-string (s)
      (write-line "// Assembled by gen.lisp from project.lisp. DO NOT EDIT." s)
      (write-line "//! Library crate: re-exports the generated modules so that" s)
      (write-line "//! examples/ and tests/ can use them (the binary stays as generated)." s)
      (dolist (m mods)
        (format s "~:[pub mod ~;mod ~]~a;~%" (string= m "polyglot_rt") m)))))

(let* ((here (make-pathname :name nil :type nil :defaults *load-pathname*))
       (project-file (merge-pathnames "project.lisp" here))
       (out (merge-pathnames "source01/" here))
       (rust-dir (merge-pathnames "rust/" out))
       (results (write-project (polyglot::load-project-file project-file)
                               :targets '(:rust)
                               :out out
                               :source-file project-file))
       (extra (list (cons (namestring (merge-pathnames "Cargo.toml" rust-dir))
                          (pg-write-if-changed (merge-pathnames "Cargo.toml" rust-dir)
                                               *cargo-toml*))
                    (cons (namestring (merge-pathnames "src/lib.rs" rust-dir))
                          (pg-write-if-changed (merge-pathnames "src/lib.rs" rust-dir)
                                               (pg-lib-rs rust-dir))))))
  ;; appends (enums, Drop impls) onto generated module files
  (dolist (a *append-to*)
    (let* ((path (merge-pathnames (car a) rust-dir))
           (base (or (pg-read-file-or-nil path)
                     (error "append target missing: ~a" path)))
           (text (concatenate 'string
                              (string-right-trim '(#\Newline) base)
                              (format nil "~2%~a~%" (cdr a)))))
      (push (cons (namestring path) (pg-write-if-changed path text)) extra)))
  ;; extra files (examples/, tests/)
  (dolist (e *extra-files*)
    (let ((path (merge-pathnames (car e) rust-dir)))
      (push (cons (namestring path)
                  (pg-write-if-changed path (cdr e)))
            extra)))
  ;; Note: Cargo.toml is always reported written (generated variant is
  ;; replaced by *cargo-toml*); steady state = only Cargo.toml rewritten.
  (let ((all (append results (nreverse extra))))
    (dolist (r all)
      (format t "~&~(~a~)  ~a~%" (cdr r) (car r)))
    (format t "~&~d files, ~d written, ~d unchanged~%"
            (length all)
            (count :written all :key #'cdr)
            (count :unchanged all :key #'cdr))
    (let ((other (remove-if (lambda (r)
                              (or (eq (cdr r) :unchanged)
                                  (search "Cargo.toml" (car r))))
                            all)))
      (format t "~&stable: ~:[NO~;YES~]~%" (null other)))))
