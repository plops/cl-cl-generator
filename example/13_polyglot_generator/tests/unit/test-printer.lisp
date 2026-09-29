;;;; test-printer.lisp --- writer, precedence engine and literals

(in-package :polyglot.tests)

(def-suite :polyglot.unit.printer :in :polyglot.unit)
(in-suite :polyglot.unit.printer)

(defparameter *c-table*
  (make-op-table
   :entries '((:op :postfix :level 20) (:op :neg :token "-" :level 15) (:op :neg-literal :level 15)
              (:op :not :token "!" :level 15)
              (:op :mul :token "*" :level 13) (:op :div :token "/" :level 13)
              (:op :add :token "+" :level 12) (:op :sub :token "-" :level 12)
              (:op :shl :token "<<" :level 11)
              (:op :lt :token "<" :level 9 :assoc :non) (:op :eq :token "==" :level 8 :assoc :non)
              (:op :bitand :token "&" :level 7) (:op :and :token "&&" :level 4)
              (:op :or :token "||" :level 3))
   :clarity '(((:shl) (:add :sub)) ((:or) (:and)))))

(defparameter *py-table*
  (make-op-table
   :entries '((:op :postfix :level 20) (:op :mul :token "*" :level 13) (:op :neg :token "-" :level 14)
              (:op :neg-literal :level 14) (:op :add :token "+" :level 12) (:op :sub :token "-" :level 12)
              (:op :lt :token "<" :level 6 :assoc :non) (:op :not :token "not " :level 5)
              (:op :and :token "and" :level 4) (:op :or :token "or" :level 3))))

(defun bin (table op l r &optional (mode :minimal))
  (multiple-value-bind (s o) (binary-string table op l r mode) (cons s o)))

(defun leaf (s) (cons s nil))

(test minimal-parentheses
  (let ((t1 *c-table*))
    (is (string= "a + b * c" (car (bin t1 :add (leaf "a") (bin t1 :mul (leaf "b") (leaf "c"))))))
    (is (string= "(a + b) * c" (car (bin t1 :mul (bin t1 :add (leaf "a") (leaf "b")) (leaf "c")))))
    (is (string= "a - b - c" (car (bin t1 :sub (bin t1 :sub (leaf "a") (leaf "b")) (leaf "c")))))
    (is (string= "a - (b - c)" (car (bin t1 :sub (leaf "a") (bin t1 :sub (leaf "b") (leaf "c"))))))
    (is (string= "a + (b + c)" (car (bin t1 :add (leaf "a") (bin t1 :add (leaf "b") (leaf "c"))))))
    (is (string= "a + b - c" (car (bin t1 :sub (bin t1 :add (leaf "a") (leaf "b")) (leaf "c")))))))

(test non-associative-and-clarity
  (let ((t1 *c-table*))
    (is (string= "(a < b) == c" (car (bin t1 :eq (bin t1 :lt (leaf "a") (leaf "b")) (leaf "c")))))
    (is (string= "(a < b) < c" (car (bin t1 :lt (bin t1 :lt (leaf "a") (leaf "b")) (leaf "c")))))
    (is (string= "a << (b + c)" (car (bin t1 :shl (leaf "a") (bin t1 :add (leaf "b") (leaf "c"))))))
    (is (string= "a || (b && c)" (car (bin t1 :or (leaf "a") (bin t1 :and (leaf "b") (leaf "c"))))))))

(test full-mode-is-oracle
  (is (string= "a + (b * c)" (car (bin *c-table* :add (leaf "a") (bin *c-table* :mul (leaf "b") (leaf "c") :full) :full)))))

(test unary-and-negative-literals
  (is (string= "-(-x)" (unary-string *c-table* :neg (cons "-x" :neg) :minimal)))
  (is (string= "-(a + b)" (unary-string *c-table* :neg (cons "a + b" :add) :minimal)))
  (is (string= "(-5)" (postfix-receiver *c-table* (cons "-5" :neg-literal) :minimal)))
  (is (string= "x" (postfix-receiver *c-table* (leaf "x") :minimal)))
  (is (string= "not a < b" (unary-string *py-table* :not (cons "a < b" :lt) :minimal)) "python not binds looser than <")
  (is (eq :neg-literal (literal-op -3)))
  (is (eq :neg-literal (literal-op -0d0)))
  (is (null (literal-op 3))))

(test string-escaping
  (let ((s (format nil "a\"b\\c~%d~ae~af" #\Tab (code-char 0))))
    (is (string= "a\\\"b\\\\c\\nd\\te\\000f" (escape-string s :c)))
    (is (string= "a\\\"b\\\\c\\nd\\te\\x00f" (escape-string s :python)))
    (is (string= "a\\\"b\\\\c\\nd\\te\\x00f" (escape-string s :rust))))
  (is (string= "ä😀" (escape-string "ä😀" :rust)))
  (is (string= "\\u{e4}\\u{1f600}" (escape-string "ä😀" :rust :ascii-only t)))
  (is (string= "\\u00e4\\U0001f600" (escape-string "ä😀" :python :ascii-only t)))
  (is (string= "'\\''" (char-literal #\' :c))))

(test float-round-trip
  (is (string= "0.1" (float-literal 0.1d0)))
  (is (string= "1.0e300" (float-literal 1d300)))
  (is (string= "-0.0" (float-literal -0d0)))
  (is (string= "1.0" (float-literal 1d0)))
  (dolist (f '(0.1d0 1d300 -0d0 1d0 3.141592653589793d0 1d-7))
    (is (= f (let ((*read-default-float-format* 'double-float)) (read-from-string (float-literal f)))))))

(test writer
  (is (string= (format nil "a {~%    b~%    c~%}~%")
               (with-output-lines ()
                 (with-block ("a {" "}") (emit-line "b") (emit-line "c")))))
  (is (string= (format nil "x~%~%y~%")
               (with-output-lines () (emit-line "x") (emit-blank-line) (emit-blank-line) (emit-line "y")
                                  (emit-blank-line))))
  (is (string= (format nil "  a~%  b~%")
               (with-output-lines (:unit "  ") (with-indent () (emit-line (format nil "a~%b")))))))
