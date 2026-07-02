(asdf/parse-defsystem:defsystem cockpit-tui
  :version
  "0.1.0"
  :description
  "An interactive bandwidth-optimized Linux system cockpit TUI using cl-tuition."
  :depends-on
  ("alexandria" "uiop" "tuition")
  :serial
  t
  :components
  ((:file "package") (:file "cockpit"))
  :in-order-to
  ((asdf/lisp-action:test-op (asdf/lisp-action:test-op "cockpit-tui/tests"))))

(asdf/parse-defsystem:defsystem cockpit-tui/tests
  :depends-on
  ("cockpit-tui" "rove")
  :components
  ((:file "tests"))
  :perform
  (asdf/lisp-action:test-op (op c) (uiop/package:symbol-call :rove :run c)))