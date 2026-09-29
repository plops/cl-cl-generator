;;;; 14-items.lisp --- items, modules and projects

(in-package :polyglot)

(define-node item ()
  ((name) (visibility :initform :private) (target-name) (doc) (module))
  "Base class of module level definitions. MODULE is set by resolve.")

(define-node function-item (item)
  ((params :child :list) (ret :initform :void) (body :child :list)
   (flags) (borrows-from) (outlives) (ret-declared))
  "Function. FLAGS is a list of :pure :virtual :override :abstract.")

(define-node method-item (function-item)
  ((owner) (owner-item) (super-target) (free-name))
  "Method; the first parameter is the receiver (receiver-p). OWNER is the
spelling of the owning type, OWNER-ITEM the item (set by resolve).")

(define-node field-def ()
  ((name) (ty) (default :child :one) (target-name) (owner))
  "Field of a struct or class; OWNER is the owning item.")

(define-node struct-item (item)
  ((fields :child :list) (methods :child :list) (implements) (base)
   (class-p) (base-item) (implements-items) (vtable) (composed))
  "defstruct (CLASS-P NIL) or defclass (CLASS-P T, optional BASE).
BASE-ITEM and VTABLE are computed by resolve and the vtable pass.")

(define-node interface-item (item)
  ((extends) (methods :child :list) (extends-items) (generated))
  "definterface; methods without body are abstract.")

(define-node const-item (item)
  ((ty) (value :child :one))
  "defconst.")

(define-node extern-item (item)
  ((params :child :list) (ret :initform :void) (expansions))
  "defextern: native function with one spelling per backend.")

(define-node module-item (item)
  ((exports) (imports) (std-imports) (items :child :list) (entry-p)
   (project))
  "A module: a namespace and translation unit of the generated program.")

(define-node project-item (item)
  ((modules :child :list) (entry) (symbols))
  "Project: modules plus the entry module.")

(defun item-kind (item)
  "Keyword describing ITEM for messages and naming roles."
  (etypecase item
    (method-item :method)
    (function-item :function)
    (struct-item (if (struct-class-p item) :class :struct))
    (interface-item :interface)
    (const-item :constant)
    (extern-item :extern)
    (module-item :module)
    (project-item :project)))

(defun struct-class-p (item) (ir-class-p item))

(defun function-flag-p (fn flag)
  (member flag (ir-flags fn)))

(defun method-receiver (method)
  (first (ir-params method)))

(defun module-entry-function (module)
  (find-if (lambda (i) (and (typep i 'function-item)
                            (not (typep i 'method-item))
                            (string= (ir-name i) "main")))
           (ir-items module)))
