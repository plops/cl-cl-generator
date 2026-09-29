;;;; 12-expr.lisp --- expression nodes
;;;;
;;;; Slots without :child are annotations. TY is set by resolve, TARGET and
;;;; BINDING point to the resolved definition (var-def or item).

(in-package :polyglot)

(define-node expr ()
  ((ty :initform :unknown))
  "Base class of expressions; TY is the (inferred) type.")

(define-node lit-expr (expr)
  ((value) (kind))
  "Literal. KIND is :int :float :string :char :bool or :nil.")

(define-node var-expr (expr)
  ((name) (binding))
  "Reference to a variable, parameter, constant or function by NAME.")

(define-node op-expr (expr)
  ((op) (args :child :list))
  "Operator application. OP is an abstract keyword such as :add or :ne.")

(define-node call-expr (expr)
  ((name) (args :child :list) (target) (call-kind))
  "Call of a named function. CALL-KIND is set by resolve: :function
:intrinsic :extern :local.")

(define-node method-call-expr (expr)
  ((name) (receiver :child :one) (args :child :list) (target))
  "Call of method NAME on RECEIVER (created by resolve from a call-expr).")

(define-node field-expr (expr)
  ((object :child :one) (name) (target))
  "Field access (dot OBJECT NAME); TARGET is the field-def.")

(define-node aref-expr (expr)
  ((object :child :one) (index :child :one))
  "Element access (aref OBJECT INDEX).")

(define-node make-expr (expr)
  ((type-name) (inits :child :list) (target))
  "(make-<type> :field value ...); TARGET is the struct item.")

(define-node field-init ()
  ((name) (value :child :one))
  "One :field value pair of a make-expr.")

(define-node vec-expr (expr)
  ((elem-type) (elems :child :list))
  "(vec-of T x ...).")

(define-node map-expr (expr)
  ((key-type) (value-type))
  "(map-of K V): an empty map.")

(define-node own-expr (expr)
  ((kind) (value :child :one))
  "Ownership forms: KIND is :box :clone :move or :some.")

(define-node super-expr (expr)
  ((args :child :list) (target) (method))
  "(call-super args...): TARGET is the overridden base method.")

(define-node lambda-expr (expr)
  ((params :child :list) (ret :initform :void) (body :child :list)
   (capture :initform :value))
  "Anonymous function.")

(define-node funcall-expr (expr)
  ((fn :child :one) (args :child :list))
  "(funcall f args...).")

(define-node if-expr (expr)
  ((test :child :one) (then :child :one) (else :child :one))
  "IF in value position.")

(define-node block-expr (expr)
  ((stmts :child :list) (value :child :one))
  "LET/PROGN in value position: STMTS in a new scope, then VALUE.")

(define-node target-branch ()
  ((backends) (body :child :list))
  "One branch of target-case. BACKENDS is a list of keywords or T.")

(define-node target-case-expr (expr)
  ((branches :child :list))
  "target-case in value position; every branch body is one expression.")

(define-node target-form-expr (expr)
  ((backend) (form))
  "Form from an extension package (cpp: py: rs: go:), kept raw.")

(define-node raw-expr (expr)
  ((text))
  "(raw \"text\") in value position.")

(define-node comment-expr (expr)
  ((lines))
  "Comment inside an expression; moved before the statement by lower (E11).")
