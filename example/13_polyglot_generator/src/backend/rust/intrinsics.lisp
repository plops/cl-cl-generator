;;;; intrinsics.lisp --- Rust backend: format!/println! with inlined
;;;; identifiers (clippy::uninlined_format_args), other intrinsics, prelude

(in-package :polyglot)

(defun rs-inline-ident (e)
  "Identifier that can be inlined into a format string, or NIL."
  (when (and (typep e 'var-expr) (typep (ir-binding e) 'var-def))
    (let ((s (ex-str e)))
      (when (every (lambda (c) (or (alphanumericp c) (char= c #\_))) s) s))))

(defun rs-escape-format-literal (s)
  (cl-ppcre:regex-replace-all "\\}" (cl-ppcre:regex-replace-all "\\{" (escape-string s :rust) "{{") "}}"))

(defun rs-format-parts (pieces args)
  "Format string body and positional arguments for PIECES (from format-pieces)
with ARGS in order. String literals are embedded, identifiers inlined."
  (let ((out (make-string-output-stream)) (positional '()))
    (dolist (piece pieces)
      (if (stringp piece)
          (write-string (rs-escape-format-literal piece) out)
          (let* ((a (pop args))
                 (spec (if (integerp piece) (format nil ":.~d" piece) ""))
                 (ident (rs-inline-ident a)))
            (cond ((and (string-literal-p a) (string= spec ""))
                   (write-string (rs-escape-format-literal (ir-value a)) out))
                  (ident (format out "{~a~a}" ident spec))
                  (t (format out "{~a}" spec) (push (ex-str a) positional))))))
    (values (get-output-stream-string out) (nreverse positional))))

(defun rs-format-call (macro pieces args)
  (multiple-value-bind (body positional) (rs-format-parts pieces args)
    (format nil "~a!(\"~a\"~{, ~a~})" macro body positional)))

(defun rs-format-string (e)
  (let ((pieces (format-pieces (ir-value (first (ir-args e))))))
    (if (every #'stringp pieces)
        (prim (format nil "~a.to_string()" (string-literal (apply #'concatenate 'string pieces) :rust)))
        (prim (rs-format-call "format" pieces (rest (ir-args e)))))))

(defun rs-print-line (e)
  (let ((arg (first (ir-args e))))
    (prim (if (intrinsic-name-is arg "format-string")
              (rs-format-call "println" (format-pieces (ir-value (first (ir-args arg)))) (rest (ir-args arg)))
              (rs-format-call "println" (list :plain) (list arg))))))

(defun rs-string-concat (e)
  (prim (rs-format-call "format" (mapcar (constantly :plain) (ir-args e)) (ir-args e))))

(defun rs-typed-receiver (e fn)
  "x.fn() or, for literal receivers whose type Rust cannot infer, T::fn(x)."
  (let ((x (first (ir-args e))))
    (if (typep x 'lit-expr)
        (prim (format nil "~a::~a(~a)" (rs-type (ir-ty e)) fn (comma-list (ir-args e))))
        (prim (format nil "~a.~a(~a)" (receiver x) fn (comma-list (rest (ir-args e))))))))

(defun rs-cast (text-or-expr ty)
  (values (format nil "~a as ~a" (if (stringp text-or-expr) text-or-expr (operand :cast :left text-or-expr))
                  ty)
          :cast))

(defun rs-int-division (e name)
  (let ((args (ir-args e)))
    (cond ((and (= 1 (length args)) (string= name "truncate")) (rs-cast (first args) "i64"))
          ((= 1 (length args))
           (rs-cast (if (typep (first args) 'lit-expr)
                        (format nil "f64::floor(~a)" (ex-str (first args)))
                        (format nil "~a.floor()" (receiver (first args))))
                    "i64"))
          ((string= name "truncate") (binary :div (first args) (second args)))
          (t (note-prelude "floor_div")
             (prim (format nil "polyglot_rt::floor_div(~a)" (comma-list args)))))))

(defun rs-map-get (e)
  (destructuring-bind (m k) (ir-args e)
    (let ((vty (third (strip-indirection (ir-ty m)))))
      (prim (format nil "~a.get(~a).~:[cloned~;copied~]()" (receiver m) (rs-borrowed k) (copy-type-p vty))))))

(defun rs-len (e)
  (rs-cast (format nil "~a.len()" (receiver (first (ir-args e)))) "i64"))

(define-expansions :rust
    `(("print-line" :function rs-print-line)
      ("format-string" :function rs-format-string)
      ("length" :function rs-len)
      ("string-byte-length" :function rs-len)
      ("string-char-count" :function ,(lambda (e) (rs-cast (format nil "~a.chars().count()" (receiver (first (ir-args e)))) "i64")))
      ("push" :function ,(lambda (e) (prim (format nil "~a.push(~a)" (receiver (second (ir-args e)))
                                                   (ex-str-for (first (ir-args e)) (element-type (ir-ty (second (ir-args e)))))))))
      ("map-get" :function rs-map-get)
      ("map-set" :function ,(lambda (e) (destructuring-bind (m k v) (ir-args e)
                                          (let ((ty (strip-indirection (ir-ty m))))
                                            (prim (format nil "~a.insert(~a, ~a)" (receiver m)
                                                          (ex-str-for k (second ty)) (ex-str-for v (third ty))))))))
      ("map-contains" :function ,(lambda (e) (prim (format nil "~a.contains_key(~a)" (receiver (first (ir-args e)))
                                                           (rs-borrowed (second (ir-args e)))))))
      ("map-keys-sorted" :function ,(lambda (e) (note-prelude "sorted_keys")
                                      (prim (format nil "polyglot_rt::sorted_keys(~a)" (rs-borrowed (first (ir-args e)))))))
      ("string-concat" :function rs-string-concat)
      ("sqrt" :function ,(lambda (e) (rs-typed-receiver e "sqrt")))
      ("abs" :function ,(lambda (e) (rs-typed-receiver e "abs")))
      ("min" :function ,(lambda (e) (rs-typed-receiver e "min")))
      ("max" :function ,(lambda (e) (rs-typed-receiver e "max")))
      ("truncate" :function ,(lambda (e) (rs-int-division e "truncate")))
      ("floor" :function ,(lambda (e) (rs-int-division e "floor")))
      ("mod" :template "polyglot_rt::modulo($a, $b)" :prelude ("modulo"))
      ("rem" :op :rem)
      ("to-float" :function ,(lambda (e) (rs-cast (first (ir-args e)) "f64")))
      ("int-to-string" :template "$x.to_string()")
      ("string-find" :function ,(lambda (e) (destructuring-bind (s ch start) (ir-args e)
                                              (note-prelude "find_char")
                                              (prim (format nil "polyglot_rt::find_char(~a, ~a, ~a)"
                                                            (rs-borrowed s) (ex-str ch) (ex-str start))))))
      ("string-slice" :function ,(lambda (e) (destructuring-bind (s start end) (ir-args e)
                                               (prim (format nil "&~a[~a..~a]" (receiver s) (rs-index start) (rs-index end))))))))

(defparameter +rust-prelude+
  '(("floor_div" "/// Integer division rounding toward negative infinity (CL floor).
pub fn floor_div(a: i64, b: i64) -> i64 {
    let q = a / b;
    if a % b != 0 && ((a < 0) != (b < 0)) {
        q - 1
    } else {
        q
    }
}")
    ("modulo" "/// Remainder with the sign of the divisor (CL mod).
pub fn modulo(a: i64, b: i64) -> i64 {
    let r = a % b;
    if r != 0 && ((r < 0) != (b < 0)) {
        r + b
    } else {
        r
    }
}")
    ("find_char" "/// Byte offset of `c` in `s` at or after `start`, -1 when absent.
pub fn find_char(s: &str, c: char, start: i64) -> i64 {
    s[start as usize..]
        .find(c)
        .map_or(-1, |pos| pos as i64 + start)
}")
    ("sorted_keys" "/// The keys of a map in ascending order.
pub fn sorted_keys<K: Ord + Clone, V>(m: &std::collections::HashMap<K, V>) -> Vec<K> {
    let mut keys: Vec<K> = m.keys().cloned().collect();
    keys.sort();
    keys
}"))
  "Helpers of src/polyglot_rt.rs; only the used ones are written.")

(defun rust-prelude-text ()
  (format nil "//! Runtime helpers of the polyglot generator.~%~{~%~a~%~}"
          (loop for (name text) in +rust-prelude+
                when (member name *prelude-used* :test #'string=) collect text)))
