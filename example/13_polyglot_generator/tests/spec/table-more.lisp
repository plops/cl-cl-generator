;;;; table-more.lisp --- spec entries: remaining statements, items, ownership,
;;;; closures, literals, escape hatches

(in-package :polyglot.tests)

(define-spec let-star
  :tags (:statements) :doc "let* binds sequentially; Rust folds let x = e; x."
  :params ((a :i64)) :ret :i64
  :lisp (let* ((b (* a 2)) (c (+ b 1))) c)
  :expect (:cl "(let* ((b (* a 2)) (c (+ b 1))) c)"
               :python "b = a * 2 c = b + 1 return c"
               :cpp "const std::int64_t b = a * 2; const std::int64_t c = b + 1; return c;"
               :rust "let b: i64 = a * 2; b + 1"
               :go "b := a * 2 c := b + 1 return c"))

(define-spec unless-form
  :tags (:statements) :doc "unless is if with a negated test."
  :params ((a :i64)) :ret nil
  :lisp (unless (> a 0) (print-line "neg"))
  :expect (:cl "(unless (> a 0) (write-line \"neg\"))"
               :python "if not a > 0: print(\"neg\")"
               :cpp "if (!(a > 0)) { std::cout << \"neg\" << '\\n'; }"
               :rust "if !(a > 0) { println!(\"neg\"); }"
               :go "if !(a > 0) { fmt.Println(\"neg\") }"))

(define-spec if-let-form
  :tags (:statements :optional) :doc "if-let on an optional value (here map-get)."
  :params ((m (map :string :i64))) :ret :i64
  :lisp (if-let (v (map-get m "k")) v 0)
  :expect (:cl "(let ((v (values (gethash \"k\" m)))) (if v v 0))"
               :python "if (v := m.get(\"k\")) is not None: return v else: return 0"
               :cpp "if (const auto v_opt = polyglot_rt::map_get(m, \"k\"); v_opt.has_value()) { const auto& v = *v_opt; return v; }"
               :rust "if let Some(v) = m.get(\"k\").copied() { v } else { 0 }"
               :go "if v, ok := m[\"k\"]; ok { return v } else { return 0 }"))

(define-spec comment-form
  :tags (:statements) :doc "Comments are statements in every target."
  :params () :ret nil
  :lisp (progn (comment "explain") (print-line "x"))
  :expect (:cl ";; explain" :python "# explain print(\"x\")" :cpp "// explain std::cout"
               :rust "// explain println!(\"x\");" :go "// explain fmt.Println(\"x\")"))

(define-spec target-case-form
  :tags (:escape-hatches) :doc "target-case selects a branch per backend, t is the default."
  :params () :ret nil
  :lisp (target-case (:cpp (print-line "c++")) (t (print-line "other")))
  :expect (:cl "(write-line \"other\")" :python "print(\"other\")" :cpp "std::cout << \"c++\""
               :rust "println!(\"other\");" :go "fmt.Println(\"other\")"))

(define-spec raw-form
  :tags (:escape-hatches) :doc "raw inserts target text verbatim (usually inside target-case)."
  :params () :ret nil
  :lisp (target-case (:cpp (raw "// raw c++")) (:python (raw "pass  # raw python")) (:rust (raw "// raw rust"))
                     (:go (raw "// raw go")) (:cl (raw "(values)")))
  :expect (:cl "(defun spec-f () (values))" :python "pass # raw python" :cpp "// raw c++"
               :rust "// raw rust" :go "// raw go"))

(define-spec target-form-rejected
  :tags (:escape-hatches) :doc "A form of another backend's package is unsupported-construct (R4)."
  :params () :ret nil
  :lisp (polyglot.rs::raw "unsafe {}")
  :expect (:rust "unsafe {}")
  :expect-error (:cl unsupported-construct :python unsupported-construct :cpp unsupported-construct
                     :go unsupported-construct))

(define-spec const-form
  :tags (:items) :doc "defconst: naming per target."
  :items ("(defconst +limit+ :i64 10)")
  :params ((a :i64)) :ret :bool
  :lisp (> a +limit+)
  :expect (:cl "(defparameter +limit+ 10)" :python "LIMIT: int = 10" :cpp "constexpr std::int64_t LIMIT = 10;"
               :rust "const LIMIT: i64 = 10;" :go "const limit int64 = 10"))

(define-spec extern-form
  :tags (:items :escape-hatches) :doc "defextern binds a native function per backend."
  :items ("(defextern c-hypot ((x :f64) (y :f64)) :f64 (:cpp \"std::hypot\" :includes (\"<cmath>\")) (:rust \"f64::hypot\" :method t) (:python \"math.hypot\" :imports (\"math\")) (:go \"math.Hypot\" :imports (\"math\")) (:cl \"my-hypot\"))")
  :params ((x :f64) (y :f64)) :ret :f64
  :lisp (c-hypot x y)
  :expect (:cl "(my-hypot x y)" :python "return math.hypot(x, y)" :cpp "return std::hypot(x, y);"
               :rust "x.hypot(y)" :go "return math.Hypot(x, y)"))

