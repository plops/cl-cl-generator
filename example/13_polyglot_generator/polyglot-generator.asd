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
       (:file "23-declare")
       (:file "24-items")
       (:file "24-modules")
       (:file "25-intrinsics")))
     (:module "passes"
      :serial t
      :components
      ((:file "30-pipeline")
       (:file "31-signatures")
       (:file "31-desugar")
       (:file "32-resolve-env")
       (:file "32-resolve-types")
       (:file "32-resolve-expr")
       (:file "32-resolve-expr2")
       (:file "32-resolve-stmt")
       (:file "32-resolve")
       (:file "33-check")
       (:file "33-check-walk")
       (:file "34-mutability")
       (:file "35-vtable")
       (:file "37-rename")
       (:file "37-rename-locals")
       (:file "38-lower")
       (:file "38-lower-stmt")
       (:file "39-order-args")
       (:file "40-capability")))
     (:module "printer"
      :serial t
      :components
      ((:file "50-writer")
       (:file "51-precedence")
       (:file "52-literals")))
     (:module "driver"
      :serial t
      :components
      ((:file "80-artifacts")
       (:file "81-format")
       (:file "82-write")))
     (:module "backend"
      :serial t
      :components
      ((:file "60-protocol")
       (:module "cl"
        :serial t
        :components
        ((:file "config")
         (:file "symbols")
         (:file "expr")
         (:file "stmt")
         (:file "items")
         (:file "intrinsics")
         (:file "artifacts")))
       (:file "61-text")
       (:module "python"
        :serial t
        :components
        ((:file "config")
         (:file "expr")
         (:file "intrinsics")
         (:file "stmt")
         (:file "items")
         (:file "artifacts")))
       (:module "cpp"
        :serial t
        :components
        ((:file "config")
         (:file "types")
         (:file "expr")
         (:file "intrinsics")
         (:file "stmt")
         (:file "items")
         (:file "split")
         (:file "artifacts"))))))))
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
       (:file "test-declare")
       (:file "test-items")
       (:file "test-macros")
       (:file "test-intrinsics")
       (:file "test-desugar")
       (:file "test-resolve")
       (:file "test-check")
       (:file "test-mutability")
       (:file "test-vtable")
       (:file "test-rename")
       (:file "test-lower")
       (:file "test-printer")
       (:file "test-driver")
       (:file "test-cpp-split")))
     (:module "spec"
      :serial t
      :components
      ((:file "spec")
       (:file "table-core"))))))
  :perform (asdf:test-op (o c)
             (uiop:symbol-call :fiveam :run! :polyglot)))