;;;; test-intrinsics.lisp --- tests of src/frontend/25-intrinsics.lisp

(in-package :polyglot.tests)

(def-suite :polyglot.unit.intrinsics :in :polyglot.unit)
(in-suite :polyglot.unit.intrinsics)

(define-intrinsic test-twice ((x :number)) (:type-of x)
                  (:test-backend "2 * $x" :includes ("<x>")))

(test registration-and-lookup
  (let ((i (find-intrinsic "test-twice")))
    (is (not (null i)))
    (is (equal '(("x" :number)) (intrinsic-params i)))
    (is (equal '(:type-of x) (intrinsic-ret i)))
    (is (equal "2 * $x" (getf (intrinsic-expansion i :test-backend nil) :template)))
    (is (equal '("<x>") (getf (intrinsic-expansion i :test-backend nil) :includes)))))

(test minimum-set-declared
  (dolist (name '("print-line" "format-string" "length" "string-byte-length"
                  "string-char-count" "push" "map-get" "map-set" "map-contains"
                  "map-keys-sorted" "string-concat" "sqrt" "abs" "min" "max"
                  "truncate" "floor" "mod" "rem"))
    (is (find-intrinsic name) "~a" name)))

(test optional-and-rest
  (let ((tr (find-intrinsic "truncate"))
        (fs (find-intrinsic "format-string")))
    (is (equal '(("b" :integer)) (intrinsic-optional tr)))
    (is (string= "args" (intrinsic-rest fs)))
    (check-intrinsic-arity tr nil 1)
    (check-intrinsic-arity tr nil 2)
    (signals dsl-error (check-intrinsic-arity tr nil 3))
    (check-intrinsic-arity fs nil 5)))

(test missing-expansion-is-unsupported
  (signals unsupported-construct
           (intrinsic-expansion (find-intrinsic "test-twice") :no-such-backend '(test-twice 1))))

(test templates
  (is (string= "std::sqrt(a + b)" (expand-template "std::sqrt($x)" '(("x" . "a + b")))))
  (is (string= "$1 x" (expand-template "$$1 $y" '(("y" . "x")))))
  (is (equal '(format t "~a~%" (f 1))
             (expand-sexp-template '(format t "~a~%" $x) '(("x" . (f 1)))))))
