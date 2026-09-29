;;;; 13-stmt.lisp --- statement nodes and variable definitions

(in-package :polyglot)

(define-node var-def ()
  ((name) (declared-ty) (ty :initform :unknown) (mode :initform :in)
   (kind :initform :local) (target-name) (mutable) (receiver-p))
  "A binding: local, parameter, loop variable. KIND is :local :param :loop
:receiver. MODE (:in :inout :sink) only matters for parameters; MUTABLE is set
by the mutability pass, TARGET-NAME by rename.")

(define-node stmt ()
  ()
  "Base class of statements.")

(define-node block-stmt (stmt)
  ((stmts :child :list) (scope :initform t))
  "Statement sequence. SCOPE T opens a new scope (LET), NIL does not (PROGN).")

(define-node decl-stmt (stmt)
  ((var :child :one) (init :child :one))
  "Declaration of VAR (a var-def) in the current block, optional INIT.")

(define-node assign-stmt (stmt)
  ((place :child :one) (value :child :one))
  "(setf place value).")

(define-node op-assign-stmt (stmt)
  ((op) (place :child :one) (value :child :one))
  "Compound assignment such as +=, produced by desugar from incf/decf.")

(define-node incf-stmt (stmt)
  ((op) (place :child :one) (delta :child :one))
  "(incf place [delta]) / (decf ...); OP is :add or :sub.")

(define-node if-stmt (stmt)
  ((test :child :one) (then :child :list) (else :child :list))
  "IF in statement position.")

(define-node when-stmt (stmt)
  ((test :child :one) (body :child :list) (negate))
  "WHEN, or UNLESS when NEGATE is true.")

(define-node cond-clause ()
  ((test :child :one) (body :child :list))
  "One COND clause; TEST NIL stands for the default clause T.")

(define-node cond-stmt (stmt)
  ((clauses :child :list))
  "COND in statement position.")

(define-node while-stmt (stmt)
  ((test :child :one) (body :child :list))
  "(while test body...).")

(define-node dotimes-stmt (stmt)
  ((var :child :one) (count :child :one) (body :child :list))
  "(dotimes (i n) body...), desugared to for-range-stmt.")

(define-node for-range-stmt (stmt)
  ((var :child :one) (start :child :one) (end :child :one) (body :child :list))
  "Counting loop from START below END.")

(define-node for-each-stmt (stmt)
  ((var :child :one) (seq :child :one) (body :child :list) (iter-mode))
  "(dolist (x seq) body...). ITER-MODE (:ref :mut :move) is set by mutability.")

(define-node return-stmt (stmt)
  ((value :child :one))
  "(return [value]).")

(define-node break-stmt (stmt) () "(break).")
(define-node continue-stmt (stmt) () "(continue).")

(define-node expr-stmt (stmt)
  ((expr :child :one))
  "Expression evaluated for its side effects.")

(define-node comment-stmt (stmt)
  ((lines))
  "(comment \"...\") / (comments ...).")

(define-node raw-stmt (stmt)
  ((text))
  "(raw \"text\") in statement position.")

(define-node if-let-stmt (stmt)
  ((var :child :one) (expr :child :one) (then :child :list) (else :child :list))
  "(if-let (x optional-expr) then [else]).")

(define-node target-case-stmt (stmt)
  ((branches :child :list))
  "target-case in statement position.")

(define-node target-form-stmt (stmt)
  ((backend) (form))
  "Statement form from an extension package.")
