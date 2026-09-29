;;;; 52-literals.lisp --- string escaping (E1), round-trip floats, integers

(in-package :polyglot)

(defun control-char-escape (code style)
  (ecase style
    (:c (format nil "\\~3,'0o" code))      ; octal: \x in C++ is greedy
    ((:python :go :rust) (format nil "\\x~(~2,'0x~)" code))))

(defun unicode-escape (code style)
  (ecase style
    (:rust (format nil "\\u{~(~x~)}" code))
    ((:c :python :go) (if (> code #xFFFF)
                          (format nil "\\U~(~8,'0x~)" code)
                          (format nil "\\u~(~4,'0x~)" code)))))

(defun escape-char-into (ch out style quote ascii-only)
  (let ((code (char-code ch)))
    (cond ((char= ch #\\) (write-string "\\\\" out))
          ((char= ch quote) (write-char #\\ out) (write-char ch out))
          ((char= ch #\Newline) (write-string "\\n" out))
          ((char= ch #\Tab) (write-string "\\t" out))
          ((char= ch #\Return) (write-string "\\r" out))
          ((or (< code 32) (= code 127)) (write-string (control-char-escape code style) out))
          ((and ascii-only (> code 127)) (write-string (unicode-escape code style) out))
          (t (write-char ch out)))))

(defun escape-string (string style &key ascii-only (quote #\"))
  "STRING as the body of a literal (without quotes) for STYLE :c :python
:rust or :go. Non-ASCII characters stay literal (files are UTF-8) unless
ASCII-ONLY is true."
  (with-output-to-string (out)
    (loop for ch across string
          do (escape-char-into ch out style quote ascii-only))))

(defun string-literal (string style &key ascii-only)
  (format nil "\"~a\"" (escape-string string style :ascii-only ascii-only)))

(defun char-literal (ch style)
  (format nil "'~a'" (escape-string (string ch) style :quote #\')))

(defun float-literal (f)
  "Shortest representation of the double F that reads back as the same number
in C++, Python, Rust and Go (exponent marker e)."
  (let* ((*read-default-float-format* 'double-float)
         (s (prin1-to-string (coerce f 'double-float))))
    (map 'string (lambda (c) (if (member c '(#\d #\D #\f #\F #\s #\S #\l #\L)) #\e c)) s)))

(defun literal-op (value)
  "Precedence class of a numeric literal: negative numbers behave like a
unary minus (they need parentheses as receivers or unary operands)."
  (if (and (realp value) (or (minusp value) (and (floatp value) (minusp (float-sign value)))))
      :neg-literal
      nil))