(define-spec map-of-form
  :tags (:collections) :doc "map-of, map-set and length of a map."
  :params () :ret :i64
  :lisp (let ((m (map-of :string :i64))) (map-set m "a" 1) (length m))
  :expect (:cl "(setf (gethash \"a\" m) 1) (hash-table-count m)" :python "m = {} m[\"a\"] = 1 return len(m)"
               :cpp "m.insert_or_assign(\"a\", 1);" :rust "m.insert(\"a\".to_string(), 1); m.len() as i64"
               :go "m := map[string]int64{} m[\"a\"] = 1 return int64(len(m))"))

(define-spec vec-aref
  :tags (:collections) :doc "vec-of and aref."
  :params () :ret :i64
  :lisp (let ((v (vec-of :i64 1 2 3))) (aref v 1))
  :expect (:cl "(let ((v (pg-vec 1 2 3))) (aref v 1))" :python "v = [1, 2, 3] return v[1]"
               :cpp "const std::vector<std::int64_t> v = std::vector<std::int64_t>{1, 2, 3}; return v[1];"
               :rust "let v = vec![1, 2, 3]; v[1]" :go "v := []int64{1, 2, 3} return v[1]"))

(define-spec box-clone-move
  :tags (:ownership) :doc "clone copies, move transfers, box allocates (E5)."
  :items ("(defstruct p (x :i64 0))")
  :params ((a p)) :ret :i64
  :lisp (let* ((b (clone a)) (c (box (move b)))) (dot c x))
  :expect (:cl "(let* ((b (pg-clone a)) (c b)) (p-x c))" :python "b = copy.deepcopy(a) c = b return c.x"
               :cpp "const P b = a; std::unique_ptr<P> c = std::make_unique<P>(std::move(b)); return c->x;"
               :rust "let b = a.clone(); let c = Box::new(b); c.x" :go "b := a c := polyglotrt.Ptr(b) return c.x"))

(define-spec lambda-funcall
  :tags (:closures) :doc "lambda and funcall; captures by value (E3)."
  :params ((n :i64)) :ret :i64
  :lisp (let ((f (lambda (k) (declare (type :i64 k) (values :i64)) (* k n)))) (funcall f 3))
  :expect (:cl "(let ((f (lambda (k) (* k n)))) (funcall f 3))" :python "def f(k): return k * n return f(3)"
               :cpp "[=](std::int64_t k) -> std::int64_t { return k * n; };" :rust "let f = move |k: i64| k * n; f(3)"
               :go "f := func(k int64) int64 { return k * n } return f(3)"))

