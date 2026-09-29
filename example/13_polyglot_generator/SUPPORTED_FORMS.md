# Supported forms

Generated from the spec table in `tests/spec/` by `./run-tests.sh --docs`.
Do not edit by hand; `./run-tests.sh --docs-check` fails when this file is outdated.

Every cell is a fragment of the generated code (whitespace normalized) that the
spec test checks; *unsupported-construct* means the backend rejects the form (R4).

43 entries, 13 tags.

## Borrows

| Name | DSL | Common Lisp | Python | C++ | Rust | Go |
|---|---|---|---|---|---|---|
| view-parameter | `(string-byte-length s)` | `(pg-utf8-length s)` | `def spec_f(s: str) -> int: return len(s.encode())` | `std::int64_t spec_f(std::string_view s) { return static_cast<std::int64_t>(s.size()); }` | `fn spec_f(s: &str) -> i64 { s.len() as i64 }` | `func specF(s string) int64 { return int64(len(s)) }` |
| borrows-from | `(if (> (string-byte-length x) (string-byte-length y)) x y)` | `(defun spec-f (x y)` | `def spec_f(x: str, y: str) -> str:` | `std::string_view spec_f(std::string_view x, std::string_view y)` | `fn spec_f<'a>(x: &'a str, y: &'a str) -> &'a str` | `func specF(x string, y string) string` |
| named-regions | `x` | — | `def spec_f(x: int, y: int) -> int: return x` | `const std::int64_t& spec_f(const std::int64_t& x, [[maybe_unused]] const std::int64_t& y)` | `fn spec_f<'a: 'b, 'b>(x: &'a i64, _y: &'b i64) -> &'a i64` | — |

## Closures

| Name | DSL | Common Lisp | Python | C++ | Rust | Go |
|---|---|---|---|---|---|---|
| lambda-funcall | `(let ((f (lambda (k) (declare (type :i64 k) (values :i64)) (* k n)))) (funcall f 3))` | `(let ((f (lambda (k) (* k n)))) (funcall f 3))` | `def f(k): return k * n return f(3)` | `[=](std::int64_t k) -> std::int64_t { return k * n; };` | `let f = move \|k: i64\| k * n; f(3)` | `f := func(k int64) int64 { return k * n } return f(3)` |
| capture-ref | `(let ((f (lambda (k) (declare (type :i64 k) (values :i64) (capture :ref)) (+ k n)))) (funcall f 1))` | — | — | `[&](std::int64_t k) -> std::int64_t` | `let f = \|k: i64\| k + n;` | — |

## Collections

| Name | DSL | Common Lisp | Python | C++ | Rust | Go |
|---|---|---|---|---|---|---|
| map-of-form | `(let ((m (map-of :string :i64))) (map-set m "a" 1) (length m))` | `(setf (gethash "a" m) 1) (hash-table-count m)` | `m = {} m["a"] = 1 return len(m)` | `m.insert_or_assign("a", 1);` | `m.insert("a".to_string(), 1); m.len() as i64` | `m := map[string]int64{} m["a"] = 1 return int64(len(m))` |
| vec-aref | `(let ((v (vec-of :i64 1 2 3))) (aref v 1))` | `(let ((v (pg-vec 1 2 3))) (aref v 1))` | `v = [1, 2, 3] return v[1]` | `const std::vector<std::int64_t> v = std::vector<std::int64_t>{1, 2, 3}; return v[1];` | `let v = vec![1, 2, 3]; v[1]` | `v := []int64{1, 2, 3} return v[1]` |
| sorted-keys | `(let ((n 0)) (dolist (k (map-keys-sorted m)) (when (map-contains m k) (incf n))) n)` | `(pg-sorted-keys m 'string<)` | `for k in sorted(m): if k in m:` | `for (const auto& k : polyglot_rt::sorted_keys(m)) { if (m.contains(k)) {` | `for k in polyglot_rt::sorted_keys(m) { if m.contains_key(&k) {` | `for _, k := range slices.Sorted(maps.Keys(m)) { if polyglotrt.Contains(m, k) {` |

## Escape Hatches

