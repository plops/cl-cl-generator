;;;; artifacts.lisp --- CL backend: package files, runtime prelude, .asd

(in-package :polyglot)

(defun uninterned (sym-or-string)
  (make-symbol (if (symbolp sym-or-string) (symbol-name sym-or-string) sym-or-string)))

(defun cl-defpackage (module)
  (let ((imports (sort (alexandria:hash-table-keys *cl-imports*) #'string<)))
    `(defpackage ,(intern (string-upcase (cl-package-name module)) :keyword)
       (:use :cl)
       ,@(let ((shadows (sort (copy-list (gethash module *cl-shadows*)) #'string<)))
           (when shadows `((:shadow ,@(mapcar #'uninterned shadows)))))
       ,@(loop for pkg in imports
               for syms = (sort (copy-list (gethash pkg *cl-imports*)) #'string< :key #'symbol-name)
               for shadowing = (remove-if-not (lambda (s) (cl-external-p (symbol-name s))) syms)
               for plain = (remove-if (lambda (s) (cl-external-p (symbol-name s))) syms)
               for key = (intern (string-upcase pkg) :keyword)
               when plain collect `(:import-from ,key ,@(mapcar #'uninterned plain))
               when shadowing collect `(:shadowing-import-from ,key ,@(mapcar #'uninterned shadowing)))
       ,@(let ((exports (cl-exported-symbols module)))
           (when exports `((:export ,@(mapcar #'uninterned exports))))))))

(defun print-cl-forms (forms package)
  (let ((*package* package)
        (*read-default-float-format* 'single-float))
    (cl-cl-generator:emit-cl `(cl-cl-generator:toplevel ,@forms))))

(defun cl-module-text (module)
  (let* ((*cl-module* module)
         (*cl-imports* (make-hash-table :test 'equal))
         (*cl-generics* '())
         (items (loop for item in (ir-items module) append (cl-item-forms item)))
         (head (list (cl-defpackage module)
                     `(in-package ,(intern (string-upcase (cl-package-name module)) :keyword)))))
    (format nil "~a~%" (print-cl-forms (append head items) (scratch-package module)))))

(defun project-uses-clone-p (project)
  (let ((found nil))
    (walk-nodes (lambda (n) (when (and (typep n 'own-expr) (eq :clone (ir-kind n))
                                       (not (copy-type-p (ir-ty n))) (not (eq :string (ir-ty n))))
                              (setf found t)))
                project)
    found))

(defun module-order (project)
  "Modules sorted so that every module comes after the modules it imports."
  (let ((done '()) (visiting '()))
    (labels ((visit (m)
               (when (member m visiting)
                 (dsl-error (ir-source m) "cyclic module imports involving ~a" (ir-name m)))
               (unless (member m done)
                 (push m visiting)
                 (dolist (i (ir-imports m)) (visit (find-module i project)))
                 (pop visiting)
                 (push m done))))
      (mapc #'visit (ir-modules project))
      (nreverse done))))

(defun cl-asd-text (project modules)
  (format nil "(asdf:defsystem ~s~%  :serial t~%  :components (~{~a~^~%               ~}))~%"
          (ir-name project)
          (append (when *cl-rt-used* '("(:file \"polyglot-rt\")"))
                  (loop for m in modules collect (format nil "(:file ~s)" (ir-target-name m))))))

(defmethod project-artifacts ((b cl-backend) project)
  (with-cl-scratch ()
    (let* ((*cl-clone-used* (project-uses-clone-p project))
           (modules (module-order project))
           (files (loop for m in modules
                        collect (make-artifact :path (format nil "~a.lisp" (ir-target-name m))
                                               :kind :source :content (cl-module-text m))))
           (rt (when *cl-rt-used*
                 (let ((*cl-module* (first modules)))
                   (make-artifact :path "polyglot-rt.lisp" :kind :prelude
                                  :content (cl-prelude-text))))))
      (append (when rt (list rt)) files
              (list (make-artifact :path (format nil "~a.asd" (ir-name project)) :kind :build
                                   :content (cl-asd-text project modules)))))))
