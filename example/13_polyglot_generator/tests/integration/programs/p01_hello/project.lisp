;;;; p01_hello --- print-line with Unicode and escapes (E1)

(in-package :polyglot-user)
(in-dsl)

(defmodule hello (:entry t)
  (defun main ()
    (print-line "Hello, World!")
    (print-line "Umlaute: äöü ÄÖÜ ß")
    (print-line "CJK: 你好，世界")
    (print-line "Emoji: 😀🚀")
    (print-line "Quote: \" Backslash: \\ Braces: {} {{x}}")
    (print-line #.(format nil "Tab:~aend" #\Tab))
    (print-line "Line1
Line2")
    (print-line (format-string "{} has {} bytes and {} characters"
                               "äö😀" (string-byte-length "äö😀") (string-char-count "äö😀")))))

(defproject hello (:modules hello) (:entry hello))