| Name | DSL | Common Lisp | Python | C++ | Rust | Go |
|---|---|---|---|---|---|---|
| target-case-form | `(target-case (:cpp (print-line "c++")) (t (print-line "other")))` | `(write-line "other")` | `print("other")` | `std::cout << "c++"` | `println!("other");` | `fmt.Println("other")` |
| raw-form | `(target-case (:cpp (raw "// raw c++")) (:python (raw "pass # raw python")) (:rust (raw "// raw rust")) (:go (raw "// raw go")) (:cl (raw "(values)")))` | `(defun spec-f () (values))` | `pass # raw python` | `// raw c++` | `// raw rust` | `// raw go` |
| target-form-rejected | `(polyglot.rs::raw "unsafe {}")` | *unsupported-construct* | *unsupported-construct* | *unsupported-construct* | `unsafe {}` | *unsupported-construct* |
| extern-form | `(c-hypot x y)` | `(my-hypot x y)` | `return math.hypot(x, y)` | `return std::hypot(x, y);` | `x.hypot(y)` | `return math.Hypot(x, y)` |

## Inheritance

| Name | DSL | Common Lisp | Python | C++ | Rust | Go |
|---|---|---|---|---|---|---|
| call-super-form | `(f d)` | `(defmethod f ((d derived)) (+ 1 (call-next-method)))` | `return 1 + super().f()` | `std::int64_t Derived::f() const { return 1 + Base::f(); }` | `fn derived_f(this: &dyn DerivedDyn) -> i64 { 1 + base_f(this) }` | `func derivedF(this derivedDyn) int64 { return 1 + baseF(this) }` |

## Intrinsics

| Name | DSL | Common Lisp | Python | C++ | Rust | Go |
|---|---|---|---|---|---|---|
| int-division | `(+ (truncate a b) (floor a b) (mod a b) (rem a b))` | `(+ (values (truncate a b)) (values (floor a b)) (mod a b) (rem a b))` | `trunc_div(a, b) + a // b + a % b + rem(a, b)` | `a / b + polyglot_rt::floor_div(a, b) + polyglot_rt::mod(a, b) + a % b` | `a / b + polyglot_rt::floor_div(a, b) + polyglot_rt::modulo(a, b) + a % b` | `a / b + polyglotrt.FloorDiv(a, b) + polyglotrt.Mod(a, b) + a % b` |
| print-format | `(print-line (format-string "n={} x={:.2f}" n x))` | `(format t "n=~a x=~,2f~%" n x)` | `print(f"n={n} x={x:.2f}")` | `std::cout << std::format("n={} x={:.2f}", n, x) << '\n';` | `println!("n={n} x={x:.2}");` | `fmt.Printf("n=%d x=%.2f\n", n, x)` |
| math-intrinsics | `(+ (sqrt x) (to-float (+ (abs a) (min a b) (max a b))))` | `(sqrt x)` | `math.sqrt(x) + float(abs(a) + min(a, b) + max(a, b))` | `std::sqrt(x) + static_cast<double>(std::abs(a) + std::min<std::int64_t>(a, b) + std::max<std::int64_t>(a, b))` | `x.sqrt() + (a.abs() + a.min(b) + a.max(b)) as f64` | `math.Sqrt(x) + float64(polyglotrt.AbsInt(a) + min(a, b) + max(a, b))` |
| string-intrinsics | `(string-char-count (string-concat s "!"))` | `(length (concatenate 'string s "!"))` | `len(s + "!")` | `polyglot_rt::utf8_char_count(s + "!")` | `format!("{s}!").chars().count() as i64` | `int64(utf8.RuneCountInString(s + "!"))` |

## Items

| Name | DSL | Common Lisp | Python | C++ | Rust | Go |
|---|---|---|---|---|---|---|
| struct-construction | `(make-point :y 2.0)` | `(make-instance 'point :y 2.0d0)` | `return Point(y=2.0)` | `return Point{.y = 2.0};` | `Point { x: 0.0, y: 2.0 }` | `return point{x: 0.0, y: 2.0}` |
| const-method | `(norm p)` | `(defmethod norm ((p point)) (* (point-x p) (point-x p)))` | `def norm(self) -> float: return self.x * self.x` | `double norm() const;` | `fn norm(&self) -> f64 { self.x * self.x }` | `func (p point) norm() float64 { return p.x * p.x }` |
| interface-declaration | `(area s)` | `(defgeneric area (s))` | `class Shape(ABC): @abstractmethod def area(self) -> float: ...` | `struct Shape { virtual ~Shape() = default; virtual double area() const = 0; };` | `trait Shape { fn area(&self) -> f64; }` | `type shape interface { area() float64 }` |
| const-form | `(> a +limit+)` | `(defparameter +limit+ 10)` | `LIMIT: int = 10` | `constexpr std::int64_t LIMIT = 10;` | `const LIMIT: i64 = 10;` | `const limit int64 = 10` |
| extern-form | `(c-hypot x y)` | `(my-hypot x y)` | `return math.hypot(x, y)` | `return std::hypot(x, y);` | `x.hypot(y)` | `return math.Hypot(x, y)` |

