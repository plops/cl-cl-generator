(asdf:defsystem :cl-py-generator-example
  :version "0.1.0"
  :description "Self-contained cl-py-generator example system."
  :depends-on ("alexandria" "jonathan" "external-program")
  :serial t
  :components ((:file "package")
               (:file "py")))
