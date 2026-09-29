;;;; intrinsics.lisp --- Python backend: intrinsic expansions and prelude

(in-package :polyglot)

(defun py-fstring (e)
  "f-string for (format-string fmt args...)."
  (let ((args (rest (ir-args e))))
    (with-output-to-string (s)
      (write-string "f\"" s)
      (dolist (piece (format-pieces (ir-value (first (ir-args e)))))
        (if (stringp piece)
            (write-string (cl-ppcre:regex-replace-all
                           "\\}" (cl-ppcre:regex-replace-all "\\{" (escape-string piece :python) "{{")
                           "}}")
                          s)
            (format s "{~a~@[:.~df~]}" (ex-str (pop args)) (and (integerp piece) piece))))
      (write-string "\"" s))))

(defun py-format-string (e)
  (let ((pieces (format-pieces (ir-value (first (ir-args e))))))
    (if (every #'stringp pieces)
        (prim (string-literal (apply #'concatenate 'string pieces) :python))
        (prim (py-fstring e)))))

(defun py-int-division (e name)
  (let ((args (ir-args e)))
    (if (= 1 (length args))
        (progn (note-import (list :import "math"))
               (prim (format nil "math.~a(~a)" (if (string= name "floor") "floor" "trunc")
                             (ex-str (first args)))))
        (if (string= name "floor")
            (binary :floordiv (first args) (second args))
            (progn (note-prelude "trunc_div")
                   (note-import (list :from "polyglot_rt" "trunc_div"))
                   (prim (format nil "trunc_div(~a)" (comma-list args))))))))

(defun py-rem (e)
  (note-prelude "trunc_div")
  (note-prelude "rem")
  (note-import (list :from "polyglot_rt" "rem"))
  (prim (format nil "rem(~a)" (comma-list (ir-args e)))))

(defun py-string-concat (e)
  (let ((args (ir-args e)))
    (if (null args)
        (prim "\"\"")
        (let ((acc (ex-pair (first args))))
          (dolist (a (rest args) (values (car acc) (cdr acc)))
            (setf acc (multiple-value-bind (s op)
                          (binary-string +python-ops+ :add acc (ex-pair a) *mode*)
                        (cons s op))))))))

(define-expansions :python
    `(("print-line" :template "print($x)")
      ("format-string" :function py-format-string)
      ("length" :template "len($x)")
      ("string-byte-length" :template "len($s.encode())")
      ("string-char-count" :template "len($s)")
      ("push" :template "$place.append($item)")
      ("map-get" :template "$m.get($k)")
      ("map-set" :template "$m[$k] = $v")
      ("map-contains" :function ,(lambda (e) (binary :in (second (ir-args e)) (first (ir-args e)))))
      ("map-keys-sorted" :template "sorted($m)")
      ("string-concat" :function py-string-concat)
      ("sqrt" :template "math.sqrt($x)" :imports ((:import "math")))
      ("abs" :template "abs($x)")
      ("min" :template "min($a, $b)")
      ("max" :template "max($a, $b)")
      ("truncate" :function ,(lambda (e) (py-int-division e "truncate")))
      ("floor" :function ,(lambda (e) (py-int-division e "floor")))
      ("mod" :op :mod)
      ("rem" :function py-rem)
      ("to-float" :template "float($x)")
      ("int-to-string" :template "str($x)")))

(defparameter +python-prelude+
  '(("trunc_div" "def trunc_div(a: int, b: int) -> int:
    \"\"\"Integer division rounding toward zero (CL truncate, C++ /).\"\"\"
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b >= 0) else -q")
    ("rem" "def rem(a: int, b: int) -> int:
    \"\"\"Remainder with the sign of the dividend (CL rem, C++ %).\"\"\"
    return a - b * trunc_div(a, b)"))
  "Helpers of polyglot_rt.py; only the used ones are written.")

(defun python-prelude-text ()
  (format nil "\"\"\"Runtime helpers of the polyglot generator.\"\"\"~%~{~%~%~a~}~%"
          (loop for (name text) in +python-prelude+
                when (member name *prelude-used* :test #'string=) collect text)))