## Literals

| Name | DSL | Common Lisp | Python | C++ | Rust | Go |
|---|---|---|---|---|---|---|
| string-literal-escapes | `(print-line "tab \"q\" \\ äö")` | — | `print("tab\t\"q\" \\ äö")` | `std::cout << "tab\t\"q\" \\ äö"` | `println!("tab\t\"q\" \\ äö");` | `fmt.Println("tab\t\"q\" \\ äö")` |
| char-literal | `#\a` | `#\a` | `return "a"` | `return 'a';` | `-> char { 'a' }` | `rune { return 'a' }` |

## Modes

| Name | DSL | Common Lisp | Python | C++ | Rust | Go |
|---|---|---|---|---|---|---|
| modes-parameters | `(push (length (dot a items)) (dot b items))` | `(vector-push-extend (length (bag-items a)) (bag-items b))` | `def spec_f(a: Bag, b: Bag, c: Bag) -> None: b.items.append(len(a.items))` | `void spec_f(const Bag& a, Bag& b, [[maybe_unused]] Bag c)` | `fn spec_f(a: &Bag, b: &mut Bag, _c: Bag) { b.items.push(a.items.len() as i64); }` | `func specF(a bag, b *bag, c bag) { b.items = append(b.items, int64(len(a.items))) }` |
| inout-scalar | `(incf x)` | *unsupported-construct* | *unsupported-construct* | `void spec_f(std::int64_t& x) { ++x; }` | `fn spec_f(x: &mut i64) { *x += 1; }` | `func specF(x *int64) { (*x)++ }` |

## Operators

| Name | DSL | Common Lisp | Python | C++ | Rust | Go |
|---|---|---|---|---|---|---|
| add-mul | `(+ a (* b c))` | `(+ a (* b c))` | `return a + b * c` | `return a + b * c;` | `fn spec_f(a: i64, b: i64, c: i64) -> i64 { a + b * c }` | `return a + b * c` |
| sub-right | `(- a (- b c))` | `(- a (- b c))` | `a - (b - c)` | `a - (b - c)` | `a - (b - c)` | `a - (b - c)` |
| logic | `(or (and a b) (not c))` | `(or (and a b) (not c))` | `a and b or not c` | `return (a && b) \|\| !c;` | `a && b \|\| !c` | `a && b \|\| !c` |
| bitwise | `(logior (logand a b) (shl a 2))` | `(logior (logand a b) (ash a 2))` | `a & b \| a << 2` | `(a & b) \| (a << 2)` | `a & b \| a << 2` | `a & b \| a << 2` |
| not-equal | `(/= a b)` | `(/= a b)` | `a != b` | `a != b` | `a != b` | `a != b` |
| string-equal | `(= a b)` | `(string= a b)` | `a == b` | `bool spec_f(const std::string& a, const std::string& b)` | `fn spec_f(a: &str, b: &str) -> bool { a == b }` | `func specF(a string, b string) bool` |
| float-division | `(/ x 2)` | `(/ x 2.0d0)` | `x / 2.0` | `x / 2.0` | `x / 2.0` | `x / 2.0` |

## Optional

| Name | DSL | Common Lisp | Python | C++ | Rust | Go |
|---|---|---|---|---|---|---|
| if-let-form | `(if-let (v (map-get m "k")) v 0)` | `(let ((v (values (gethash "k" m)))) (if v v 0))` | `if (v := m.get("k")) is not None: return v else: return 0` | `if (const auto v_opt = polyglot_rt::map_get(m, "k"); v_opt.has_value()) { const auto& v = *v_opt; return v; }` | `if let Some(v) = m.get("k").copied() { v } else { 0 }` | `if v, ok := m["k"]; ok { return v } else { return 0 }` |
| some-nil | `(if (> a 0) (some a) nil)` | `(if (> a 0) a nil)` | `-> int \| None: if a > 0: return a else: return None` | `return std::nullopt;` | `if a > 0 { Some(a) } else { None }` | `return polyglotrt.Ptr(a) } else { return nil }` |

## Ownership

