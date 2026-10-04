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
(defvar *lib-name*)
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

(defun pg-mod-line-p (line)
  (and (> (length line) 4) (string= line "mod " :end1 4)))

(defun pg-split-bin (rust-dir)
  "Rewrite src/main.rs into a thin bin that uses the lib (like source7):
drop the `mod` lines (plus the separator blank line) and rewrite every
`crate::` to *LIB-NAME*::. Returns the :written/:unchanged status.
Constraint: no `crate::` inside raw string literals of the entry module."
  (let* ((path (merge-pathnames "src/main.rs" rust-dir))
         (text (or (pg-read-file-or-nil path)
                   (error "src/main.rs missing: ~a" path)))
         (lines (uiop:split-string text :separator '(#\Newline)))
         (dropped-mods nil)
         (kept (loop for l in lines
                     if (pg-mod-line-p l)
                     do (setf dropped-mods t)
                     else collect l))
         ;; drop the blank line that separated mods from the rest
         (kept (if (and dropped-mods
                        (member "" kept :test #'string=))
                   (remove "" kept :test #'string= :count 1)
                   kept))
         ;; provenance note after the header comment block
         (kept (let ((pos (position-if
                           (lambda (l)
                             (not (and (> (length l) 2)
                                       (string= l "//" :end1 2))))
                           kept)))
                 (if pos
                     (append (subseq kept 0 pos)
                             (list "// Thin bin: gen.lisp dropped the mod lines and"
                                   "// rewrote the paths to the lib (bin split).")
                             (nthcdr pos kept))
                     kept)))
         (rewritten (mapcar (lambda (l)
                              (cl-ppcre:regex-replace-all "crate::" l
                                                          (concatenate 'string
                                                                       *lib-name*
                                                                       "::")))
                            kept))
         (out (format nil "~{~a~^~%~}" rewritten)))
    ;; split-string drops the trailing newline; restore exactly one
    (pg-write-if-changed path (concatenate 'string
                                           (string-right-trim '(#\Newline) out)
                                           (string #\Newline)))))

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
           ;; exactly one blank line between, one newline at end
           (text (concatenate 'string
                              (string-right-trim '(#\Newline) base)
                              (format nil "~2%~a~%"
                                      (string-right-trim '(#\Newline)
                                                         (cdr a))))))
      (push (cons (namestring path) (pg-write-if-changed path text)) extra)))
  ;; extra files (examples/, tests/)
  (dolist (e *extra-files*)
    (let ((path (merge-pathnames (car e) rust-dir)))
      (push (cons (namestring path)
                  (pg-write-if-changed path (cdr e)))
            extra)))
  ;; thin bin: main.rs uses the lib instead of compiling the modules
  (when *append-to*
    (when (assoc "src/main.rs" *append-to* :test #'string=)
      (error "*append-to* must not target src/main.rs (bin split owns it)")))
  (push (cons (namestring (merge-pathnames "src/main.rs" rust-dir))
              (pg-split-bin rust-dir))
        extra)
  ;; Note: Cargo.toml (replaced by *cargo-toml*), *append-to* targets and
  ;; src/main.rs (bin split) are always reported written; steady state =
  ;; targets (base differs from base+append by construction) are always
  ;; reported written; steady state = only those rewritten.
  (let ((all (append results (nreverse extra))))
    (dolist (r all)
      (format t "~&~(~a~)  ~a~%" (cdr r) (car r)))
    (format t "~&~d files, ~d written, ~d unchanged~%"
            (length all)
            (count :written all :key #'cdr)
            (count :unchanged all :key #'cdr))
    (let* ((noisy (list* "Cargo.toml" "src/main.rs"
                        (mapcar #'car *append-to*)))
           (other (remove-if (lambda (r)
                               (or (eq (cdr r) :unchanged)
                                   (some (lambda (n) (search n (car r)))
                                         noisy)))
                             all)))
      (format t "~&stable: ~:[NO~;YES~]~%" (null other)))))
