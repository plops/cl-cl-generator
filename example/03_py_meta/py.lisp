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
    (with-output-to-file
     (s tmp :if-exists :supersede :if-does-not-exist :create)
     (format s "~a~%"
             (jonathan.encode:to-json
              `(:cells
                ,(loop for e in nb-code
                       collect (destructuring-bind (name &rest rest) e
                                 (case name
                                   (markdown
                                    `(:cell_type "markdown" :metadata :empty
                                      :source
                                      ,(loop for p in rest
                                             collect (format nil "~a~c" p
                                                             #\Newline))))
                                   (python
                                    `(:cell_type "code" :metadata :empty
                                      :execution_count :null :outputs nil
                                      :source
                                      ,(loop for p in rest
                                             appending (let ((tempfn
                                                              #+sbcl "/dev/shm/cell" #+ecl (format nil "~a_tmp_cell" nb-file)))
                                                         (write-source tempfn p)
                                                         (with-open-file
                                                             (stream
                                                              (format nil
                                                                      "~a.py"
                                                                      tempfn))
                                                           (loop for line = (read-line
                                                                             stream
                                                                             nil)
                                                                 while line
                                                                 collect (format
                                                                          nil
                                                                          "~a~c"
                                                                          line
                                                                          #\Newline))))))))))
                #+nil (:|metadata| (:|kernelspec| (:|display_name| "Python 3" :|language| "python" :|name| "python3") :|nbformat| 4 :|nbformat_minor| 2))
                :metadata
                (:kernelspec
                 (:display_name "Python 3" :language "python" :name "python3"))
                :nbformat 4 :nbformat_minor 2))))
    #-sbcl (external-program:run "/usr/bin/jq" `("-M" "." ,tmp) :output nb-file :if-output-exists :supersede)
    #+sbcl (sb-ext:run-program "/usr/bin/jq" `("-M" "." ,tmp) :output nb-file :if-output-exists :supersede)
    (delete-file tmp)))

(setf (readtable-case *readtable*) :invert)

(defparameter *warn-breaking* t)

(defparameter *file-hashes* (make-hash-table))

(defun consume-declare (body)
  "Take a list of instructions from `body`, parse type declarations,
return the `body` without them and a hash table with an environment. The
entry `return-values` contains a list of return values. Currently supports `type`, `values`."
  (let ((env (make-hash-table)) (looking-p t) (new-body nil))
    (loop for e in body
          do (if looking-p
                 (if (listp e)
                     (if (eq (car e) 'declare)
                         (loop for declaration in (cdr e)
                               do (when (eq (first declaration) 'type)
                                    (destructuring-bind (symb type &rest
                                                         vars) declaration
                                      (declare (ignorable symb))
                                      (loop for var in vars
                                            do (setf (gethash var env)
                                                       type)))) (when (eq
                                                                       (first
                                                                        declaration)
                                                                       'capture)
                                                                  (destructuring-bind (symb
                                                                                       &rest
                                                                                       vars) declaration
                                                                    (declare
                                                                     (ignorable
                                                                      symb))
                                                                    (loop for var in vars
                                                                          do (push
                                                                              var
                                                                              captures)))) (when (eq
                                                                                                  (first
                                                                                                   declaration)
                                                                                                  'values)
                                                                                             (destructuring-bind (symb
                                                                                                                  &rest
                                                                                                                  types-opt) declaration
                                                                                               (declare
                                                                                                (ignorable
                                                                                                 symb))
                                                                                               (let ((types
                                                                                                      nil))
                                                                                                 (loop for type in types-opt
                                                                                                       do (unless (eq
                                                                                                                   #\&
                                                                                                                   (aref
                                                                                                                    (format
                                                                                                                     nil
                                                                                                                     "~a"
                                                                                                                     type)
                                                                                                                    0))
                                                                                                            (push
                                                                                                             type
                                                                                                             types)))
                                                                                                 (setf (gethash
                                                                                                        'return-values
                                                                                                        env)
                                                                                                         (reverse
                                                                                                          types))))))
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
      (multiple-value-bind (req-param opt-param res-param key-param other-key-p
                            aux-param key-exist-p) (parse-ordinary-lambda-list
                                                    lambda-list)
        (declare
         (ignorable req-param opt-param res-param key-param other-key-p
          aux-param key-exist-p))
        (with-output-to-string (s)
          (format s "def ~a~a~@[->~a~]:~%" name
                  (funcall emit
                           `(paren
                             ,@(loop for p in req-param
                                     collect `(raw
                                               ,(format nil "~a~@[: ~a~]" p
                                                        (let ((type
                                                               (gethash p env)))
                                                          (when type
                                                            (funcall emit
                                                                     type))))))
                             ,@(loop for ((keyword-name name) init
                                          supplied-p) in key-param
                                     collect `(raw
                                               ,(format nil "~a~a ~@[~a~]" name
                                                        (let ((type
                                                               (gethash name
                                                                        env)))
                                                          (if type
                                                              (format nil
                                                                      ": ~a"
                                                                      (funcall
                                                                       emit
                                                                       type))
                                                              ""))
                                                        (format nil "= ~a"
                                                                (funcall emit
                                                                         init)))))))
                  (let ((r (gethash 'return-values env)))
                    (if (< 1 (length r))
                        (break "multiple return values unsupported: ~a" r)
                        (if (car r)
                            (case (car r)
                              (:constructor "")
                              (t (car r)))
                            nil))))
          (format s "~a" (funcall emit `(body ,@body))))))))

(defun write-source (name code &optional (dir (user-homedir-pathname))
                     ignore-hash)
  "Writes the Python source code to a file."
  (let* ((fn (merge-pathnames (format nil "~a.py" name) dir))
         (code-str (emit-py :clear-env t :code code)) (fn-hash (sxhash fn))
         (code-hash (sxhash code-str)))
    (multiple-value-bind (old-code-hash exists) (gethash fn-hash *file-hashes*)
      (when (or (not exists) ignore-hash (/= code-hash old-code-hash))
        (setf (gethash fn-hash *file-hashes*) code-hash)
        (with-open-file
            (s fn :direction :output :if-exists :supersede :if-does-not-exist
             :create)
          (write-sequence code-str s))
        #+nil (sb-ext:run-program "/usr/bin/autopep8" (list "--max-line-length 80" (namestring fn)))
        (sb-ext:run-program "/snap/bin/uvx"
                            (list "ruff" "format" (namestring fn)))
        #+nil (sb-ext:run-program "/usr/bin/yapf" (list "-i" (namestring fn)))
        #+nil (progn (sb-ext:run-program "/home/martin/.local/bin/black" (list "--fast" (namestring fn))))))))

(defun print-sufficient-digits-f64 (f)
  "Prints a double floating point number as a string with a given number of digits.
	 Parses the string representation and increases the number of digits until the same bit pattern is obtained."
  (let* ((a f) (digits 1) (b (- a 1))
         (threshold
          (if (typep f 'double-float)
              1.0d-12
              1.0e-7))
         (*read-default-float-format*
          (if (typep f 'double-float)
              'double-float
              'single-float)))
    (unless (= a 0)
      (loop while (< threshold (/ (abs (- a b)) (abs a)))
            do (setf b (read-from-string (format nil "~,vG" digits a))) (incf
                                                                         digits)))
    (substitute #\e #\d (format nil "~,vG" (max 1 (1- digits)) a))))

(defparameter *precedence*
  `((:op (paren paren* dict list tuple curly aref dot) :assoc l)
    (:op (**) :assoc r) (:op (unary- unary+ ~) :assoc r)
    (:op (* @ / // %) :assoc l) (:op (+ -) :assoc l) (:op (<< >>) :assoc l)
    (:op (& logand) :assoc l) (:op (^ logxor) :assoc l)
    (:op (|\|| logior) :assoc l)
    (:op (< <= > >= != == in not-in is is-not) :assoc l) (:op (not) :assoc r)
    (:op (and) :assoc l) (:op (or) :assoc l) (:op (? ternary) :assoc r)
    (:op (= setf) :assoc r)))

(defparameter *operators*
  (loop for e in *precedence*
        append (getf e :op)))

(defun lookup-precedence (operator)
  (loop for e in *precedence*
        and e-i from 0
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

(defun parse-and-emit-fstring (str)
  (let ((len (length str)) (pos 0) (parts nil))
    (labels ((scan-literal nil
              (let ((start pos))
                (loop while (< pos len)
                      do (cond
                           ((and (< (1+ pos) len)
                                 (or
                                  (and (char= (char str pos) #\{)
                                       (char= (char str (1+ pos)) #\{))
                                  (and (char= (char str pos) #\})
                                       (char= (char str (1+ pos)) #\}))))
                            (incf pos 2))
                           ((char= (char str pos) #\{) (return))
                           (t (incf pos))))
                (when (> pos start)
                  (push (subseq str start pos) parts))))
             (scan-expr nil (incf pos)
              (let ((start pos) (depth 0))
                (loop while (< pos len)
                      do (cond
                           ((char= (char str pos) #\{) (incf depth) (incf pos))
                           ((char= (char str pos) #\})
                            (if (= depth 0)
                                (return)
                                (progn
                                  (decf depth)
                                  (incf pos))))
                           (t (incf pos))))
                (if (< pos len)
                    (let ((expr-str (subseq str start pos)))
                      (incf pos)
                      (let ((expr (read-from-string expr-str)))
                        (push (list :expr expr) parts)))
                    (error "Unmatched '{' in f-string: ~a" str)))))
      (loop while (< pos len)
            do (if (char= (char str pos) #\{)
                   (scan-expr)
                   (scan-literal)))
      (let ((has-expr
             (some (lambda (part) (and (listp part) (eq (car part) :expr)))
                   parts)))
        (format nil "~a\"~{~a~}\""
                (if has-expr
                    "f"
                    "")
                (mapcar
                 (lambda (part)
                   (if (and (listp part) (eq (car part) :expr))
                       (format nil "{~a}" (emit-py :code (cadr part)))
                       part))
                 (nreverse parts)))))))

(defun concat-string-prefixes (&key raw bytes force-f args)
  (let ((has-expr
         (or force-f (some (lambda (x) (not (stringp x))) args)
             (some (lambda (x) (and (stringp x) (search "{" x))) args))))
    (format nil "~{~a~}"
            (remove nil
                    (list
                     (when bytes
                       "b")
                     (when raw
                       "r")
                     (when has-expr
                       "f"))))))

(defun format-string-body (args)
  (with-output-to-string (s)
    (dolist (x args)
      (cond
        ((stringp x) (write-string x s))
        (t (format s "{~a}" (emit-py :code x)))))))

(defun parse-explicit-string (args)
  (let ((raw nil) (bytes nil) (triple nil) (force-f nil) (actual-args nil))
    (loop for rest = args then (cdr rest)
          while rest
          do (let ((arg (car rest)))
               (cond
                 ((eq arg :raw) (setf raw t))
                 ((eq arg :bytes) (setf bytes t))
                 ((eq arg :triple) (setf triple t))
                 ((eq arg :f) (setf force-f t))
                 (t (setf actual-args rest) (return)))))
    (let* ((prefix
            (concat-string-prefixes :raw raw :bytes bytes :force-f force-f
             :args actual-args))
           (body (format-string-body actual-args))
           (quote-str
            (if triple
                "\"\"\""
                "\"")))
      (format nil "~a~a~a~a" prefix quote-str body quote-str))))

(defun emit-py (&key code (str nil) (clear-env nil) (level 0)
                (omit-redundant-parentheses t))
  "Emit Python code based on the given parameters."
  (when clear-env
    (setf *env-functions* nil
          *env-macros* nil))
  (flet ((emit (code &optional (dl 0))
          (emit-py :code code :clear-env nil :level (+ dl level)
           :omit-redundant-parentheses omit-redundant-parentheses)))
    (if code
        (if (listp code)
            (case (car code)
              (paren
               (let ((args (cdr code)))
                 (format nil "(~{~a~^, ~})" (mapcar #'emit args))))
              (ntuple
               (let ((args (cdr code)))
                 (format nil "~{~a~^, ~}" (mapcar #'emit args))))
              (list
               (let ((args (cdr code)))
                 (format nil "[~{~a~^, ~}]" (mapcar #'emit args))))
              (curly
               (let ((args (cdr code)))
                 (format nil "{~{~a~^, ~}}" (mapcar #'emit args))))
              (tuple
               (let ((args (cdr code)))
                 (format nil "(~{~a,~})" (mapcar #'emit args))))
              (dict
               (let* ((args (cdr code)))
                 (format nil "{~{~{(~a):(~a)~}~^, ~}}"
                         (loop for (k v) in args
                               collect (list (emit k) (emit v))))))
              (dict*
               (let* ((args (cdr code)))
                 (format nil "dict~a"
                         (emit
                          `(paren
                            ,@(loop for (e f) on args by #'cddr
                                    collect `(= ,e ,f)))))))
              (indent
               (format nil "~{~a~}~a"
                       (loop for i below level
                             collect "    ")
                       (emit (cadr code))))
              (body
               (with-output-to-string (s)
                 (format s "~{~&~a~}"
                         (mapcar #'(lambda (x) (emit `(indent ,x) 1))
                                 (cdr code)))))
              (class
               (destructuring-bind (name parents &rest body) (cdr code)
                 (format nil "class ~a~a:~%~a" name
                         (if (eq 0 (length parents))
                             ""
                             (emit `(paren ,@parents)))
                         (emit `(body ,@body)))))
              (progn
                (with-output-to-string (s)
                  (format s "~&~a~{~&~a~}" (emit (cadr code))
                          (mapcar #'(lambda (x) (emit `(indent ,x) 0))
                                  (cddr code)))))
              (cell
               (with-output-to-string (s)
                 (format s "~a~%"
                         (emit
                          `(progn
                             (cl-py-generator:comments "export")
                             ,@(cdr code))))))
              (export
               (with-output-to-string (s)
                 (format s "~a~%"
                         (emit
                          `(progn
                             (cl-py-generator:comments "|export")
                             ,@(cdr code))))))
              (space
               (with-output-to-string (s)
                 (format s "~{~a~^ ~}"
                         (mapcar #'(lambda (x) (emit x)) (cdr code)))))
              (lambda
                  (destructuring-bind (lambda-list &rest body) (cdr code)
                   (multiple-value-bind
                    (req-param opt-param res-param key-param other-key-p
                     aux-param key-exist-p)
                    (parse-ordinary-lambda-list lambda-list)
                    (declare
                     (ignorable req-param opt-param res-param key-param
                      other-key-p aux-param key-exist-p))
                    (with-output-to-string (s)
                      (format s "lambda ~a: ~a"
                              (emit
                               `(ntuple
                                 ,@(append req-param
                                           (loop for e in key-param
                                                 collect (destructuring-bind ((keyword-name
                                                                               name)
                                                                              init
                                                                              suppliedp) e
                                                           (declare
                                                            (ignorable
                                                             keyword-name
                                                             suppliedp))
                                                           (if init
                                                               `(= ,name ,init)
                                                               `(= ,name
                                                                   None)))))))
                              (if (cdr body)
                                  (break "body ~a should have only one entry"
                                         body)
                                  (emit (car body))))))))
              (def (parse-defun code #'emit))
              (=
               (destructuring-bind (a b) (cdr code)
                 (format nil "~a=~a" (emit a) (emit b))))
              (in
               (destructuring-bind (a b) (cdr code)
                 (format nil "(~a in ~a)" (emit a) (emit b))))
              (not-in
               (destructuring-bind (a b) (cdr code)
                 (format nil "(~a not in ~a)" (emit a) (emit b))))
              (is
               (destructuring-bind (a b) (cdr code)
                 (format nil "(~a is ~a)" (emit a) (emit b))))
              (is-not
               (destructuring-bind (a b) (cdr code)
                 (format nil "(~a is not ~a)" (emit a) (emit b))))
              (as
               (destructuring-bind (a b) (cdr code)
                 (format nil "~a as ~a" (emit a) (emit b))))
              (setf (let ((args (cdr code)))
                      (format nil "~a"
                              (emit
                               `(progn
                                  ,@(loop for i below (length args) by 2
                                          collect (let ((a (elt args i))
                                                        (b (elt args (+ 1 i))))
                                                    `(= ,a ,b))))))))
              (incf
               (destructuring-bind (target &optional (val 1)) (cdr code)
                 (format nil "~a += ~a" (emit target) (emit val))))
              (decf
               (destructuring-bind (target &optional (val 1)) (cdr code)
                 (format nil "~a -= ~a" (emit target) (emit val))))
              (aref
               (destructuring-bind (name &rest indices) (cdr code)
                 (format nil "~a[~{~a~^,~}]" (emit name)
                         (mapcar #'emit indices))))
              (slice
               (let ((args (cdr code)))
                 (if (null args)
                     (format nil ":")
                     (format nil "~{~a~^:~}"
                             (mapcar
                              (lambda (a)
                                (if (equal a "")
                                    ""
                                    (emit a)))
                              args)))))
              (dot
               (let ((args (cdr code)))
                 (format nil "~{~a~^.~}"
                         (mapcar #'emit (remove-if #'null args)))))
              (paren*
               (destructuring-bind (parent-op arg &key side) (cdr code)
                 (if (not omit-redundant-parentheses)
                     (format nil "(~a)" (emit arg))
                     (cond
                       ((symbolp arg) (format nil "~a" (emit arg)))
                       ((numberp arg)
                        (if (<= 0 arg)
                            (format nil "~a" (emit arg))
                            (format nil " ~a" (emit arg))))
                       ((stringp arg) (format nil "~a" arg))
                       ((listp arg)
                        (cond
                          ((<= (length arg) 2)
                           (let ((op0 (car arg)) (rest (cdr arg)))
                             (assert (or (symbolp op0) (stringp op0)))
                             (assert (listp rest))
                             (emit `(,op0 ,@rest))))
                          (t
                           (let ((op0 parent-op))
                             (assert (or (symbolp op0) (stringp op0)))
                             (if (and (member op0 *operators*)
                                      (member (car arg) *operators*))
                                 (let* ((p0 (lookup-precedence op0))
                                        (p0assoc (lookup-associativity op0))
                                        (op1 (car arg))
                                        (p1 (lookup-precedence op1)))
                                   (if (or (< p0 p1)
                                           (and (= p0 p1)
                                                (or
                                                 (and (eq p0assoc 'l)
                                                      (eq side 'r))
                                                 (and (eq p0assoc 'r)
                                                      (eq side 'l)))))
                                       (format nil "(~a)" (emit arg))
                                       (emit arg)))
                                 (emit arg))))))))))
              (**
               (let ((args (cdr code)))
                 (if omit-redundant-parentheses
                     (format nil "~a**~a"
                             (emit `(paren* ,'** ,(first args) :side l))
                             (emit `(paren* ,'** ,(second args) :side r)))
                     (format nil "((~a)**(~a))" (emit (first args))
                             (emit (second args))))))
              (//
               (let ((args (cdr code)))
                 (if omit-redundant-parentheses
                     (format nil "~a//~a"
                             (emit `(paren* ,'// ,(first args) :side l))
                             (emit `(paren* ,'// ,(second args) :side r)))
                     (format nil "((~a)//(~a))" (emit (first args))
                             (emit (second args))))))
              (%
               (let ((args (cdr code)))
                 (if omit-redundant-parentheses
                     (format nil "~a%~a"
                             (emit `(paren* ,'% ,(first args) :side l))
                             (emit `(paren* ,'% ,(second args) :side r)))
                     (format nil "((~a)%(~a))" (emit (first args))
                             (emit (second args))))))
              (not
               (destructuring-bind (arg) (cdr code)
                 (if omit-redundant-parentheses
                     (format nil "not ~a" (emit `(paren* ,'not ,arg :side r)))
                     (format nil "(not ~a)" (emit arg)))))
              (lognot
               (destructuring-bind (arg) (cdr code)
                 (if omit-redundant-parentheses
                     (format nil "~~~a" (emit `(paren* ,'lognot ,arg :side r)))
                     (format nil "(~~~a)" (emit arg)))))
              (~
               (destructuring-bind (arg) (cdr code)
                 (if omit-redundant-parentheses
                     (format nil "~~~a" (emit `(paren* ,'~ ,arg :side r)))
                     (format nil "(~~~a)" (emit arg)))))
              (string
               (let ((args (cdr code)))
                 (parse-explicit-string args)))
              (raw
               (destructuring-bind (val) (cdr code)
                 (format nil "~a" val)))
              (decorator
               (destructuring-bind (dec) (cdr code)
                 (if (listp dec)
                     (format nil "@~a~%" (emit dec))
                     (format nil "@~a~%" dec))))
              (decorated
               (destructuring-bind (decs definition) (cdr code)
                 (with-output-to-string (s)
                   (loop for dec in decs
                         do (if (listp dec)
                                (format s "@~a~%" (emit dec))
                                (format s "@~a~%" dec)))
                   (format s "~a" (emit definition)))))
              (yield
               (let ((args (cdr code)))
                 (if args
                     (format nil "yield ~a" (emit (car args)))
                     "yield")))
              (yield-from
               (destructuring-bind (val) (cdr code)
                 (format nil "yield from ~a" (emit val))))
              (assert
               (destructuring-bind (condition &optional message) (cdr code)
                 (if message
                     (format nil "assert ~a, ~a" (emit condition)
                             (emit message))
                     (format nil "assert ~a" (emit condition)))))
              (+
               (let ((args (cdr code)))
                 (if omit-redundant-parentheses
                     (format nil "~{~a~^+~}"
                             (loop for x in args
                                   and i from 0
                                   collect (emit
                                            `(paren* ,'+ ,x :side
                                              ,(if (= i 0)
                                                   'l
                                                   'r)))))
                     (format nil "(~{(~a)~^+~})" (mapcar #'emit args)))))
              (*
               (let ((args (cdr code)))
                 (if omit-redundant-parentheses
                     (format nil "~{~a~^*~}"
                             (loop for x in args
                                   and i from 0
                                   collect (emit
                                            `(paren* ,'* ,x :side
                                              ,(if (= i 0)
                                                   'l
                                                   'r)))))
                     (format nil "(~{(~a)~^*~})" (mapcar #'emit args)))))
              (@
               (let ((args (cdr code)))
                 (if omit-redundant-parentheses
                     (format nil "~{~a~^@~}"
                             (loop for x in args
                                   and i from 0
                                   collect (emit
                                            `(paren* ,'@ ,x :side
                                              ,(if (= i 0)
                                                   'l
                                                   'r)))))
                     (format nil "(~{(~a)~^@~})" (mapcar #'emit args)))))
              (==
               (let ((args (cdr code)))
                 (if omit-redundant-parentheses
                     (format nil "~{~a~^==~}"
                             (loop for x in args
                                   and i from 0
                                   collect (emit
                                            `(paren* ,'== ,x :side
                                              ,(if (= i 0)
                                                   'l
                                                   'r)))))
                     (format nil "(~{(~a)~^==~})" (mapcar #'emit args)))))
              (<<
               (let ((args (cdr code)))
                 (if omit-redundant-parentheses
                     (format nil "~{~a~^<<~}"
                             (loop for x in args
                                   and i from 0
                                   collect (emit
                                            `(paren* ,'<< ,x :side
                                              ,(if (= i 0)
                                                   'l
                                                   'r)))))
                     (format nil "(~{(~a)~^<<~})" (mapcar #'emit args)))))
              (!=
               (let ((args (cdr code)))
                 (if omit-redundant-parentheses
                     (format nil "~{~a~^!=~}"
                             (loop for x in args
                                   and i from 0
                                   collect (emit
                                            `(paren* ,'!= ,x :side
                                              ,(if (= i 0)
                                                   'l
                                                   'r)))))
                     (format nil "(~{(~a)~^!=~})" (mapcar #'emit args)))))
              (<
               (let ((args (cdr code)))
                 (if omit-redundant-parentheses
                     (format nil "~{~a~^<~}"
                             (loop for x in args
                                   and i from 0
                                   collect (emit
                                            `(paren* ,'< ,x :side
                                              ,(if (= i 0)
                                                   'l
                                                   'r)))))
                     (format nil "(~{(~a)~^<~})" (mapcar #'emit args)))))
              (>
               (let ((args (cdr code)))
                 (if omit-redundant-parentheses
                     (format nil "~{~a~^>~}"
                             (loop for x in args
                                   and i from 0
                                   collect (emit
                                            `(paren* ,'> ,x :side
                                              ,(if (= i 0)
                                                   'l
                                                   'r)))))
                     (format nil "(~{(~a)~^>~})" (mapcar #'emit args)))))
              (<=
               (let ((args (cdr code)))
                 (if omit-redundant-parentheses
                     (format nil "~{~a~^<=~}"
                             (loop for x in args
                                   and i from 0
                                   collect (emit
                                            `(paren* ,'<= ,x :side
                                              ,(if (= i 0)
                                                   'l
                                                   'r)))))
                     (format nil "(~{(~a)~^<=~})" (mapcar #'emit args)))))
              (>=
               (let ((args (cdr code)))
                 (if omit-redundant-parentheses
                     (format nil "~{~a~^>=~}"
                             (loop for x in args
                                   and i from 0
                                   collect (emit
                                            `(paren* ,'>= ,x :side
                                              ,(if (= i 0)
                                                   'l
                                                   'r)))))
                     (format nil "(~{(~a)~^>=~})" (mapcar #'emit args)))))
              (>>
               (let ((args (cdr code)))
                 (if omit-redundant-parentheses
                     (format nil "~{~a~^>>~}"
                             (loop for x in args
                                   and i from 0
                                   collect (emit
                                            `(paren* ,'>> ,x :side
                                              ,(if (= i 0)
                                                   'l
                                                   'r)))))
                     (format nil "(~{(~a)~^>>~})" (mapcar #'emit args)))))
              (&
               (let ((args (cdr code)))
                 (if omit-redundant-parentheses
                     (format nil "~{~a~^ & ~}"
                             (loop for x in args
                                   and i from 0
                                   collect (emit
                                            `(paren* ,'& ,x :side
                                              ,(if (= i 0)
                                                   'l
                                                   'r)))))
                     (format nil "(~{(~a)~^ & ~})" (mapcar #'emit args)))))
              (logand
               (let ((args (cdr code)))
                 (if omit-redundant-parentheses
                     (format nil "~{~a~^ & ~}"
                             (loop for x in args
                                   and i from 0
                                   collect (emit
                                            `(paren* ,'logand ,x :side
                                              ,(if (= i 0)
                                                   'l
                                                   'r)))))
                     (format nil "(~{(~a)~^ & ~})" (mapcar #'emit args)))))
              (logxor
               (let ((args (cdr code)))
                 (if omit-redundant-parentheses
                     (format nil "~{~a~^ ^ ~}"
                             (loop for x in args
                                   and i from 0
                                   collect (emit
                                            `(paren* ,'logxor ,x :side
                                              ,(if (= i 0)
                                                   'l
                                                   'r)))))
                     (format nil "(~{(~a)~^ ^ ~})" (mapcar #'emit args)))))
              (|\||
               (let ((args (cdr code)))
                 (if omit-redundant-parentheses
                     (format nil "~{~a~^ | ~}"
                             (loop for x in args
                                   and i from 0
                                   collect (emit
                                            `(paren* ,'|\|| ,x :side
                                              ,(if (= i 0)
                                                   'l
                                                   'r)))))
                     (format nil "(~{(~a)~^ | ~})" (mapcar #'emit args)))))
              (^
               (let ((args (cdr code)))
                 (if omit-redundant-parentheses
                     (format nil "~{~a~^ ^ ~}"
                             (loop for x in args
                                   and i from 0
                                   collect (emit
                                            `(paren* ,'^ ,x :side
                                              ,(if (= i 0)
                                                   'l
                                                   'r)))))
                     (format nil "(~{(~a)~^ ^ ~})" (mapcar #'emit args)))))
              (logior
               (let ((args (cdr code)))
                 (if omit-redundant-parentheses
                     (format nil "~{~a~^ | ~}"
                             (loop for x in args
                                   and i from 0
                                   collect (emit
                                            `(paren* ,'logior ,x :side
                                              ,(if (= i 0)
                                                   'l
                                                   'r)))))
                     (format nil "(~{(~a)~^ | ~})" (mapcar #'emit args)))))
              (and
               (let ((args (cdr code)))
                 (if omit-redundant-parentheses
                     (format nil "~{~a~^ and ~}"
                             (loop for x in args
                                   and i from 0
                                   collect (emit
                                            `(paren* ,'and ,x :side
                                              ,(if (= i 0)
                                                   'l
                                                   'r)))))
                     (format nil "(~{(~a)~^ and ~})" (mapcar #'emit args)))))
              (or
               (let ((args (cdr code)))
                 (if omit-redundant-parentheses
                     (format nil "~{~a~^ or ~}"
                             (loop for x in args
                                   and i from 0
                                   collect (emit
                                            `(paren* ,'or ,x :side
                                              ,(if (= i 0)
                                                   'l
                                                   'r)))))
                     (format nil "(~{(~a)~^ or ~})" (mapcar #'emit args)))))
              (-
               (let ((args (cdr code)))
                 (if omit-redundant-parentheses
                     (if (eq 1 (length args))
                         (format nil "-~a"
                                 (emit `(paren* - ,(car args) :side r)))
                         (format nil "~{~a~^-~}"
                                 (loop for x in args
                                       and i from 0
                                       collect (emit
                                                `(paren* - ,x :side
                                                  ,(if (= i 0)
                                                       'l
                                                       'r))))))
                     (format nil "(~{(~a)~^-~})" (mapcar #'emit args)))))
              (/
               (let ((args (cdr code)))
                 (if omit-redundant-parentheses
                     (if (eq 1 (length args))
                         (format nil "1.0 / ~a"
                                 (emit `(paren* / ,(car args) :side r)))
                         (format nil "~{~a~^/~}"
                                 (loop for x in args
                                       and i from 0
                                       collect (emit
                                                `(paren* / ,x :side
                                                  ,(if (= i 0)
                                                       'l
                                                       'r))))))
                     (format nil "(~{(~a)~^/~})" (mapcar #'emit args)))))
              (comment (format nil "# ~a~%" (cadr code)))
              (comments
               (let ((args (cdr code)))
                 (format nil "~{# ~a~%~}"
                         (mapcar
                          #'(lambda (arg)
                              (cl-ppcre:regex-replace-all "\\n" arg
                                                          (format nil "~%# ")))
                          args))))
              (symbol (substitute #\: #\- (format nil "~a" (cadr code))))
              (return
               (let ((args (cdr code)))
                 (if args
                     (format nil "return ~a" (emit `(ntuple ,@args)))
                     "return")))
              (for
               (destructuring-bind ((vs ls) &rest body) (cdr code)
                 (with-output-to-string (s)
                   (format s "for ~a in ~a:~%" (emit vs) (emit ls))
                   (format s "~a" (emit `(body ,@body))))))
              (for-generator
               (destructuring-bind ((vs ls) expr) (cdr code)
                 (format nil "~a for ~a in ~a" (emit expr) (emit vs)
                         (emit ls))))
              (while
               (destructuring-bind (vs &rest body) (cdr code)
                 (with-output-to-string (s)
                   (if omit-redundant-parentheses
                       (format s "while ~a:~%" (emit vs))
                       (format s "while ~a:~%" (emit `(paren ,vs))))
                   (format s "~a" (emit `(body ,@body))))))
              (if (destructuring-bind (condition true-statement &optional
                                       false-statement) (cdr code)
                    (with-output-to-string (s)
                      (if omit-redundant-parentheses
                          (format s "if ~a:~%~a" (emit condition)
                                  (emit `(body ,true-statement)))
                          (format s "if ( ~a ):~%~a" (emit condition)
                                  (emit `(body ,true-statement))))
                      (when false-statement
                        (format s "~&~a:~%~a"
                                (emit `(indent (cl-py-generator::raw "else")))
                                (emit `(body ,false-statement)))))))
              (cond
                (destructuring-bind (&rest clauses) (cdr code)
                  (with-output-to-string (s)
                    (loop for clause in clauses
                          and i from 0
                          do (destructuring-bind (condition &rest
                                                  statements) clause
                               (format s "~&~a:~%~a"
                                       (cond
                                         ((and (eq condition 't) (eq i 0))
                                          (if omit-redundant-parentheses
                                              "if True"
                                              "if ( True )"))
                                         ((eq i 0)
                                          (if omit-redundant-parentheses
                                              (format nil "if ~a"
                                                      (emit condition))
                                              (format nil "if ( ~a )"
                                                      (emit condition))))
                                         ((eq condition 't)
                                          (emit
                                           `(indent
                                             (cl-py-generator::raw "else"))))
                                         (t
                                          (emit
                                           `(indent
                                             (cl-py-generator::raw
                                              ,(if omit-redundant-parentheses
                                                   (format nil "elif ~a"
                                                           (emit condition))
                                                   (format nil "elif ( ~a )"
                                                           (emit
                                                            condition))))))))
                                       (emit `(body ,@statements))))))))
              (?
               (destructuring-bind (condition true-statement &optional
                                    (false-statement
                                     '(cl-py-generator::raw "None")
                                     false-statement-supplied-p)) (cdr code)
                 (if omit-redundant-parentheses
                     (if false-statement-supplied-p
                         (format nil "~a if ~a else ~a"
                                 (emit
                                  `(paren* ternary ,true-statement :side l))
                                 (emit `(paren* ternary ,condition :side l))
                                 (emit
                                  `(paren* ternary ,false-statement :side r)))
                         (format nil "~a if ~a"
                                 (emit
                                  `(paren* ternary ,true-statement :side l))
                                 (emit `(paren* ternary ,condition :side l))))
                     (if false-statement-supplied-p
                         (format nil "(~a) if (~a) else (~a)"
                                 (emit true-statement) (emit condition)
                                 (emit false-statement))
                         (format nil "~a if (~a)" (emit true-statement)
                                 (emit condition))))))
              (when (destructuring-bind (condition &rest forms) (cdr code)
                      (emit
                       `(if ,condition
                            (progn
                              ,@forms)))))
              (unless (destructuring-bind (condition &rest forms) (cdr code)
                        (emit
                         `(if (not ,condition)
                              (progn
                                ,@forms)))))
              (import-from
               (destructuring-bind (module &rest rest) (cdr code)
                 (format nil "from ~a import ~{~a~^, ~}" (emit module)
                         (mapcar #'emit rest))))
              (import
               (let ((args (cdr code)))
                 (with-output-to-string (s)
                   (loop for val in args
                         and i from 0
                         do (unless (= i 0)
                              (terpri s)) (if (listp val)
                                              (format s "import ~a as ~a"
                                                      (second val) (first val))
                                              (format s "import ~a" val))))))
              (with
               (destructuring-bind (form &rest body) (cdr code)
                 (with-output-to-string (s)
                   (format s "~a~a:~%~a" (emit `(cl-py-generator::raw "with "))
                           (emit form) (emit `(body ,@body))))))
              (try
               (destructuring-bind (prog &rest exceptions) (cdr code)
                 (with-output-to-string (s)
                   (format s "~&~a:~%~a" (emit `(cl-py-generator::raw "try"))
                           (emit `(body ,prog)))
                   (loop for e in exceptions
                         do (destructuring-bind (form &rest body) e
                              (if (member form '(else finally))
                                  (format s "~&~a~%"
                                          (emit
                                           `(indent
                                             (cl-py-generator::raw
                                              ,(format nil "~a:" form)))))
                                  (format s "~&~a~%"
                                          (emit
                                           `(indent
                                             (cl-py-generator::raw
                                              ,(format nil "except ~a:"
                                                       (if (stringp form)
                                                           form
                                                           (emit form))))))))
                              (format s "~a" (emit `(body ,@body))))))))
              (t
               (destructuring-bind (name &rest args) code
                 (if (listp name)
                     (format nil "(~a)(~a)" (emit name)
                             (if args
                                 (emit `(paren ,@args))
                                 ""))
                     (let* ((positional
                             (loop for i below (length args)
                                   until (keywordp (elt args i))
                                   collect (elt args i)))
                            (plist (subseq args (length positional)))
                            (props
                             (loop for e in plist by #'cddr
                                   collect e)))
                       (format nil "~a~a" name
                               (emit
                                `(paren
                                  ,@(append positional
                                            (loop for e in props
                                                  collect `(=
                                                            (cl-py-generator::raw
                                                             ,(format nil "~a"
                                                                      e))
                                                            ,(getf plist
                                                                   e))))))))))))
            (cond
              ((symbolp code) (format nil "~a" code))
              ((stringp code) (parse-and-emit-fstring code))
              ((numberp code)
               (cond
                 ((integerp code) (format str "~a" code))
                 ((floatp code)
                  (if omit-redundant-parentheses
                      (format str "~a" (print-sufficient-digits-f64 code))
                      (format str "(~a)" (print-sufficient-digits-f64 code))))
                 ((complexp code)
                  (if omit-redundant-parentheses
                      (format str "~a + 1j * ~a"
                              (print-sufficient-digits-f64 (realpart code))
                              (print-sufficient-digits-f64 (imagpart code)))
                      (format str "((~a) + 1j * (~a))"
                              (print-sufficient-digits-f64 (realpart code))
                              (print-sufficient-digits-f64
                               (imagpart code)))))))))
        "")))