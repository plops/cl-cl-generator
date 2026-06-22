(eval-when (:compile-toplevel :execute :load-toplevel)
  ;; Setup the registry path relative to this file so it can load the cl-cl-generator system.
  (let ((current-dir (make-pathname :directory (pathname-directory *load-pathname*))))
    (push (merge-pathnames "../../" current-dir) asdf:*central-registry*)
    (push (merge-pathnames "../../../cl-py-generator/" current-dir) asdf:*central-registry*))
  (ql:quickload '(:cl-cl-generator :cl-py-generator :jonathan :cl-ppcre)))

(defpackage :cl-cl-generator/example-py-meta
  (:use :cl :cl-cl-generator))

(in-package :cl-cl-generator/example-py-meta)

;; =========================================================================
;; Helper functions to reduce boilerplate in generated S-expressions
;; =========================================================================

(defun make-fmt-clause (op prefix suffix separator)
  "Formats a list of elements separated by a delimiter, wrapped inside a prefix and suffix.
For example, (make-fmt-clause 'paren \"(\" \")\" \", \") expands to:
  (paren (let ((args (cdr code)))
           (format nil \"(~{~a~^, ~})\" (mapcar #'emit args))))"
  `(,op (let ((args (cdr code)))
          (format nil ,(format nil "~a~~{~~a~~^~a~~}~a" prefix separator suffix)
                  (mapcar #'emit args)))))

(defun make-relation-clause (op py-op)
  "Formats simple Python binary relations (e.g., identity and membership tests).
For example, (make-relation-clause 'in \"in\") expands to:
  (in (destructuring-bind (a b) (cdr code)
        (format nil \"(~a in ~a)\" (emit a) (emit b))))"
  `(,op (destructuring-bind (a b) (cdr code)
          (format nil ,(format nil "(~~a ~a ~~a)" py-op) (emit a) (emit b)))))

(defun make-assignment-op-clause (op op-str)
  "Formats Python assignment operators (e.g., target += val).
For example, (make-assignment-op-clause 'incf \"+=\") expands to:
  (incf (destructuring-bind (target &optional (val 1)) (cdr code)
          (format nil \"~a += ~a\" (emit target) (emit val))))"
  `(,op (destructuring-bind (target &optional (val 1)) (cdr code)
          (format nil ,(format nil "~~a ~a ~~a" op-str) (emit target) (emit val)))))

(defun make-binary-op-clause (op py-op)
  "Formats mathematical operations limited strictly to two operands (e.g. pow, mod, floor-div).
Operands are optionally parenthesized to satisfy python operator precedence checks.
For example, (make-binary-op-clause '** \"**\") expands to:
  (** (let ((args (cdr code)))
        (if omit-redundant-parentheses
            (format nil \"~a**~a\" (emit `(paren* ** ,(first args))) (emit `(paren* ** ,(second args))))
            (format nil \"((~a)**(~a))\" (emit (first args)) (emit (second args))))))"
  `(,op (let ((args (cdr code)))
          (if omit-redundant-parentheses
              (format nil ,(format nil "~~a~a~~a" py-op)
                      (emit `(paren* ,',op ,(first args)))
                      (emit `(paren* ,',op ,(second args))))
              (format nil ,(format nil "((~~a)~a(~~a))" py-op)
                      (emit (first args))
                      (emit (second args)))))))

(defun make-unary-op-clause (op py-op &key space)
  "Formats Python unary operations (e.g. bitwise not '~', logical 'not').
Tildes (~) in the prefix are automatically escaped to '~~' to prevent Common Lisp format warnings.
For example, (make-unary-op-clause 'not \"not\" :space t) expands to:
  (not (destructuring-bind (arg) (cdr code)
         (if omit-redundant-parentheses
             (format nil \"not ~a\" (emit `(paren* not ,arg)))
             (format nil \"(not ~a)\" (emit arg)))))"
  (let* ((sep (if space " " ""))
         (escaped-py-op (cl-ppcre:regex-replace-all "~" py-op "~~"))
         (fmt-omit (format nil "~a~a~~a" escaped-py-op sep))
         (fmt-keep (format nil "(~a~a~~a)" escaped-py-op sep)))
    `(,op (destructuring-bind (arg) (cdr code)
            (if omit-redundant-parentheses
                (format nil ,fmt-omit (emit `(paren* ,',op ,arg)))
                (format nil ,fmt-keep (emit arg)))))))

(defun make-string-clause (op format-str)
  "Formats Python string literals (including prefix modifiers like f-strings, byte-strings, and multi-line raw blocks).
For example, (make-string-clause 'fstring \"f\\\"~a\\\"\") expands to:
  (fstring (format nil \"f\\\"~a\\\"\" (cadr code)))"
  `(,op (format nil ,format-str (cadr code))))

(defun make-op-clause (op py-op &key spaces)
  "Formats mathematical and logical n-ary operations that support variable arguments (e.g. +, *, and, or).
Delimiter separator string optionally pads spaces on both sides.
For example, (make-op-clause '+ \"+\") expands to:
  (+ (let ((args (cdr code)))
       (if omit-redundant-parentheses
           (format nil \"~{~a~^+~}\" (mapcar #'(lambda (x) (emit `(paren* + ,x))) args))
           (format nil \"(~{(~a)~^+~})\" (mapcar #'emit args)))))"
  (let* ((sep (if spaces (format nil " ~a " py-op) py-op))
         (fmt-omit (format nil "~~{~~a~~^~a~~}" sep))
         (fmt-keep (format nil "(~~{(~~a)~~^~a~~})" sep)))
    `(,op (let ((args (cdr code)))
            (if omit-redundant-parentheses
                (format nil ,fmt-omit (mapcar #'(lambda (x) (emit `(paren* ,',op ,x))) args))
                (format nil ,fmt-keep (mapcar #'emit args)))))))

(let* ((output-dir (asdf:system-relative-pathname :cl-cl-generator "example/03_py_meta/"))
       (output-filename "py")
       (code
         `(toplevel
            (in-package :cl-py-generator)

            (defun write-notebook (&key nb-file nb-code)
              "Writes a notebook to a file.

    The notebook is written in JSON format and formatted using the jq tool.
    
	Args:
		nb-file (string): The path to the notebook file.
		nb-code (string): The code to be written to the notebook.

	Returns:
		None"
              (let ((tmp (format nil "~a.tmp" nb-file)))
                (with-output-to-file (s tmp :if-exists :supersede
                                        :if-does-not-exist :create)
                  (format s "~a~%"
                          (jonathan:to-json
                           `(:cells
                             ,(loop for e in nb-code
                                    collect
                                    (destructuring-bind (name &rest rest) e
                                      (case name
                                        (markdown `(:cell_type "markdown"
                                                    :metadata :empty
                                                    :source
                                                    ,(loop for p in rest
                                                           collect
                                                           (format nil "~a~c" p #\Newline))))
                                        (python `(:cell_type "code"
                                                  :metadata :empty
                                                  :execution_count :null
                                                  :outputs ()
                                                  :source
                                                  ,(loop for p in rest
                                                         appending
                                                         (let ((tempfn (raw "#+sbcl \"/dev/shm/cell\" #+ecl (format nil \"~a_tmp_cell\" nb-file)")))
                                                           (write-source tempfn p)
                                                           (with-open-file (stream (format nil "~a.py" tempfn))
                                                             (loop for line = (read-line stream nil)
                                                                   while line
                                                                   collect
                                                                   (format nil "~a~c" line #\Newline))))))))))
                             (raw "#+nil (:|metadata| (:|kernelspec| (:|display_name| \"Python 3\" :|language| \"python\" :|name| \"python3\") :|nbformat| 4 :|nbformat_minor| 2))")
                             :metadata (:kernelspec (:display_name "Python 3"
                                                     :language "python"
                                                     :name "python3"))
                             :nbformat 4
                             :nbformat_minor 2))))
                (raw "#-sbcl (external-program:run \"/usr/bin/jq\" `(\"-M\" \".\" ,tmp) :output nb-file :if-output-exists :supersede)")
                (raw "#+sbcl (sb-ext:run-program \"/usr/bin/jq\" `(\"-M\" \".\" ,tmp) :output nb-file :if-output-exists :supersede)")
                (delete-file tmp)))

            (setf (readtable-case *readtable*) :invert)

            (defparameter *warn-breaking* t)
            (defparameter *file-hashes* (make-hash-table))

            (defun consume-declare (body)
              "Take a list of instructions from `body`, parse type declarations,
return the `body` without them and a hash table with an environment. The
entry `return-values` contains a list of return values. Currently supports `type`, `values`."
              (let ((env (make-hash-table))
                    (looking-p t)
                    (new-body nil))
                (loop for e in body do
                      (if looking-p
                          (if (listp e)
                              (if (eq (car e) 'declare)
                                  (loop for declaration in (cdr e) do
                                        (when (eq (first declaration) 'type)
                                          (destructuring-bind (symb type &rest vars) declaration
                                            (declare (ignorable symb))
                                            (loop for var in vars do
                                                  (setf (gethash var env) type))))
                                        (when (eq (first declaration) 'capture)
                                          (destructuring-bind (symb &rest vars) declaration
                                            (declare (ignorable symb))
                                            (loop for var in vars do
                                                  (push var captures))))
                                        (when (eq (first declaration) 'values)
                                          (destructuring-bind (symb &rest types-opt) declaration
                                            (declare (ignorable symb))
                                            (let ((types nil))
                                              (loop for type in types-opt do
                                                    (unless (eq #\& (aref (format nil "~a" type) 0))
                                                      (push type types)))
                                              (setf (gethash 'return-values env) (reverse types))))))
                                  (progn
                                    (push e new-body)
                                    (setf looking-p nil)))
                              (progn
                                (setf looking-p nil)
                                (push e new-body)))
                          (push e new-body)))
                (values (reverse new-body) env)))

            (defun parse-defun (code emit)
              "Parse a defun expression and generate Python code.
    
    This function parses a DEFUN s-expression form and emits Python code. Optionally, it can insert type hints for parameters and the return value."
              (destructuring-bind (name lambda-list &rest body) (cdr code)
                (multiple-value-bind (body env) (consume-declare body)
                  (multiple-value-bind (req-param opt-param res-param
                                        key-param other-key-p
                                        aux-param key-exist-p)
                      (parse-ordinary-lambda-list lambda-list)
                    (declare (ignorable req-param opt-param res-param
                                        key-param other-key-p aux-param key-exist-p))
                    (with-output-to-string (s)
                      (format s "def ~a~a~@[->~a~]:~%"
                              name
                              (funcall emit `(paren
                                              ,@(loop for p in req-param collect
                                                      (format nil "~a~@[: ~a~]"
                                                              p
                                                              (let ((type (gethash p env)))
                                                                (when type
                                                                  (funcall emit type)))))
                                              ,@(loop for ((keyword-name name) init supplied-p) in key-param
                                                      collect
                                                      (progn
                                                        (format nil "~a~a ~@[~a~]"
                                                                name
                                                                (let ((type (gethash name env)))
                                                                  (if type
                                                                      (format nil ": ~a" (funcall emit type))
                                                                      ""))
                                                                (format nil "= ~a" (funcall emit init)))))))
                      (let ((r (gethash 'return-values env)))
                                (if (< 1 (length r))
                                    (break "multiple return values unsupported: ~a" r)
                                    (if (car r)
                                        (case (car r)
                                          (:constructor "")
                                          (t (car r)))
                                        nil))))
                      (format s "~a" (funcall emit `(do ,@body))))))))

            (defun write-source (name code &optional (dir (user-homedir-pathname)) ignore-hash)
              "Writes the Python source code to a file."
              (let* ((fn (merge-pathnames (format nil "~a.py" name) dir))
                     (code-str (emit-py :clear-env t :code code))
                     (fn-hash (sxhash fn))
                     (code-hash (sxhash code-str)))
                (multiple-value-bind (old-code-hash exists) (gethash fn-hash *file-hashes*)
                  (when (or (not exists) ignore-hash (/= code-hash old-code-hash))
                    (setf (gethash fn-hash *file-hashes*) code-hash)
                    (with-open-file (s fn :direction :output :if-exists :supersede :if-does-not-exist :create)
                      (write-sequence code-str s))
                    (raw "#+nil (sb-ext:run-program \"/usr/bin/autopep8\" (list \"--max-line-length 80\" (namestring fn)))")
                    (sb-ext:run-program "/snap/bin/uvx" (list "ruff" "format" (namestring fn)))
                    (raw "#+nil (sb-ext:run-program \"/usr/bin/yapf\" (list \"-i\" (namestring fn)))")
                    (raw "#+nil (progn (sb-ext:run-program \"/home/martin/.local/bin/black\" (list \"--fast\" (namestring fn))))")))))

            (defun print-sufficient-digits-f64 (f)
              "Prints a double floating point number as a string with a given number of digits.
	 Parses the string representation and increases the number of digits until the same bit pattern is obtained."
              (let* ((a f)
                     (digits 1)
                     (b (- a 1))
                     (threshold (if (typep f 'double-float) 1d-12 1e-7))
                     (*read-default-float-format* (if (typep f 'double-float) 'double-float 'single-float)))
                (unless (= a 0)
                  (loop while (< threshold (/ (abs (- a b)) (abs a)))
                        do (setf b (read-from-string (format nil "~,vG" digits a)))
                           (incf digits)))
                (substitute #\e #\d (format nil "~,vG" (max 1 (1- digits)) a))))

            (defparameter *precedence*
              `((:op (paren paren* dict list tuple curly aref dot) :assoc l)
                (:op (**) :assoc r)
                (:op (unary- unary+ ~) :assoc r)
                (:op (* @ / // %) :assoc l)
                (:op (+ -) :assoc l)
                (:op (<< >>) :assoc l)
                (:op (& logand) :assoc l)
                (:op (^ logxor) :assoc l)
                (:op (|\|| logior) :assoc l)
                (:op (< <= > >= != == in not-in is is-not) :assoc l)
                (:op (not) :assoc r)
                (:op (and) :assoc l)
                (:op (or) :assoc l)
                (:op (? ternary) :assoc r)
                (:op (= setf) :assoc r)))

            (defparameter *operators*
              (loop for e in *precedence* append (getf e :op)))

            (defun lookup-precedence (operator)
              (loop for e in *precedence* and e-i from 0
                    do (destructuring-bind (&key op assoc) e
                         (declare (ignore assoc))
                         (when (member operator op)
                           (return e-i)))))

            (defun lookup-associativity (operator)
              (loop for e in *precedence*
                    do (destructuring-bind (&key op (assoc 'l)) e
                         (declare (ignore op))
                         (when (member operator op)
                           (return assoc)))))

            (defparameter *env-functions* nil)
            (defparameter *env-macros* nil)

            (defun emit-py (&key code (str nil) (clear-env nil) (level 0) (omit-redundant-parentheses t))
              "Emit Python code based on the given parameters."
              (when clear-env
                (setf *env-functions* nil
                      *env-macros* nil))
              (flet ((emit (code &optional (dl 0))
                       (emit-py :code code :clear-env nil :level (+ dl level) :omit-redundant-parentheses omit-redundant-parentheses)))
                (if code
                    (if (listp code)
                        (case (car code)
                          ;; Factor standard formatting functions using generation-time helpers
                          ,(make-fmt-clause 'paren "(" ")" ", ")
                          ,(make-fmt-clause 'ntuple "" "" ", ")
                          ,(make-fmt-clause 'list "[" "]" ", ")
                          ,(make-fmt-clause 'curly "{" "}" ", ")
                          
                          (tuple (let ((args (cdr code)))
                                   (format nil "(~{~a,~})" (mapcar #'emit args))))
                          
                          (dict (let* ((args (cdr code)))
                                  (format nil "{~{~{(~a):(~a)~}~^, ~}}"
                                          (loop for (k v) in args
                                                collect (list (emit k) (emit v))))))
                          (dictionary (let* ((args (cdr code)))
                                        (format nil "dict~a"
                                                (emit `(paren ,@(loop for (e f) on args by #'cddr
                                                                      collect `(= ,e ,f)))))))
                          (indent (format nil "~{~a~}~a"
                                          (loop for i below level collect "    ")
                                          (emit (cadr code))))
                          (do (with-output-to-string (s)
                                (format s "~{~&~a~}" (mapcar #'(lambda (x) (emit `(indent ,x) 1)) (cdr code)))))
                          (class (destructuring-bind (name parents &rest body) (cdr code)
                                   (format nil "class ~a~a:~%~a"
                                           name
                                           (if (eq 0 (length parents))
                                               ""
                                               (emit `(paren ,@parents)))
                                           (emit `(do ,@body)))))
                          (cl-py-generator:do0 (with-output-to-string (s)
                                                 (format s "~&~a~{~&~a~}"
                                                         (emit (cadr code))
                                                         (mapcar #'(lambda (x) (emit `(indent ,x) 0)) (cddr code)))))
                          (cell (with-output-to-string (s)
                                  (format s "~a~%"
                                          (emit `(cl-py-generator:do0 (cl-py-generator:comments "export")
                                                                      ,@(cdr code))))))
                          (export (with-output-to-string (s)
                                    (format s "~a~%"
                                            (emit `(cl-py-generator:do0 (cl-py-generator:comments "|export")
                                                                        ,@(cdr code))))))
                          (space (with-output-to-string (s)
                                   (format s "~{~a~^ ~}"
                                           (mapcar #'(lambda (x) (emit x)) (cdr code)))))
                          (lambda (destructuring-bind (lambda-list &rest body) (cdr code)
                                    (multiple-value-bind (req-param opt-param res-param
                                                          key-param other-key-p aux-param key-exist-p)
                                        (parse-ordinary-lambda-list lambda-list)
                                      (declare (ignorable req-param opt-param res-param
                                                          key-param other-key-p aux-param key-exist-p))
                                      (with-output-to-string (s)
                                        (format s "lambda ~a: ~a"
                                                (emit `(ntuple ,@(append req-param
                                                                         (loop for e in key-param collect
                                                                               (destructuring-bind ((keyword-name name) init suppliedp)
                                                                                   e
                                                                                 (declare (ignorable keyword-name suppliedp))
                                                                                 (if init
                                                                                     `(= ,(emit name) ,init)
                                                                                     `(= ,(emit name) "None")))))))
                                                (if (cdr body)
                                                    (break "body ~a should have only one entry" body)
                                                    (emit (car body))))))))
                          (def (parse-defun code #'emit))
                          (= (destructuring-bind (a b) (cdr code)
                               (format nil "~a=~a" (emit a) (emit b))))
                          
                          ;; Factor relational operator list using generation-time helpers
                          ,@(mapcar (lambda (args) (apply #'make-relation-clause args))
                                    '((in "in") (not-in "not in") (is "is") (is-not "is not")))
                          
                          (as (destructuring-bind (a b) (cdr code)
                                (format nil "~a as ~a" (emit a) (emit b))))
                          (setf (let ((args (cdr code)))
                                  (format nil "~a"
                                          (emit `(cl-py-generator:do0 ,@(loop for i below (length args) by 2 collect
                                                                              (let ((a (elt args i))
                                                                                    (b (elt args (+ 1 i))))
                                                                                `(= ,a ,b))))))))
                          
                          ;; Factor assignment operators using generation-time helpers
                          ,@(mapcar (lambda (args) (apply #'make-assignment-op-clause args))
                                    '((incf "+=") (decf "-=")))
                          
                          (aref (destructuring-bind (name &rest indices) (cdr code)
                                  (format nil "~a[~{~a~^,~}]" (emit name) (mapcar #'emit indices))))
                          (slice (let ((args (cdr code)))
                                   (if (null args)
                                       (format nil ":")
                                       (format nil "~{~a~^:~}" (mapcar #'emit args)))))
                          (dot (let ((args (cdr code)))
                                 (format nil "~{~a~^.~}" (mapcar #'emit (remove-if #'null args)))))
                          (paren*
                           (if (not omit-redundant-parentheses)
                               (destructuring-bind (parent-op &rest args) (cdr code)
                                 (declare (ignore parent-op))
                                 (format nil "(~{~a~^, ~})" (mapcar #'emit args)))
                               (progn
                                 (unless (eq 3 (length code))
                                   (break "paren* expects only two arguments: ~a" code))
                                 (destructuring-bind (parent-op arg &rest rest) (cdr code)
                                   (declare (ignore rest))
                                   (cond
                                     ((symbolp arg) (format nil "~a" (emit arg)))
                                     ((numberp arg) (if (<= 0 arg) (format nil "~a" (emit arg)) (format nil " ~a" (emit arg))))
                                     ((stringp arg) (format nil "~a" arg))
                                     ((listp arg)
                                      (cond
                                        ((<= (length arg) 2)
                                         (let ((op0 (car arg)) (rest (cdr arg)))
                                           (assert (or (symbolp op0) (stringp op0)))
                                           (assert (listp rest))
                                           (emit `(,op0 ,@rest))))
                                        (t
                                         (let ((op0 parent-op) (rest (cdr arg)))
                                           (assert (or (symbolp op0) (stringp op0)))
                                           (assert (listp rest))
                                           (if (and (member op0 *operators*) (member (car arg) *operators*))
                                               (let* ((p0 (lookup-precedence op0))
                                                      (p0assoc (lookup-associativity op0))
                                                      (op1 (car arg))
                                                      (p1 (lookup-precedence op1))
                                                      (p1assoc (lookup-associativity op1)))
                                                 (if (or (< p0 p1)
                                                         (and (eq p0 p1) (not (eq p0assoc p1assoc)))
                                                         (member op0 '(/ // % - **))
                                                         (member op1 '(/ // % - **)))
                                                     (format nil "(~a)" (emit `(,op1 ,@rest)))
                                                     (format nil "~a" (emit `(,op1 ,@rest)))))
                                               (emit `(,(car arg) ,@rest)))))))
                                     (t (break "unsupported argument for paren* '~a' type='~a'" arg (type-of arg))))))))
                          
                          ;; Factor binary-only operators using generation-time helpers
                          ,@(mapcar (lambda (args) (apply #'make-binary-op-clause args))
                                    '((** "**") (// "//") (% "%")))
                          
                          ;; Factor unary operators using generation-time helpers
                          ,(make-unary-op-clause 'not "not" :space t)
                          ,(make-unary-op-clause '~ "~")
                          
                          ;; Factor string clauses using generation-time helpers
                          ,@(mapcar (lambda (args) (apply #'make-string-clause args))
                                    '((string "\"~a\"")
                                      (string-b "b\"~a\"")
                                      (string3 "\"\"\"~a\"\"\"")
                                      (rstring3 "r\"\"\"~a\"\"\"")))
                           
                          (fstring (let ((args (cdr code)))
                                     (format nil "f\"~{~a~}\""
                                             (mapcar (lambda (x)
                                                       (if (stringp x)
                                                           x
                                                           (format nil "{~a}" (emit x))))
                                                     args))))
                          (fstring3 (let ((args (cdr code)))
                                      (format nil "f\"\"\"~{~a~}\"\"\""
                                              (mapcar (lambda (x)
                                                        (if (stringp x)
                                                            x
                                                            (format nil "{~a}" (emit x))))
                                                      args))))
                           
                          (decorator (destructuring-bind (dec) (cdr code)
                                       (if (listp dec)
                                           (format nil "@~a~%" (emit dec))
                                           (format nil "@~a~%" dec))))
                          (decorated (destructuring-bind (decs definition) (cdr code)
                                       (with-output-to-string (s)
                                         (loop for dec in decs
                                               do (if (listp dec)
                                                      (format s "@~a~%" (emit dec))
                                                      (format s "@~a~%" dec)))
                                         (format s "~a" (emit definition)))))
                          (yield (let ((args (cdr code)))
                                   (if args
                                       (format nil "yield ~a" (emit (car args)))
                                       "yield")))
                          (yield-from (destructuring-bind (val) (cdr code)
                                        (format nil "yield from ~a" (emit val))))
                          (assert (destructuring-bind (condition &optional message) (cdr code)
                                    (if message
                                        (format nil "assert ~a, ~a" (emit condition) (emit message))
                                        (format nil "assert ~a" (emit condition)))))
                          
                          ;; Factor N-ary mathematical & logical operators using generation-time helpers
                          ,@(mapcar (lambda (args) (apply #'make-op-clause args))
                                    '((+ "+") (* "*") (@ "@") (== "==") (<< "<<") (!= "!=") (< "<") (> ">") (<= "<=") (>= ">=") (>> ">>")
                                      (& "&" :spaces t) (logand "&" :spaces t) (logxor "^" :spaces t)
                                      (|\|| "|" :spaces t) (^ "^" :spaces t) (logior "|" :spaces t)
                                      (and "and" :spaces t) (or "or" :spaces t)))
                          
                          ;; Handle minus specifically
                          (- (let ((args (cdr code)))
                               (if omit-redundant-parentheses
                                   (if (eq 1 (length args))
                                       (format nil "-~a" (emit `(paren* unary- ,(car args))))
                                       (format nil "~{~a~^-~}" (mapcar #'(lambda (x) (emit `(paren* - ,x))) args)))
                                   (format nil "(~{(~a)~^-~})" (mapcar #'emit args)))))
                          
                          ;; Handle division specifically
                          (/ (let ((args (cdr code)))
                               (if omit-redundant-parentheses
                                   (if (eq 1 (length args))
                                       (format nil "1.0/~a" (emit `(paren* / ,(car args))))
                                       (format nil "~a/~a" (emit `(paren* / ,(first args))) (emit `(paren* / ,(second args)))))
                                   (format nil "((~a)/(~a))" (emit (first args)) (emit (second args))))))
                          
                          (comment (format nil "# ~a~%" (cadr code)))
                          (comments (let ((args (cdr code)))
                                      (format nil "~{# ~a~%~}"
                                              (mapcar #'(lambda (arg)
                                                          (cl-ppcre:regex-replace-all "\\n" arg (format nil "~%# ")))
                                                      args))))
                          (symbol (substitute #\: #\- (format nil "~a" (cadr code))))
                          (return_ (format nil "return ~a" (emit (caadr code))))
                          (return (let ((args (cdr code)))
                                    (format nil "~a" (emit `(return_ ,args)))))
                          (for (destructuring-bind ((vs ls) &rest body) (cdr code)
                                 (with-output-to-string (s)
                                   (format s "for ~a in ~a:~%" (emit vs) (emit ls))
                                   (format s "~a" (emit `(do ,@body))))))
                          (for-generator (destructuring-bind ((vs ls) expr) (cdr code)
                                           (format nil "~a for ~a in ~a" (emit expr) (emit vs) (emit ls))))
                          (while (destructuring-bind (vs &rest body) (cdr code)
                                   (with-output-to-string (s)
                                     (if omit-redundant-parentheses
                                         (format s "while ~a:~%" (emit vs))
                                         (format s "while ~a:~%" (emit `(paren ,vs))))
                                     (format s "~a" (emit `(do ,@body))))))
                          (if (destructuring-bind (condition true-statement &optional false-statement) (cdr code)
                                (with-output-to-string (s)
                                  (if omit-redundant-parentheses
                                      (format s "if ~a:~%~a" (emit condition) (emit `(do ,true-statement)))
                                      (format s "if ( ~a ):~%~a" (emit condition) (emit `(do ,true-statement))))
                                  (when false-statement
                                    (format s "~&~a:~%~a" (emit `(indent "else")) (emit `(do ,false-statement)))))))
                          (cond (destructuring-bind (&rest clauses) (cdr code)
                                  (with-output-to-string (s)
                                    (loop for clause in clauses and i from 0
                                          do (destructuring-bind (condition &rest statements) clause
                                               (format s "~&~a:~%~a"
                                                       (cond ((and (eq condition 't) (eq i 0))
                                                              (if omit-redundant-parentheses "if True" "if ( True )"))
                                                             ((eq i 0)
                                                              (if omit-redundant-parentheses
                                                                  (format nil "if ~a" (emit condition))
                                                                  (format nil "if ( ~a )" (emit condition))))
                                                             ((eq condition 't) (emit `(indent "else")))
                                                             (t (emit `(indent ,(if omit-redundant-parentheses
                                                                                   (format nil "elif ~a" (emit condition))
                                                                                   (format nil "elif ( ~a )" (emit condition)))))))
                                                       (emit `(do ,@statements))))))))
                          (? (destructuring-bind (condition true-statement &optional (false-statement "None" false-statement-supplied-p)) (cdr code)
                               (if omit-redundant-parentheses
                                   (if false-statement-supplied-p
                                       (format nil "~a if ~a else ~a"
                                               (emit `(paren* ternary ,true-statement))
                                               (emit `(paren* ternary ,condition))
                                               (emit `(paren* ternary ,false-statement)))
                                       (format nil "~a if ~a"
                                               (emit `(paren* ternary ,true-statement))
                                               (emit `(paren* ternary ,condition))))
                                   (if false-statement-supplied-p
                                       (format nil "(~a) if (~a) else (~a)" (emit true-statement) (emit condition) (emit false-statement))
                                       (format nil "~a if (~a)" (emit true-statement) (emit condition))))))
                          (when (destructuring-bind (condition &rest forms) (cdr code)
                                  (emit `(if ,condition (cl-py-generator:do0 ,@forms)))))
                          (unless (destructuring-bind (condition &rest forms) (cdr code)
                                    (emit `(if (not ,condition) (cl-py-generator:do0 ,@forms)))))
                          (import-from (destructuring-bind (module &rest rest) (cdr code)
                                         (format nil "from ~a import ~{~a~^, ~}" (emit module) (mapcar #'emit rest))))
                          (imports-from (destructuring-bind (&rest module-defs) (cdr code)
                                          (with-output-to-string (s)
                                            (loop for e in module-defs
                                                  do (format s "~a~%" (emit `(import-from ,@e)))))))
                          (import (destructuring-bind (args) (cdr code)
                                    (if (listp args)
                                        (format nil "import ~a as ~a~%" (second args) (first args))
                                        (format nil "import ~a~%" args))))
                          (imports (destructuring-bind (args) (cdr code)
                                     (format nil "~{~a~}" (append (list (emit `(import ,(first args))))
                                                                  (mapcar #'(lambda (x) (emit `(indent (import ,x)))) (rest args))))))
                          (with (destructuring-bind (form &rest body) (cdr code)
                                  (with-output-to-string (s)
                                    (format s "~a~a:~%~a" (emit "with ") (emit form) (emit `(do ,@body))))))
                          (try (destructuring-bind (prog &rest exceptions) (cdr code)
                                 (with-output-to-string (s)
                                   (format s "~&~a:~%~a" (emit "try") (emit `(do ,prog)))
                                   (loop for e in exceptions do
                                         (destructuring-bind (form &rest body) e
                                           (if (member form '(else finally))
                                               (format s "~&~a~%" (emit `(indent ,(format nil "~a:" form))))
                                               (format s "~&~a~%" (emit `(indent ,(format nil "except ~a:" (emit form))))))
                                           (format s "~a" (emit `(do ,@body))))))))
                          
                          (t (destructuring-bind (name &rest args) code
                               (if (listp name)
                                   (format nil "(~a)(~a)" (emit name) (if args (emit `(paren ,@args)) ""))
                                   (let* ((positional (loop for i below (length args) until (keywordp (elt args i)) collect (elt args i)))
                                          (plist (subseq args (length positional)))
                                          (props (loop for e in plist by #'cddr collect e)))
                                     (format nil "~a~a" name
                                             (emit `(paren ,@(append positional
                                                                     (loop for e in props collect
                                                                           `(= ,(format nil "~a" e) ,(getf plist e))))))))))))
                        (cond
                          ((symbolp code) (format nil "~a" code))
                          ((stringp code) code)
                          ((numberp code)
                           (cond
                             ((integerp code) (format str "~a" code))
                             ((floatp code) (if omit-redundant-parentheses
                                                (format str "~a" (print-sufficient-digits-f64 code))
                                                (format str "(~a)" (print-sufficient-digits-f64 code))))
                             ((complexp code) (if omit-redundant-parentheses
                                                  (format str "~a + 1j * ~a"
                                                          (print-sufficient-digits-f64 (realpart code))
                                                          (print-sufficient-digits-f64 (imagpart code)))
                                                  (format str "((~a) + 1j * (~a))"
                                                          (print-sufficient-digits-f64 (realpart code))
                                                          (print-sufficient-digits-f64 (imagpart code)))))))))
                    ""))))))

  (let ((result-path (write-source output-filename code output-dir)))
    (format t "Successfully generated py.lisp at ~a~%" result-path)))
