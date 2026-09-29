;;;; 51-precedence.lisp --- generic precedence engine (generalized from
;;;; cl-py-generator operand-needs-parentheses-p / effective-operator and the
;;;; non-associativity of cl-rust-generator)
;;;;
;;;; A table is a list of entries
;;;;   (:op :add :token "+" :level 12 :assoc :left)
;;;; A higher :level binds tighter. :assoc is :left, :right or :non. The
;;;; pseudo operators :neg-literal (a negative number) and :postfix (receiver
;;;; of a method call or field access) take part like normal operators.
;;;; CLARITY is a list of (parent-ops child-ops) pairs that always get
;;;; parentheses (compiler/linter warnings such as -Wparentheses).

(in-package :polyglot)

(defparameter +comparison-ops+ '(:eq :ne :lt :le :gt :ge))
(defparameter +arithmetic-ops+ '(:add :sub :mul :div :rem :neg))
(defparameter +bitwise-ops+ '(:bitand :bitor :bitxor :shl :shr))

(defstruct op-table
  entries           ; list of plists
  clarity)          ; list of (parents children)

(defun op-entry (table op)
  (or (find op (op-table-entries table) :key (lambda (e) (getf e :op)))
      (error "operator ~s missing in the operator table" op)))

(defun op-level (table op) (getf (op-entry table op) :level))
(defun op-assoc (table op) (getf (op-entry table op) :assoc :left))
(defun op-token (table op) (getf (op-entry table op) :token))

(defun clarity-parens-p (table parent child)
  (loop for (parents children) in (op-table-clarity table)
        thereis (and (member parent parents) (member child children))))

(defun needs-parens-p (table parent child position mode)
  "True when an operand printing CHILD (an op keyword or NIL for a primary
expression) must be parenthesized inside PARENT. POSITION is :left, :right or
:only (unary operand, postfix receiver). MODE :full parenthesizes every
operator operand (the oracle), :minimal only where required."
  (cond ((or (null child) (null parent)) nil)
        ((eq mode :full) t)
        ((clarity-parens-p table parent child) t)
        ;; a comparison inside a comparison: chained in Python, -Wparentheses in C++
        ((and (member parent +comparison-ops+) (member child +comparison-ops+)) t)
        (t (let ((p (op-level table parent)) (c (op-level table child)))
             (cond ((< c p) t)
                   ((> c p) nil)
                   ;; same level
                   ((eq position :only) nil)
                   (t (ecase (op-assoc table parent)
                        (:left (eq position :right))
                        (:right (eq position :left))
                        (:non t))))))))

(defun operand-string (table parent position child-string child-op mode)
  "CHILD-STRING, wrapped in parentheses when NEEDS-PARENS-P says so."
  (if (needs-parens-p table parent child-op position mode)
      (format nil "(~a)" child-string)
      child-string))

(defun binary-string (table op left right mode &key token)
  "LEFT and RIGHT are (string . op) pairs. Returns (values string op)."
  (values (format nil "~a ~a ~a"
                  (operand-string table op :left (car left) (cdr left) mode)
                  (or token (op-token table op))
                  (operand-string table op :right (car right) (cdr right) mode))
          op))

(defun unary-string (table op operand mode &key token)
  "Prefix operator OP applied to the (string . op) pair OPERAND."
  (let ((inner (operand-string table op :only (car operand) (cdr operand) mode)))
    (values (format nil "~a~a" (or token (op-token table op))
                    (if (and (member (cdr operand) '(:neg :neg-literal))
                             (not (needs-parens-p table op (cdr operand) :only mode)))
                        (format nil "(~a)" inner)
                        inner))
            op)))

(defun postfix-receiver (table operand mode)
  "Receiver of a method call or field access: parenthesized unless primary."
  (operand-string table :postfix :only (car operand) (cdr operand) mode))
