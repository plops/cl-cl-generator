;;;; table-items.lisp --- spec entries: structs, methods, interfaces, views

(in-package :polyglot.tests)

(define-spec struct-construction
  :tags (:items) :doc "make-<struct> with named fields; missing fields keep their default."
  :items ("(defstruct point (x :f64 0d0) (y :f64 0d0))")
  :params () :ret point
  :lisp (make-point :y 2d0)
  :expect (:cl "(make-instance 'point :y 2.0d0)"
               :python "return Point(y=2.0)"
               :cpp "return Point{.y = 2.0};"
               :rust "Point { x: 0.0, y: 2.0 }"))

(define-spec const-method
  :tags (:items) :doc "A method with an :in receiver is const in C++."
  :items ("(defstruct point (x :f64 0d0) (defmethod norm ((p :in)) (declare (values :f64)) (* (dot p x) (dot p x))))")
  :params ((p point)) :ret :f64
  :lisp (norm p)
  :expect (:cl "(defmethod norm ((p point)) (* (point-x p) (point-x p)))"
               :python "def norm(self) -> float: return self.x * self.x"
               :cpp "double norm() const;"
               :rust "fn norm(&self) -> f64 { self.x * self.x }"))

(define-spec interface-declaration
  :tags (:items) :doc "Interfaces: abstract methods and a virtual destructor."
  :items ("(definterface shape (defmethod area ((s :in)) (declare (values :f64))))"
          "(defstruct sq (:implements shape) (a :f64) (defmethod area ((q :in)) (* (dot q a) (dot q a))))")
  :params ((s (box (dyn shape)))) :ret :f64
  :lisp (area s)
  :expect (:cl "(defgeneric area (s))"
               :python "class Shape(ABC): @abstractmethod def area(self) -> float: ..."
               :cpp "struct Shape { virtual ~Shape() = default; virtual double area() const = 0; };"
               :rust "trait Shape { fn area(&self) -> f64; }"))

(define-spec view-parameter
  :tags (:borrows) :doc "(view :string) is passed by value as a view."
  :params ((s (view :string))) :ret :i64
  :lisp (string-byte-length s)
  :expect (:cl "(pg-utf8-length s)"
               :python "def spec_f(s: str) -> int: return len(s.encode())"
               :cpp "std::int64_t spec_f(std::string_view s) { return static_cast<std::int64_t>(s.size()); }"
               :rust "fn spec_f(s: &str) -> i64 { s.len() as i64 }"))

(define-spec modes-parameters
  :tags (:modes) :doc "Parameter modes :in, :inout and :sink (K1)."
  :items ("(defstruct bag (items (vec :i64) nil))")
  :params ((a bag) (b bag) (c bag)) :modes ((b :inout) (c :sink)) :ret nil
  :lisp (push (length (dot a items)) (dot b items))
  :expect (:cl "(vector-push-extend (length (bag-items a)) (bag-items b))"
               :python "def spec_f(a: Bag, b: Bag, c: Bag) -> None: b.items.append(len(a.items))"
               :cpp "void spec_f(const Bag& a, Bag& b, [[maybe_unused]] Bag c)"
               :rust "fn spec_f(a: &Bag, b: &mut Bag, _c: Bag) { b.items.push(a.items.len() as i64); }"))
