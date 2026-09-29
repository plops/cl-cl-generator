;;;; artifacts.lisp --- Go backend: go.mod, package per module, prelude package

(in-package :polyglot)

(defun go-module-path () (to-snake (ir-name *go-project*)))

(defun go-import-lines ()
  (let ((std '()) (pkgs '()))
    (loop for key being the hash-keys of *imports*
          do (case (first key)
               (:std (pushnew (second key) std :test #'string=))
               (:pkg (pushnew (second key) pkgs :test #'string=))
               (:prelude (pushnew "polyglotrt" pkgs :test #'string=))))
    (append (mapcar (lambda (s) (format nil "~s" s)) (sort std #'string<))
            (when (and std pkgs) (list ""))
            (mapcar (lambda (p) (format nil "\"~a/~a\"" (go-module-path) p)) (sort pkgs #'string<)))))

(defun go-module-text (module)
  (let* ((*go-module* module)
         (*imports* (make-hash-table :test 'equal))
         (body (with-output-lines (:unit (string #\Tab))
                 (dolist (item (ir-items module))
                   (unless (typep item 'extern-item)
                     (emit-blank-line)
                     (emit-item *backend* item)))))
         (imports (go-import-lines)))
    (format nil "~:[// Package ~a is generated from the DSL module of the same name.~%package ~:*~a~;package main~*~]~%~
                 ~@[~%import (~{~%	~a~}~%)~%~]~a"
            (ir-entry-p module) (ir-target-name module) imports body)))

(defmethod project-artifacts ((b go-backend) project)
  (let* ((*go-project* project)
         (*prelude-used* '())
         (files (loop for m in (ir-modules project)
                      collect (make-artifact :path (if (ir-entry-p m)
                                                       "main.go"
                                                       (format nil "~a/~a.go" (ir-target-name m) (ir-target-name m)))
                                             :kind :source :content (go-module-text m)))))
    (append files
            (when *prelude-used*
              (list (make-artifact :path "polyglotrt/polyglotrt.go" :kind :prelude :content (go-prelude-text))))
            (list (make-artifact :path "go.mod" :kind :build
                                 :content (format nil "module ~a~%~%go 1.23~%" (go-module-path)))))))
