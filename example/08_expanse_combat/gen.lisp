;;;; gen.lisp — Orchestrator for 08_expanse_combat Code Generator

(in-package :cl-user)

;; Load sub-templates
(load "01_package.lisp")
(load "02_physics_template.lisp")
(load "03_mpc_template.lisp")
(load "04_gui_template.lisp")

(in-package :cl-cl-generator/example-expanse-gen)

(defun run-generator ()
  (ensure-directories-exist *output-dir*)

  ;; 1. Emit package.lisp
  (write-source "package"
    `(toplevel
       ,@(make-header-comments)
       (defpackage :expanse-combat
         (:use :cl)
         (:export #:run-game)))
    *output-dir*)

  ;; 2. Emit expanse-combat.asd
  (let* ((asd-path (merge-pathnames "expanse-combat.asd" *output-dir*))
         (asd-code
           `(toplevel
              ,@(make-header-comments)
              (asdf:defsystem :expanse-combat
                :version "0.1.0"
                :description "Expanse-style 2D orbital tactical space combat simulation"
                :depends-on (:pure-x11-gen :hpipm)
                :serial t
                :components ((:file "package")
                             (:file "physics")
                             (:file "mpc")
                             (:file "game"))))))
    (ensure-directories-exist asd-path)
    (with-open-file (stream asd-path
                            :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create)
      (write-sequence (emit-cl asd-code) stream)))

  ;; 3. Emit physics.lisp
  (write-source "physics" *physics-template-code* *output-dir*)

  ;; 4. Emit mpc.lisp
  (write-source "mpc" *mpc-template-code* *output-dir*)

  ;; 5. Emit game.lisp
  (write-source "game" *gui-template-code* *output-dir*)

  (format t "Successfully generated Expanse Space Combat codebase in ~a~%" *output-dir*))

;; Run the generator when loaded
(run-generator)
