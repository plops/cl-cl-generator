(asdf:defsystem cl-cl-generator
  :version "0.1.0"
  :description "An elegant, pretty-printer-based S-expression code generator for Common Lisp."
  :maintainer "Martin Kielhorn <kielhorn.martin@gmail.com>"
  :author "Martin Kielhorn <kielhorn.martin@gmail.com>"
  :licence "GPL"
  :depends-on ("alexandria")
  :serial t
  :components ((:file "package")
               (:file "cl")))
