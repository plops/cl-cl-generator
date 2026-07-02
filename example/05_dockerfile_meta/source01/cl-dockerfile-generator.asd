(asdf:defsystem :cl-dockerfile-generator
  :description "S-expression to Dockerfile transpiler"
  :version "0.1.0"
  :author "Antigravity Pair Programmer"
  :license "MIT"
  :components ((:file "dock")))

(asdf:defsystem :cl-dockerfile-generator/tests
  :description "Unit tests for cl-dockerfile-generator"
  :depends-on (:cl-dockerfile-generator)
  :components ((:file "run_tests")))
