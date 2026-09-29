;;;; intrinsics.lisp --- Go backend: fmt verbs by type, other intrinsics, prelude

(in-package :polyglot)

(defun go-std (pkg) (note-import (list :std pkg)))

(defun go-verb (arg precision)
  (let ((ty (borrow-target (ir-ty arg))))
    (cond (precision (format nil "%.~df" precision))
          ((int-type-p ty) "%d")
          ((member ty '(:string)) "%s")
          ((eq ty :char) "%c")
          (t "%v"))))

(defun go-format-parts (fmt args)
  "Printf format and argument texts for a DSL format string."
  (let ((out (make-string-output-stream)) (texts '()))
    (dolist (piece (format-pieces fmt))
      (if (stringp piece)
          (write-string (cl-ppcre:regex-replace-all "%" (escape-string piece :go) "%%") out)
          (let ((a (pop args)))
            (write-string (go-verb a (and (integerp piece) piece)) out)
            (push (go-arg a (make-var-def :name "arg" :kind :param :mode :in :ty (ir-ty a))) texts))))
    (values (get-output-stream-string out) (nreverse texts))))

(defun go-format-string (e)
  (let ((fmt (ir-value (first (ir-args e)))))
    (if (null (rest (ir-args e)))
        (prim (string-literal (apply #'concatenate 'string (format-pieces fmt)) :go))
        (multiple-value-bind (f args) (go-format-parts fmt (rest (ir-args e)))
          (go-std "fmt")
          (prim (format nil "fmt.Sprintf(\"~a\"~{, ~a~})" f args))))))

(defun go-print-line (e)
  (let ((arg (first (ir-args e))))
    (go-std "fmt")
    (if (and (intrinsic-name-is arg "format-string") (rest (ir-args arg)))
        (multiple-value-bind (f args) (go-format-parts (ir-value (first (ir-args arg))) (rest (ir-args arg)))
          (prim (format nil "fmt.Printf(\"~a\\n\"~{, ~a~})" f args)))
        (prim (format nil "fmt.Println(~a)" (ex-str arg))))))

(defun go-rt (name)
  (note-prelude name)
  (format nil "polyglotrt.~a" name))

(defun go-int-division (e name)
  (let ((args (ir-args e)))
    (cond ((and (= 1 (length args)) (string= name "truncate"))
           ;; int64(-7.9) is a compile error for constants
           (go-std "math") (prim (format nil "int64(math.Trunc(~a))" (ex-str (first args)))))
          ((= 1 (length args)) (go-std "math") (prim (format nil "int64(math.Floor(~a))" (ex-str (first args)))))
          ((string= name "truncate") (binary :div (first args) (second args)))
          (t (prim (format nil "~a(~a)" (go-rt "FloorDiv") (comma-list args)))))))

(defun go-push (e)
  (destructuring-bind (item place) (ir-args e)
    (let ((p (ex-str place)))
      (prim (format nil "~a = append(~a, ~a)" p p (ex-str item))))))

(defun go-abs (e)
  (let ((x (first (ir-args e))))
    (if (float-type-p (ir-ty e))
        (progn (go-std "math") (prim (format nil "math.Abs(~a)" (ex-str x))))
        (prim (format nil "~a(~a)" (go-rt "AbsInt") (ex-str x))))))

(define-expansions :go
    `(("print-line" :function go-print-line)
      ("format-string" :function go-format-string)
      ("length" :template "int64(len($x))")
      ("string-byte-length" :template "int64(len($s))")
      ("string-char-count" :template "int64(utf8.RuneCountInString($s))" :imports ((:std "unicode/utf8")))
      ("push" :function go-push)
      ("map-get" :template "polyglotrt.MapGet($m, $k)" :prelude ("MapGet"))
      ("map-set" :template "$m[$k] = $v")
      ("map-contains" :template "polyglotrt.Contains($m, $k)" :prelude ("Contains"))
      ("map-keys-sorted" :template "slices.Sorted(maps.Keys($m))" :imports ((:std "maps") (:std "slices")))
      ("string-concat" :function ,(lambda (e) (let ((acc (ex-pair (first (ir-args e)))))
                                                (dolist (a (rest (ir-args e)) (values (car acc) (cdr acc)))
                                                  (setf acc (multiple-value-bind (s op)
                                                                (binary-string +go-ops+ :add acc (ex-pair a) *mode*)
                                                              (cons s op)))))))
      ("sqrt" :template "math.Sqrt($x)" :imports ((:std "math")))
      ("abs" :function go-abs)
      ("min" :template "min($a, $b)")
      ("max" :template "max($a, $b)")
      ("truncate" :function ,(lambda (e) (go-int-division e "truncate")))
      ("floor" :function ,(lambda (e) (go-int-division e "floor")))
      ("mod" :template "polyglotrt.Mod($a, $b)" :prelude ("Mod"))
      ("rem" :op :rem)
      ("to-float" :template "float64($x)")
      ("int-to-string" :template "strconv.FormatInt($x, 10)" :imports ((:std "strconv")))
      ("string-find" :template "polyglotrt.FindChar($s, $ch, $start)" :prelude ("FindChar"))
      ("string-slice" :template "$s[$start:$end]")))

(defparameter +go-prelude+
  '(("FloorDiv" () "// FloorDiv divides rounding toward negative infinity (CL floor).
func FloorDiv(a, b int64) int64 {
	q := a / b
	if a%b != 0 && ((a < 0) != (b < 0)) {
		q--
	}
	return q
}")
    ("Mod" () "// Mod is the remainder with the sign of the divisor (CL mod).
func Mod(a, b int64) int64 {
	r := a % b
	if r != 0 && ((r < 0) != (b < 0)) {
		r += b
	}
	return r
}")
    ("AbsInt" () "// AbsInt is the absolute value of an integer.
func AbsInt(x int64) int64 {
	if x < 0 {
		return -x
	}
	return x
}")
    ("FindChar" ("strings") "// FindChar is the byte offset of c in s at or after start, -1 when absent.
func FindChar(s string, c rune, start int64) int64 {
	i := strings.IndexRune(s[start:], c)
	if i < 0 {
		return -1
	}
	return int64(i) + start
}")
    ("MapGet" () "// MapGet returns a pointer to a copy of the value, nil when absent.
func MapGet[K comparable, V any](m map[K]V, k K) *V {
	if v, ok := m[k]; ok {
		return &v
	}
	return nil
}")
    ("Contains" () "// Contains reports whether the map has the key.
func Contains[K comparable, V any](m map[K]V, k K) bool {
	_, ok := m[k]
	return ok
}")
    ("Ptr" () "// Ptr returns a pointer to a copy of v.
func Ptr[T any](v T) *T {
	return &v
}"))
  "Helpers of polyglotrt/polyglotrt.go: name, imports, code.")

(defun go-prelude-text ()
  (let ((used (remove-if-not (lambda (h) (member (first h) *prelude-used* :test #'string=)) +go-prelude+)))
    (format nil "// Package polyglotrt holds the runtime helpers of the polyglot generator.~%package polyglotrt~%~
                 ~@[~%import (~{~%	~s~}~%)~%~]~{~%~a~%~}"
            (sort (remove-duplicates (loop for h in used append (second h)) :test #'string=) #'string<)
            (mapcar #'third used))))
