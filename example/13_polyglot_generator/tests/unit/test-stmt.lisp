;;;; test-stmt.lisp --- tests of the statement parser (22-stmt*.lisp)

(in-package :polyglot.tests)

(def-suite :polyglot.unit.stmt :in :polyglot.unit)
(in-suite :polyglot.unit.stmt)

(defun ps (string) (parse-stmt (read-dsl string)))

(test statement-kinds
  (loop for (src class) in
        '(("(let ((x 1)) (print-line x))" block-stmt)
          ("(let* ((x 1) (y x)) y)" block-stmt)
          ("(setf x 1)" assign-stmt)
          ("(setf x 1 y 2)" block-stmt)
          ("(incf x)" incf-stmt) ("(decf x 2)" incf-stmt)
          ("(if c (f) (g))" if-stmt) ("(when c (f))" when-stmt)
          ("(unless c (f))" when-stmt) ("(cond (a (f)) (t (g)))" cond-stmt)
          ("(while c (f))" while-stmt) ("(dotimes (i 3) (f i))" dotimes-stmt)
          ("(dolist (x v) (f x))" for-each-stmt) ("(return 1)" return-stmt)
          ("(return)" return-stmt) ("(break)" break-stmt) ("(continue)" continue-stmt)
          ("(progn (f) (g))" block-stmt) ("(if-let (x (map-get m k)) (f x))" if-let-stmt)
          ("(comment \"a\")" comment-stmt) ("(raw \"x;\")" raw-stmt)
          ("(target-case (:cpp (f)) (t (g)))" target-case-stmt)
          ("(f 1)" expr-stmt))
        do (is (typep (ps src) class) "~a -> ~a" src class)))

(test let-structure
  (let ((b (ps "(let ((x 1) (y 2)) (declare (type :i64 x)) (f x y))")))
    (is (eq t (ir-scope b)))
    (is (= 3 (length (ir-stmts b))))
    (is (eq :i64 (ir-declared-ty (ir-var (first (ir-stmts b))))))
    (is (null (ir-declared-ty (ir-var (second (ir-stmts b))))))))

(test nested-statements
  (let ((s (ps "(dolist (x v) (when (> x 0) (incf n x)))")))
    (is (typep (first (ir-body s)) 'when-stmt))
    (is (typep (first (ir-body (first (ir-body s)))) 'incf-stmt))))

(test comments-split-lines
  (is (equal '("a" "b") (ir-lines (ps "(comments \"a\" \"b\")")))))

(test statement-errors
  (signals dsl-error (ps "(setf x)"))
  (signals dsl-error (ps "(setf x 1 y)"))
  (signals dsl-error (ps "(setf (f x) 1)"))
  (signals dsl-error (ps "(cond)"))
  (signals dsl-error (ps "(let ((x 1) (y x)) y)"))
  (signals dsl-error (ps "(let ((x 1)) (declare (type :i64 z)) x)"))
  (signals dsl-error (ps "(dotimes i (f))")))
