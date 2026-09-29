;;;; test-expr.lisp --- tests of the expression parser (21-expr*.lisp)

(in-package :polyglot.tests)

(def-suite :polyglot.unit.expr :in :polyglot.unit)
(in-suite :polyglot.unit.expr)

(defun pe (string) (parse-expr (read-dsl string)))

(test literals
  (is (eq :int (ir-kind (pe "42"))))
  (is (eq :float (ir-kind (pe "1.5"))))
  (is (eq :float (ir-kind (pe "1d0"))))
  (is (eq :string (ir-kind (pe "\"hi\""))))
  (is (eq :char (ir-kind (pe "#\\a"))))
  (is (eq :bool (ir-kind (pe "true"))))
  (is (eq nil (ir-value (pe "false"))))
  (is (eq :nil (ir-kind (pe "nil"))))
  (signals dsl-error (parse-expr 1.5f0))
  (signals dsl-error (pe ":foo"))
  (signals dsl-error (pe "t")))

(test operators-map-to-keywords
  (loop for (src op) in '(("(+ a b)" :add) ("(- a b)" :sub) ("(* a b)" :mul)
                          ("(/ a b)" :div) ("(= a b)" :eq) ("(/= a b)" :ne)
                          ("(< a b)" :lt) ("(<= a b)" :le) ("(> a b)" :gt)
                          ("(>= a b)" :ge) ("(and a b)" :and) ("(or a b)" :or)
                          ("(not a)" :not) ("(logand a b)" :bitand)
                          ("(logior a b)" :bitor) ("(logxor a b)" :bitxor)
                          ("(lognot a)" :bitnot) ("(shl a b)" :shl) ("(shr a b)" :shr))
        do (is (eq op (ir-op (pe src))) "~a" src)))

(test unary-minus-and-folding
  (is (eq :neg (ir-op (pe "(- x)"))))
  (let ((e (pe "(+ a b c)")))
    (is (eq :add (ir-op e)))
    (is (eq :add (ir-op (first (ir-args e)))))
    (is (string= "c" (ir-name (second (ir-args e))))))
  (is (typep (pe "(+ a)") 'var-expr))
  (signals dsl-error (pe "(< a b c)"))
  (signals dsl-error (pe "(/ a)")))

(test dot-chain
  (let ((e (pe "(dot a b c)")))
    (is (typep e 'field-expr))
    (is (string= "c" (ir-name e)))
    (is (string= "b" (ir-name (ir-object e))))
    (is (string= "a" (ir-name (ir-object (ir-object e)))))))

(test calls-make-and-forms
  (let ((e (pe "(f (g x) 1)")))
    (is (typep e 'call-expr))
    (is (string= "f" (ir-name e)))
    (is (typep (first (ir-args e)) 'call-expr)))
  (let ((m (pe "(make-point :x 1d0 :y 2d0)")))
    (is (typep m 'make-expr))
    (is (string= "point" (ir-type-name m)))
    (is (equal '("x" "y") (mapcar #'ir-name (ir-inits m)))))
  (is (typep (pe "(aref v 0)") 'aref-expr))
  (is (typep (pe "(if c 1 2)") 'if-expr))
  (is (typep (pe "(let ((x 1)) (+ x 1))") 'block-expr))
  (is (typep (pe "(cond ((> x 0) 1) (t 2))") 'if-expr))
  (is (equal '(:vec :i64) (list :vec (ir-elem-type (pe "(vec-of :int 1 2)")))))
  (is (eq :box (ir-kind (pe "(box (make-circle :r 1d0))"))))
  (is (typep (pe "(lambda (a) (declare (type :int a)) (+ a 1))") 'lambda-expr))
  (is (typep (pe "(cpp::raw \"x\")") 'target-form-expr)))

(test error-carries-source-form
  (let ((c (handler-case (pe "(if c 1)") (dsl-error (e) e))))
    (is (equal (read-dsl "(if c 1)") (dsl-error-form c)))))
