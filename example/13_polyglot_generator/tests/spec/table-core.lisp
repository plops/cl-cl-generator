;;;; table-core.lisp --- spec entries: literals, operators, calls, statements

(in-package :polyglot.tests)

(define-spec add-mul
  :tags (:operators) :doc "Precedence: only the necessary parentheses."
  :params ((a :i64) (b :i64) (c :i64)) :ret :i64
  :lisp (+ a (* b c))
  :expect (:cl "(+ a (* b c))"
               :python "return a + b * c"
               :cpp "return a + b * c;"
               :rust "fn spec_f(a: i64, b: i64, c: i64) -> i64 { a + b * c }"))

(define-spec sub-right
  :tags (:operators) :doc "Left associativity keeps the right operand grouped."
  :params ((a :i64) (b :i64) (c :i64)) :ret :i64
  :lisp (- a (- b c))
  :expect (:cl "(- a (- b c))"
               :python "a - (b - c)"
               :cpp "a - (b - c)"
               :rust "a - (b - c)"))

(define-spec logic
  :tags (:operators) :doc "and/or/not are logical (CL semantics)."
  :params ((a :bool) (b :bool) (c :bool)) :ret :bool
  :lisp (or (and a b) (not c))
  :expect (:cl "(or (and a b) (not c))"
               :python "a and b or not c"
               :cpp "return (a && b) || !c;"
               :rust "a && b || !c"))

(define-spec bitwise
  :tags (:operators) :doc "logand/logior/logxor/lognot/shl/shr are bitwise."
  :params ((a :i64) (b :i64)) :ret :i64
  :lisp (logior (logand a b) (shl a 2))
  :expect (:cl "(logior (logand a b) (ash a 2))"
               :python "a & b | a << 2"
               :cpp "(a & b) | (a << 2)"
               :rust "a & b | a << 2"))

(define-spec not-equal
  :tags (:operators) :doc "/= means not equal (not division assignment)."
  :params ((a :i64) (b :i64)) :ret :bool
  :lisp (/= a b)
  :expect (:cl "(/= a b)"
               :python "a != b"
               :cpp "a != b"
               :rust "a != b"))

(define-spec string-equal
  :tags (:operators) :doc "= on strings compares contents."
  :params ((a :string) (b :string)) :ret :bool
  :lisp (= a b)
  :expect (:cl "(string= a b)"
               :python "a == b"
               :cpp "bool spec_f(const std::string& a, const std::string& b)"
               :rust "fn spec_f(a: &str, b: &str) -> bool { a == b }"))

(define-spec float-division
  :tags (:operators) :doc "/ only for floats; int literals become floats."
  :params ((x :f64)) :ret :f64
  :lisp (/ x 2)
  :expect (:cl "(/ x 2.0d0)"
               :python "x / 2.0"
               :cpp "x / 2.0"
               :rust "x / 2.0"))

(define-spec int-division
  :tags (:intrinsics) :doc "truncate/floor/mod/rem with CL semantics."
  :params ((a :i64) (b :i64)) :ret :i64
  :lisp (+ (truncate a b) (floor a b) (mod a b) (rem a b))
  :expect (:cl "(+ (values (truncate a b)) (values (floor a b)) (mod a b) (rem a b))"
               :python "trunc_div(a, b) + a // b + a % b + rem(a, b)"
               :cpp "a / b + polyglot_rt::floor_div(a, b) + polyglot_rt::mod(a, b) + a % b"
               :rust "a / b + polyglot_rt::floor_div(a, b) + polyglot_rt::modulo(a, b) + a % b"))

(define-spec print-format
  :tags (:intrinsics) :doc "print-line of format-string is merged into one call."
  :params ((n :i64) (x :f64)) :ret nil
  :lisp (print-line (format-string "n={} x={:.2f}" n x))
  :expect (:cl "(format t \"n=~a x=~,2f~%\" n x)"
               :python "print(f\"n={n} x={x:.2f}\")"
               :cpp "std::cout << std::format(\"n={} x={:.2f}\", n, x) << '\\n';"
               :rust "println!(\"n={n} x={x:.2}\");"))

(define-spec let-and-setf
  :tags (:statements) :doc "let with inferred mutability, setf, incf."
  :params ((n :i64)) :ret :i64
  :lisp (let ((acc 0)) (dotimes (i n) (incf acc i)) (setf acc (* acc 2)) acc)
  :expect (:cl "(let ((acc 0)) (loop for i from 0 below n do (incf acc i)) (setf acc (* acc 2)) acc)"
               :python "acc = 0 for i in range(n): acc += i acc = acc * 2 return acc"
               :cpp "std::int64_t acc = 0; for (std::int64_t i = 0; i < n; ++i) { acc += i; } acc = acc * 2; return acc;"
               :rust "let mut acc: i64 = 0; for i in 0..n { acc += i; } acc *= 2; acc"))

(define-spec cond-chain
  :tags (:statements) :doc "cond becomes an if/else-if chain."
  :params ((x :i64)) :ret :string
  :lisp (cond ((< x 0) "neg") ((= x 0) "zero") (t "pos"))
  :expect (:cl "(cond ((< x 0) \"neg\") ((= x 0) \"zero\") (t \"pos\"))"
               :python "if x < 0: return \"neg\" elif x == 0: return \"zero\" else: return \"pos\""
               :cpp "if (x < 0) { return \"neg\"; } else if (x == 0) { return \"zero\"; } else { return \"pos\"; }"
               :rust "if x < 0 { \"neg\".to_string() } else if x == 0 { \"zero\".to_string() } else { \"pos\".to_string() }"))

(define-spec while-break
  :tags (:statements) :doc "while with break and continue."
  :params ((n :i64)) :ret nil
  :lisp (let ((i 0)) (while true (incf i) (when (> i n) (break)) (when (= i 2) (continue)) (print-line "x")))
  :expect (:cl "(loop while t do (block pg-continue (incf i) (when (> i n) (return))"
               :python "while True: i += 1 if i > n: break if i == 2: continue print(\"x\")"
               :cpp "while (true) { ++i; if (i > n) { break; } if (i == 2) { continue; }"
               :rust "loop { i += 1; if i > n { break; } if i == 2 { continue; } println!(\"x\"); }"))

(define-spec early-return
  :tags (:statements) :doc "A return that is not in tail position."
  :params ((v (vec :i64))) :ret :i64
  :lisp (progn (dolist (x v) (when (> x 10) (return x))) 0)
  :expect (:cl "(return-from spec-f x)"
               :python "for x in v: if x > 10: return x return 0"
               :cpp "for (const auto& x : v) { if (x > 10) { return x; } } return 0;"
               :rust "for &x in v { if x > 10 { return x; } } 0"))
