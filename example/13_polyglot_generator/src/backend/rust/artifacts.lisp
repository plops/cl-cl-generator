;;;; artifacts.lisp --- Rust backend: crate layout (src/main.rs, modules,
;;;; polyglot_rt.rs, Cargo.toml)

(in-package :polyglot)

(defun rs-use-lines ()
  (let ((std '()) (crate (make-hash-table :test 'equal)))
    (loop for key being the hash-keys of *imports*
          do (case (first key)
               (:std (pushnew (second key) std :test #'string=))
               (:use (pushnew (third key) (gethash (second key) crate) :test #'string=))))
    (append (mapcar (lambda (s) (format nil "use ~a;" s)) (sort std #'string<))
            (loop for m in (sort (alexandria:hash-table-keys crate) #'string<)
                  for names = (sort (copy-list (gethash m crate)) #'string<)
                  collect (if (cdr names)
                              (format nil "use crate::~a::{~{~a~^, ~}};" m names)
                              (format nil "use crate::~a::~a;" m (first names)))))))

(defun rs-module-body (module)
  (with-output-lines ()
    (loop for item in (ir-items module)
          unless (typep item 'extern-item)
          do (emit-blank-line)
          (emit-item *backend* item))))

(defun rs-module-text (module mods)
  "Text of MODULE; MODS are the mod declarations of main.rs."
  (let* ((*rs-module* module)
         (*imports* (make-hash-table :test 'equal))
         (*rs-loop-modes* (make-hash-table))
         (*derivable* (make-hash-table))
         (body (rs-module-body module))
         (uses (rs-use-lines)))
    (format nil "~@[//! ~a~%~%~]~{mod ~a;~%~}~:[~;~%~]~{~a~%~}~:[~;~%~]~a"
            (unless (ir-entry-p module) (format nil "Module ~a." (ir-target-name module)))
            mods (and mods uses) uses uses body)))

(defun rs-cargo-text (project)
  (format nil "[package]~%name = ~s~%version = \"0.1.0\"~%edition = \"2021\"~%~%[dependencies]~%"
          (to-snake (ir-name project))))

(defmethod project-artifacts ((b rust-backend) project)
  (let* ((*prelude-used* '())
         (others (remove-if #'ir-entry-p (ir-modules project)))
         (texts (loop for m in others
                      collect (make-artifact :path (format nil "src/~a.rs" (ir-target-name m))
                                             :kind :source :content (rs-module-text m nil))))
         (entry (find-if #'ir-entry-p (ir-modules project)))
         (mods (sort (append (mapcar #'ir-target-name others)
                             ;; the prelude is known only after all modules are emitted
                             '())
                     #'string<))
         (main-text (rs-module-text entry nil))
         (mods (if *prelude-used* (sort (cons "polyglot_rt" mods) #'string<) mods)))
    (append (list (make-artifact :path "src/main.rs" :kind :source
                                 :content (format nil "~{mod ~a;~%~}~:[~;~%~]~a" mods mods main-text)))
            texts
            (when *prelude-used*
              (list (make-artifact :path "src/polyglot_rt.rs" :kind :prelude :content (rust-prelude-text))))
            (list (make-artifact :path "Cargo.toml" :kind :build :content (rs-cargo-text project))))))
