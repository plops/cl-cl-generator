(asdf:defsystem cockpit
  :version "0.1.0"
  :description "A bandwidth-optimized Linux system cockpit TUI, generated using cl-cl-generator."
  :depends-on ("alexandria" "uiop")
  :serial t
  :components ((:file "package")
               (:file "cockpit")))
