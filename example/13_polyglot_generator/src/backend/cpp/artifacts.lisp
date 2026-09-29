;;;; artifacts.lisp --- C++ backend: header and implementation text,
;;;; CMakeLists.txt, polyglot_rt.hpp

(in-package :polyglot)

(defun cpp-header-body (module)
  (let ((types (module-types module :public)))
    (with-output-lines (:unit "  ")
      (cpp-forward-declarations types)
      (dolist (i (module-consts module :public)) (cpp-const-definition i :header t))
      (dolist (i types) (emit-blank-line) (cpp-type-declaration i))
      (emit-blank-line)
      (dolist (f (remove (module-entry-function module) (module-functions module :public)))
        (emit-line (cpp-function-prototype f))))))

(defun cpp-header-text (module)
  (let* ((*cpp-module* module)
         (*imports* (make-hash-table :test 'equal))
         (body (cpp-header-body module))
         (includes (cpp-include-lines))
         (forwards (cpp-foreign-forward-lines))
         (ns (ir-target-name module)))
    (if (ir-entry-p module)
        (format nil "#pragma once~%~%~{~a~%~}~%~{~a~%~%~}~a" includes forwards body)
        (format nil "#pragma once~%~%~{~a~%~}~%~{~a~%~%~}namespace ~a {~%~%~a~%}  // namespace ~a~%"
                includes forwards ns body ns))))

(defun cpp-method-definitions (item)
  (dolist (m (ir-methods item))
    (unless (function-flag-p m :abstract)
      (emit-blank-line)
      (cpp-function-definition m :owner item))))

(defun cpp-private-block (thunk)
  "Run THUNK inside namespace { ... } unless it emits nothing."
  (let ((text (with-output-lines (:unit "  ") (funcall thunk))))
    (when (plusp (length text))
      (emit-blank-line)
      (emit-line "namespace {")
      (emit-line "~a" (string-right-trim '(#\Newline) text))
      (emit-line "}  // namespace"))))

(defun cpp-impl-body (module)
  (let ((ptypes (module-types module :private))
        (pfuns (remove (module-entry-function module) (module-functions module :private))))
    (with-output-lines (:unit "  ")
      (cpp-private-block
       (lambda ()
         (cpp-forward-declarations ptypes)
         (dolist (i (module-consts module :private)) (cpp-const-definition i))
         (dolist (i ptypes) (emit-blank-line) (cpp-type-declaration i))
         (when pfuns (emit-blank-line))
         (dolist (f pfuns) (emit-line (cpp-function-prototype f)))))
      (dolist (i (module-types module :public)) (cpp-method-definitions i))
      (dolist (f (remove (module-entry-function module) (module-functions module :public)))
        (emit-blank-line) (cpp-function-definition f))
      (cpp-private-block
       (lambda ()
         (dolist (i ptypes) (cpp-method-definitions i))
         (dolist (f pfuns) (emit-blank-line) (cpp-function-definition f)))))))

(defun cpp-has-header-p (module)
  (or (not (ir-entry-p module))
      (some (lambda (i) (eq :public (ir-visibility i))) (ir-items module))))

(defun cpp-impl-text (module)
  (let* ((*cpp-module* module)
         (*imports* (make-hash-table :test 'equal))
         (entry (and (ir-entry-p module) (module-entry-function module)))
         (body (cpp-impl-body module))
         (main (when entry (with-output-lines (:unit "  ") (cpp-main-definition entry))))
         (includes (cpp-include-lines :own-header (when (cpp-has-header-p module) (ir-target-name module))))
         (ns (ir-target-name module)))
    (format nil "~{~a~%~}~%~a~@[~%~a~]"
            includes
            (if (ir-entry-p module)
                body
                (format nil "namespace ~a {~%~a~%}  // namespace ~a~%" ns body ns))
            main)))

(defun cpp-cmake-text (project sources)
  (let ((name (to-snake (ir-name project))))
    (format nil "cmake_minimum_required(VERSION 3.20)~%project(~a LANGUAGES CXX)~%~%~
                 set(CMAKE_CXX_STANDARD 20)~%set(CMAKE_CXX_STANDARD_REQUIRED ON)~%~%~
                 add_executable(~a~{ ~a~})~%target_compile_options(~a PRIVATE -Wall -Wextra)~%"
            name name sources name)))

(defmethod project-artifacts ((b cpp-backend) project)
  (let* ((*prelude-used* '())
         (files (loop for m in (ir-modules project)
                      append (append (when (cpp-has-header-p m)
                                       (list (make-artifact :path (format nil "~a.hpp" (ir-target-name m))
                                                            :kind :header :content (cpp-header-text m))))
                                     (list (make-artifact :path (format nil "~a.cpp" (ir-target-name m))
                                                          :kind :source :content (cpp-impl-text m))))))
         (sources (loop for f in files when (eq :source (artifact-kind f)) collect (artifact-path f))))
    (append files
            (when *prelude-used*
              (list (make-artifact :path "polyglot_rt.hpp" :kind :prelude :content (cpp-prelude-text))))
            (list (make-artifact :path "CMakeLists.txt" :kind :build
                                 :content (cpp-cmake-text project sources))))))
