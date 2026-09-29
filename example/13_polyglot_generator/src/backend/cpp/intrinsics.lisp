;;;; intrinsics.lisp --- C++ backend: intrinsic expansions and prelude

(in-package :polyglot)

(defun cpp-rt (name)
  (note-prelude name)
  (format nil "polyglot_rt::~a" name))

(defun cpp-print-line (e)
  (cpp-std-include "iostream")
  (prim (format nil "std::cout << ~a << '\\n'" (operand :shl :right (first (ir-args e))))))

(defun cpp-format-string (e)
  (let ((fmt (ir-value (first (ir-args e)))))
    (if (null (rest (ir-args e)))
        (prim (format nil "std::string(~a)"
                      (string-literal (apply #'concatenate 'string (format-pieces fmt)) :c)))
        (progn (cpp-std-include "format")
               (prim (format nil "std::format(~a, ~a)" (string-literal fmt :c)
                             (comma-list (rest (ir-args e)))))))))

(defun cpp-size (e)
  (let ((x (first (ir-args e))))
    (prim (format nil "static_cast<std::int64_t>(~a.size())"
                  (if (typep x 'lit-expr)
                      (progn (cpp-std-include "string_view")
                             (format nil "std::string_view(~a)" (ex-str x)))
                      (receiver x))))))

(defun cpp-int-division (e name)
  (let ((args (ir-args e)))
    (cond ((and (= 1 (length args)) (string= name "truncate"))
           (prim (format nil "static_cast<std::int64_t>(~a)" (ex-str (first args)))))
          ((= 1 (length args))
           (cpp-std-include "cmath")
           (prim (format nil "static_cast<std::int64_t>(std::floor(~a))" (ex-str (first args)))))
          ((string= name "truncate") (binary :div (first args) (second args)))
          (t (prim (format nil "~a(~a)" (cpp-rt "floor_div") (comma-list args)))))))

(defun cpp-min-max (e name)
  (cpp-std-include "algorithm")
  (prim (format nil "std::~a<~a>(~a)" name (cpp-type (ir-ty e)) (comma-list (ir-args e)))))

(defun cpp-string-concat (e)
  (let ((args (ir-args e)))
    (if (null args)
        (prim "std::string()")
        (let ((acc (let ((a (first args)))
                     (if (typep a 'lit-expr)
                         (cons (format nil "std::string(~a)" (ex-str a)) nil)
                         (ex-pair a)))))
          (dolist (a (rest args) (values (car acc) (cdr acc)))
            (setf acc (multiple-value-bind (s op) (binary-string +cpp-ops+ :add acc (ex-pair a) *mode*)
                        (cons s op))))))))

(define-expansions :cpp
    `(("print-line" :function cpp-print-line)
      ("format-string" :function cpp-format-string)
      ("length" :function cpp-size)
      ("string-byte-length" :function cpp-size)
      ("string-char-count" :template "polyglot_rt::utf8_char_count($s)" :prelude ("utf8_char_count"))
      ("push" :template "$place.push_back($item)")
      ("map-get" :template "polyglot_rt::map_get($m, $k)" :prelude ("map_get"))
      ("map-set" :template "$m.insert_or_assign($k, $v)")
      ("map-contains" :template "$m.contains($k)")
      ("map-keys-sorted" :template "polyglot_rt::sorted_keys($m)" :prelude ("sorted_keys"))
      ("string-concat" :function cpp-string-concat)
      ("sqrt" :template "std::sqrt($x)" :includes ((:std "cmath")))
      ("abs" :template "std::abs($x)" :includes ((:std "cmath") (:std "cstdlib")))
      ("min" :function ,(lambda (e) (cpp-min-max e "min")))
      ("max" :function ,(lambda (e) (cpp-min-max e "max")))
      ("truncate" :function ,(lambda (e) (cpp-int-division e "truncate")))
      ("floor" :function ,(lambda (e) (cpp-int-division e "floor")))
      ("mod" :template "polyglot_rt::mod($a, $b)" :prelude ("mod"))
      ("rem" :op :rem)
      ("to-float" :template "static_cast<double>($x)")
      ("int-to-string" :template "std::to_string($x)" :includes ((:std "string")))))

(defparameter +cpp-prelude+
  '(("floor_div" ("cstdint")
     "// Integer division rounding toward negative infinity (CL floor).
inline std::int64_t floor_div(std::int64_t a, std::int64_t b) {
  std::int64_t q = a / b;
  if ((a % b != 0) && ((a < 0) != (b < 0))) {
    --q;
  }
  return q;
}")
    ("mod" ("cstdint")
     "// Remainder with the sign of the divisor (CL mod).
inline std::int64_t mod(std::int64_t a, std::int64_t b) {
  std::int64_t r = a % b;
  if ((r != 0) && ((r < 0) != (b < 0))) {
    r += b;
  }
  return r;
}")
    ("utf8_char_count" ("cstdint" "string_view")
     "// Number of Unicode code points of a UTF-8 string.
inline std::int64_t utf8_char_count(std::string_view s) {
  std::int64_t n = 0;
  for (const char c : s) {
    if ((static_cast<unsigned char>(c) & 0xC0U) != 0x80U) {
      ++n;
    }
  }
  return n;
}")
    ("map_get" ("map" "optional")
     "// Value of a key as std::optional (std::nullopt when absent).
template <typename K, typename V>
std::optional<V> map_get(const std::map<K, V>& m, const K& k) {
  const auto it = m.find(k);
  if (it == m.end()) {
    return std::nullopt;
  }
  return it->second;
}")
    ("sorted_keys" ("map" "vector")
     "// The keys of a std::map (already sorted).
template <typename K, typename V>
std::vector<K> sorted_keys(const std::map<K, V>& m) {
  std::vector<K> keys;
  keys.reserve(m.size());
  for (const auto& entry : m) {
    keys.push_back(entry.first);
  }
  return keys;
}")
    ("make_vec" ("vector" "utility")
     "// A vector of move-only values (std::initializer_list would copy).
template <typename T, typename... Args>
std::vector<T> make_vec(Args&&... args) {
  std::vector<T> v;
  v.reserve(sizeof...(args));
  (v.emplace_back(std::forward<Args>(args)), ...);
  return v;
}"))
  "Helpers of polyglot_rt.hpp: name, needed standard headers, code.")

(defun cpp-prelude-text ()
  (let ((used (remove-if-not (lambda (h) (member (first h) *prelude-used* :test #'string=))
                             +cpp-prelude+)))
    (format nil "#pragma once~%~%~{#include <~a>~%~}~%namespace polyglot_rt {~%~{~%~a~%~}~%}  // namespace polyglot_rt~%"
            (sort (remove-duplicates (loop for h in used append (second h)) :test #'string=) #'string<)
            (mapcar #'third used))))
