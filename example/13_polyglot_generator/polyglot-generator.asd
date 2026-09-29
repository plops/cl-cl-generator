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
     (:file "02-conditions")
     (:file "03-names")
     (:module "ir"
      :serial t
      :components
      ((:file "10-node")
       (:file "11-types")
       (:file "12-expr")
       (:file "13-stmt")
       (:file "14-items")))
     (:module "frontend"
      :serial t
      :components
      ((:file "20-registry")
       (:file "21-expr")
       (:file "21-expr-forms")
       (:file "22-stmt")
       (:file "22-stmt-forms")
       (:file "23-declare"))))))
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
      ((:file "test-syntax")
       (:file "test-names")
       (:file "test-node")
       (:file "test-types")
       (:file "test-expr")
       (:file "test-stmt")
       (:file "test-declare"))))))
  :perform (asdf:test-op (o c)
             (uiop:symbol-call :fiveam :run! :polyglot)))
