;;;; polyglot-generator.asd --- unified multi-target transpiler (example 13)

(asdf:defsystem "polyglot-generator"
  :version "0.1.0"
  :description "One S-expression DSL, idiomatic C++20, Python 3, Rust, Common Lisp and Go."
  :author "wol pumba <wolpumba@gmail.com>"
  :licence "GPL"
  :depends-on ("alexandria" "cl-ppcre" "trivia" "named-readtables" "cl-cl-generator")
  :serial t
  :components
  ((:module "src"
    :serial t
    :components
    ((:file "00-package")
     (:file "01-syntax")
     (:file "02-conditions"))))
  :in-order-to ((asdf:test-op (asdf:test-op "polyglot-generator/tests"))))

(asdf:defsystem "polyglot-generator/tests"
  :description "FiveAM unit and spec tests of the polyglot generator."
  :depends-on ("polyglot-generator" "fiveam")
  :serial t
  :components
  ((:module "tests"
    :serial t
    :components
    ((:file "00-suite")
     (:module "unit"
      :serial t
      :components
      ((:file "test-syntax"))))))
  :perform (asdf:test-op (o c)
             (uiop:symbol-call :fiveam :run! :polyglot)))