(define-spec string-literal-escapes
  :tags (:literals) :doc "Escapes; non-ASCII stays literal (E1)."
  :params () :ret nil
  :lisp (print-line #.(format nil "tab~a\"q\" \\ äö" #\Tab))
  :expect (:python "print(\"tab\\t\\\"q\\\" \\\\ äö\")" :cpp "std::cout << \"tab\\t\\\"q\\\" \\\\ äö\""
                   :rust "println!(\"tab\\t\\\"q\\\" \\\\ äö\");" :go "fmt.Println(\"tab\\t\\\"q\\\" \\\\ äö\")"))

(define-spec char-literal
  :tags (:literals) :doc "Characters."
  :params () :ret :char
  :lisp #\a
  :expect (:cl "#\\a" :python "return \"a\"" :cpp "return 'a';" :rust "-> char { 'a' }" :go "rune { return 'a' }"))

(define-spec some-nil
  :tags (:optional) :doc "(some x) and nil of an optional type (E7)."
  :params ((a :i64)) :ret (optional :i64)
  :lisp (if (> a 0) (some a) nil)
  :expect (:cl "(if (> a 0) a nil)" :python "-> int | None: if a > 0: return a else: return None"
               :cpp "return std::nullopt;" :rust "if a > 0 { Some(a) } else { None }"
               :go "return polyglotrt.Ptr(a) } else { return nil }"))

(define-spec call-super-form
  :tags (:inheritance) :doc "Implementation inheritance: native or lowered to composition (K3)."
  :items ("(defclass base () (defmethod f ((b :in)) (declare (values :i64) (virtual)) 1))"
          "(defclass derived (base) (defmethod f ((d :in)) (declare (values :i64) (override)) (+ 1 (call-super))))")
  :params ((d derived)) :ret :i64
  :lisp (f d)
  :expect (:cl "(defmethod f ((d derived)) (+ 1 (call-next-method)))" :python "return 1 + super().f()"
               :cpp "std::int64_t Derived::f() const { return 1 + Base::f(); }"
               :rust "fn derived_f(this: &dyn DerivedDyn) -> i64 { 1 + base_f(this) }"
               :go "func derivedF(this derivedDyn) int64 { return 1 + baseF(this) }"))

(define-spec inout-scalar
  :tags (:modes) :doc ":inout on a copy type needs pointers; Python and CL cannot express it."
  :params ((x :i64)) :modes ((x :inout)) :ret nil
  :lisp (incf x)
  :expect (:cpp "void spec_f(std::int64_t& x) { ++x; }" :rust "fn spec_f(x: &mut i64) { *x += 1; }"
                :go "func specF(x *int64) { (*x)++ }")
  :expect-error (:python unsupported-construct :cl unsupported-construct))


(define-spec borrows-from
  :tags (:borrows) :doc "borrows-from: the result borrows from x and y (K1b)."
  :params ((x (view :string)) (y (view :string))) :ret (view :string) :declare ((borrows-from x y))
  :lisp (if (> (string-byte-length x) (string-byte-length y)) x y)
  :expect (:rust "fn spec_f<'a>(x: &'a str, y: &'a str) -> &'a str"
                 :cpp "std::string_view spec_f(std::string_view x, std::string_view y)"
                 :python "def spec_f(x: str, y: str) -> str:"
                 :go "func specF(x string, y string) string"
                 :cl "(defun spec-f (x y)"))

(define-spec named-regions
  :tags (:borrows) :doc "Named regions and outlives become lifetime parameters and bounds."
  :params ((x (ref :i64 :a)) (y (ref :i64 :b))) :ret (ref :i64 :a)
  :lisp x :declare ((outlives :a :b))
  :expect (:rust "fn spec_f<'a: 'b, 'b>(x: &'a i64, _y: &'b i64) -> &'a i64"
                 :cpp "const std::int64_t& spec_f(const std::int64_t& x, [[maybe_unused]] const std::int64_t& y)"
                 :python "def spec_f(x: int, y: int) -> int: return x"))

(define-spec capture-ref
  :tags (:closures) :doc "(capture :ref) captures by reference."
  :params ((n :i64)) :ret :i64
  :lisp (let ((f (lambda (k) (declare (type :i64 k) (values :i64) (capture :ref)) (+ k n)))) (funcall f 1))
  :expect (:cpp "[&](std::int64_t k) -> std::int64_t" :rust "let f = |k: i64| k + n;"))

(define-spec decf-form
  :tags (:statements) :doc "decf with and without delta."
  :params ((a :i64)) :ret :i64
  :lisp (let ((b a)) (decf b) (decf b 3) b)
  :expect (:cl "(decf b) (decf b 3)" :python "b -= 1 b -= 3" :cpp "--b; b -= 3;" :rust "b -= 1; b -= 3;"
               :go "b-- b -= 3"))

(define-spec math-intrinsics
  :tags (:intrinsics) :doc "sqrt, abs, min, max."
  :params ((x :f64) (a :i64) (b :i64)) :ret :f64
  :lisp (+ (sqrt x) (to-float (+ (abs a) (min a b) (max a b))))
  :expect (:cl "(sqrt x)" :python "math.sqrt(x) + float(abs(a) + min(a, b) + max(a, b))"
               :cpp "std::sqrt(x) + static_cast<double>(std::abs(a) + std::min<std::int64_t>(a, b) + std::max<std::int64_t>(a, b))"
               :rust "x.sqrt() + (a.abs() + a.min(b) + a.max(b)) as f64"
               :go "math.Sqrt(x) + float64(polyglotrt.AbsInt(a) + min(a, b) + max(a, b))"))

(define-spec string-intrinsics
  :tags (:intrinsics) :doc "string-concat and string-char-count (code points)."
  :params ((s :string)) :ret :i64
  :lisp (string-char-count (string-concat s "!"))
  :expect (:cl "(length (concatenate 'string s \"!\"))" :python "len(s + \"!\")"
               :cpp "polyglot_rt::utf8_char_count(s + \"!\")" :rust "format!(\"{s}!\").chars().count() as i64"
               :go "int64(utf8.RuneCountInString(s + \"!\"))"))

(define-spec sorted-keys
  :tags (:collections) :doc "map-keys-sorted gives a deterministic order (E15); map-contains."
  :params ((m (map :string :i64))) :ret :i64
  :lisp (let ((n 0)) (dolist (k (map-keys-sorted m)) (when (map-contains m k) (incf n))) n)
  :expect (:cl "(pg-sorted-keys m 'string<)" :python "for k in sorted(m): if k in m:"
               :cpp "for (const auto& k : polyglot_rt::sorted_keys(m)) { if (m.contains(k)) {"
               :rust "for k in polyglot_rt::sorted_keys(m) { if m.contains_key(&k) {"
               :go "for _, k := range slices.Sorted(maps.Keys(m)) { if polyglotrt.Contains(m, k) {"))