| Name | DSL | Common Lisp | Python | C++ | Rust | Go |
|---|---|---|---|---|---|---|
| box-clone-move | `(let* ((b (clone a)) (c (box (move b)))) (dot c x))` | `(let* ((b (pg-clone a)) (c b)) (p-x c))` | `b = copy.deepcopy(a) c = b return c.x` | `const P b = a; std::unique_ptr<P> c = std::make_unique<P>(std::move(b)); return c->x;` | `let b = a.clone(); let c = Box::new(b); c.x` | `b := a c := polyglotrt.Ptr(b) return c.x` |

## Statements

| Name | DSL | Common Lisp | Python | C++ | Rust | Go |
|---|---|---|---|---|---|---|
| let-and-setf | `(let ((acc 0)) (dotimes (i n) (incf acc i)) (setf acc (* acc 2)) acc)` | `(let ((acc 0)) (loop for i from 0 below n do (incf acc i)) (setf acc (* acc 2)) acc)` | `acc = 0 for i in range(n): acc += i acc = acc * 2 return acc` | `std::int64_t acc = 0; for (std::int64_t i = 0; i < n; ++i) { acc += i; } acc = acc * 2; return acc;` | `let mut acc: i64 = 0; for i in 0..n { acc += i; } acc *= 2; acc` | `var acc int64 = 0 for i := int64(0); i < n; i++ { acc += i } acc = acc * 2 return acc` |
| cond-chain | `(cond ((< x 0) "neg") ((= x 0) "zero") (t "pos"))` | `(cond ((< x 0) "neg") ((= x 0) "zero") (t "pos"))` | `if x < 0: return "neg" elif x == 0: return "zero" else: return "pos"` | `if (x < 0) { return "neg"; } else if (x == 0) { return "zero"; } else { return "pos"; }` | `if x < 0 { "neg".to_string() } else if x == 0 { "zero".to_string() } else { "pos".to_string() }` | `if x < 0 { return "neg" } else if x == 0 { return "zero" } else { return "pos" }` |
| while-break | `(let ((i 0)) (while true (incf i) (when (> i n) (break)) (when (= i 2) (continue)) (print-line "x")))` | `(loop while t do (block pg-continue (incf i) (when (> i n) (return))` | `while True: i += 1 if i > n: break if i == 2: continue print("x")` | `while (true) { ++i; if (i > n) { break; } if (i == 2) { continue; }` | `loop { i += 1; if i > n { break; } if i == 2 { continue; } println!("x"); }` | `for { i++ if i > n { break } if i == 2 { continue } fmt.Println("x") }` |
| early-return | `(progn (dolist (x v) (when (> x 10) (return x))) 0)` | `(return-from spec-f x)` | `for x in v: if x > 10: return x return 0` | `for (const auto& x : v) { if (x > 10) { return x; } } return 0;` | `for &x in v { if x > 10 { return x; } } 0` | `for _, x := range v { if x > 10 { return x } } return 0` |
| let-star | `(let* ((b (* a 2)) (c (+ b 1))) c)` | `(let* ((b (* a 2)) (c (+ b 1))) c)` | `b = a * 2 c = b + 1 return c` | `const std::int64_t b = a * 2; const std::int64_t c = b + 1; return c;` | `let b: i64 = a * 2; b + 1` | `b := a * 2 c := b + 1 return c` |
| unless-form | `(unless (> a 0) (print-line "neg"))` | `(unless (> a 0) (write-line "neg"))` | `if not a > 0: print("neg")` | `if (!(a > 0)) { std::cout << "neg" << '\n'; }` | `if !(a > 0) { println!("neg"); }` | `if !(a > 0) { fmt.Println("neg") }` |
| if-let-form | `(if-let (v (map-get m "k")) v 0)` | `(let ((v (values (gethash "k" m)))) (if v v 0))` | `if (v := m.get("k")) is not None: return v else: return 0` | `if (const auto v_opt = polyglot_rt::map_get(m, "k"); v_opt.has_value()) { const auto& v = *v_opt; return v; }` | `if let Some(v) = m.get("k").copied() { v } else { 0 }` | `if v, ok := m["k"]; ok { return v } else { return 0 }` |
| comment-form | `(progn (comment "explain") (print-line "x"))` | `;; explain` | `# explain print("x")` | `// explain std::cout` | `// explain println!("x");` | `// explain fmt.Println("x")` |
| decf-form | `(let ((b a)) (decf b) (decf b 3) b)` | `(decf b) (decf b 3)` | `b -= 1 b -= 3` | `--b; b -= 3;` | `b -= 1; b -= 3;` | `b-- b -= 3` |
