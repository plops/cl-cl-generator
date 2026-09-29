;;;; test-cpp-split.lisp --- C++ header/implementation split and include analysis

(in-package :polyglot.tests)

(def-suite :polyglot.unit.cpp-split :in :polyglot.unit)
(in-suite :polyglot.unit.cpp-split)

(defun cpp-artifacts (&rest module-strings)
  (let* ((modules (mapcar (lambda (s) (parse-module-form (read-dsl s))) module-strings))
         (p (make-project-item :name "t" :modules modules :entry (ir-name (car (last modules))))))
    (setf (ir-entry-p (car (last modules))) t)
    (generate-artifacts (find-backend :cpp) p)))

(defun artifact-text (artifacts path)
  (normalize-ws (artifact-content (find path artifacts :key #'artifact-path :test #'string=))))

(defparameter *split-lib* "(defmodule lib (:export pt norm) (defstruct pt (x :f64))
  (defun sq (v) (declare (type :f64 v) (values :f64)) (* v v))
  (defun norm (p) (declare (type pt p) (values :f64)) (sq (dot p x))))")

(test value-use-includes-header
  (let ((a (cpp-artifacts *split-lib*
                          "(defmodule seg (:export seg) (:import lib) (defstruct seg (a pt)))"
                          "(defmodule main (:import seg) (defun main () (print-line \"x\")))")))
    (is (search "#include \"lib.hpp\"" (artifact-text a "seg.hpp")))
    (is (search "struct Seg { lib::Pt a{}; };" (artifact-text a "seg.hpp")))))

(test signature-use-forward-declares
  (let ((a (cpp-artifacts *split-lib*
                          "(defmodule rep (:export show) (:import lib)
                             (defun show (p) (declare (type (box pt) p) (values :f64)) (norm p)))"
                          "(defmodule main (:import rep) (defun main () (print-line \"x\")))")))
    (is (search "namespace lib { struct Pt; } // namespace lib" (artifact-text a "rep.hpp")))
    (is (not (search "#include \"lib.hpp\"" (artifact-text a "rep.hpp"))))
    (is (search "#include \"rep.hpp\"" (artifact-text a "rep.cpp")))
    (is (search "#include \"lib.hpp\"" (artifact-text a "rep.cpp")))
    (is (search "return lib::norm(*p);" (artifact-text a "rep.cpp")))))

(test private-items-in-anonymous-namespace
  (let* ((a (cpp-artifacts *split-lib* "(defmodule main (:import lib) (defun main () (print-line \"x\")))"))
         (cpp (artifact-text a "lib.cpp")))
    (is (search "namespace { double sq(double v); } // namespace" cpp))
    (is (search "double norm(const Pt& p) { return sq(p.x); }" cpp))
    (is (not (search "sq" (artifact-text a "lib.hpp"))))
    (is (not (find "main.hpp" a :key #'artifact-path :test #'string=)))
    (is (search "int main() {" (artifact-text a "main.cpp")))))

(test type-order-and-cycles
  (let ((a (cpp-artifacts "(defmodule m (:export a b) (defstruct a (x b)) (defstruct b (y :i64)))"
                          "(defmodule main (defun main () (print-line \"x\")))")))
    (let ((h (artifact-text a "m.hpp")))
      (is (< (search "struct B" h) (search "struct A" h)))))
  (signals dsl-error
           (cpp-artifacts "(defmodule m (:export a b) (defstruct a (x b)) (defstruct b (y a)))"
                          "(defmodule main (defun main () (print-line \"x\")))"))
  (let ((a (cpp-artifacts "(defmodule m (:export node) (defstruct node (next (optional (box node))) (v :i64)))"
                          "(defmodule main (defun main () (print-line \"x\")))")))
    (is (search "std::optional<std::unique_ptr<Node>> next{};" (artifact-text a "m.hpp")))))
