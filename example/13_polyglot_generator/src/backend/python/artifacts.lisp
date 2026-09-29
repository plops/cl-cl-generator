;;;; artifacts.lisp --- Python backend: module files, imports, __all__, prelude

(in-package :polyglot)

(defun type-dependency-order (items)
  "ITEMS with interfaces and structs ordered so that every base (and interface)
comes before the types that use it; constants first, functions last."
  (let ((types (remove-if-not (lambda (i) (typep i '(or struct-item interface-item))) items))
        (visited '()) (order '()))
    (labels ((deps (i)
               (typecase i
                 (struct-item (append (alexandria:ensure-list (ir-base-item i)) (ir-implements-items i)))
                 (interface-item (ir-extends-items i))))
             (visit (i)
               (when (and (member i types) (not (member i visited)))
                 (push i visited)
                 (mapc #'visit (deps i))
                 (push i order))))
      (mapc #'visit types)
      (append (remove-if-not (lambda (i) (typep i 'const-item)) items)
              (reverse order)
              (remove-if-not (lambda (i) (typep i '(or function-item extern-item))) items)))))

(defparameter +python-std-modules+ '("abc" "collections.abc" "copy" "dataclasses" "math"))

(defun py-import-lines ()
  "import lines: plain imports, then from-imports of the standard library, then
project modules; everything sorted."
  (let ((plain '()) (from (make-hash-table :test 'equal)))
    (loop for key being the hash-keys of *imports*
          do (ecase (first key)
               (:prelude nil)
               (:import (pushnew (second key) plain :test #'string=))
               (:from (pushnew (third key) (gethash (second key) from) :test #'string=))))
    (flet ((from-line (m)
             (format nil "from ~a import ~{~a~^, ~}" m (sort (copy-list (gethash m from)) #'string<))))
      (let ((modules (sort (alexandria:hash-table-keys from) #'string<)))
        (let ((std (append (mapcar (lambda (m) (format nil "import ~a" m)) (sort plain #'string<))
                           (mapcar #'from-line (remove-if-not #'python-std-module-p modules))))
              (local (mapcar #'from-line (remove-if #'python-std-module-p modules))))
          ;; isort sections: standard library, blank line, first party
          (append std (when (and std local) (list "")) local))))))

(defun python-std-module-p (m)
  (member m +python-std-modules+ :test #'string=))

(defun py-module-body (module)
  (with-output-lines ()
    (dolist (item (type-dependency-order (ir-items module)))
      (unless (typep item 'extern-item)
        (emit-blank-line)
        (emit-blank-line)
        (emit-item *backend* item)))
    (let ((exports (loop for i in (ir-items module)
                         when (and (eq :public (ir-visibility i)) (not (typep i 'extern-item)))
                         collect (ir-target-name i))))
      (when (and exports (not (ir-entry-p module)))
        (emit-blank-line)
        (emit-blank-line)
        (emit-line "__all__ = [~{~s~^, ~}]" exports)))
    (when (and (ir-entry-p module) (module-entry-function module))
      (emit-blank-line)
      (emit-blank-line)
      (emit-line "if __name__ == \"__main__\":")
      (with-indent () (emit-line "~a()" (ir-target-name (module-entry-function module)))))))

(defun py-module-text (module)
  (let* ((*py-module* module)
         (*imports* (make-hash-table :test 'equal))
         (body (py-module-body module))
         (imports (py-import-lines)))
    (format nil "\"\"\"Module ~a.\"\"\"~%~@[~%~{~a~%~}~]~a" (ir-target-name module) imports body)))

(defmethod project-artifacts ((b python-backend) project)
  (let* ((*prelude-used* '())
         (files (loop for m in (ir-modules project)
                      collect (make-artifact :path (format nil "~a.py" (ir-target-name m))
                                             :kind :source :content (py-module-text m)))))
    (append files
            (when *prelude-used*
              (list (make-artifact :path "polyglot_rt.py" :kind :prelude
                                   :content (python-prelude-text)))))))
