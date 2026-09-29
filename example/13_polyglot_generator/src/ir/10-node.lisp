;;;; 10-node.lisp --- IR node infrastructure: define-node, traversal, rebuild

(in-package :polyglot)

(defclass node ()
  ((source :initarg :source :initform nil :accessor ir-source
           :documentation "The DSL source form this node was parsed from."))
  (:documentation "Base class of all IR nodes."))

(defun node-p (x) (typep x 'node))

(setf (get 'node 'node-slots) '((source nil)))

(defun slot-accessor-name (slot)
  "Accessor IR-<SLOT>, interned in the package that is current while the
DEFINE-NODE form is expanded."
  (intern (format nil "IR-~a" (symbol-name slot)) *package*))

(defun inherited-node-slots (supers)
  (loop for s in supers append (get s 'node-slots)))

(defmacro define-node (name supers slots &optional documentation)
  "Define the IR node class NAME. Every slot is (SLOT &key child initform);
CHILD is NIL, :one (a single node) or :list (a list of nodes). Defines the
class, accessors IR-<SLOT>, the constructor MAKE-<NAME> and records the child
slots for NODE-CHILDREN, WALK-NODES and MAP-TREE."
  (let* ((supers (or supers '(node)))
         (own (loop for spec in slots
                    collect (destructuring-bind (slot &key child initform)
                                (alexandria:ensure-list spec)
                              (list slot child initform))))
         (all (remove-duplicates (append (inherited-node-slots supers)
                                         (mapcar (lambda (s) (list (first s) (second s)))
                                                 own))
                                 :key #'first :from-end t)))
    `(progn
       (eval-when (:compile-toplevel :load-toplevel :execute)
         (setf (get ',name 'node-slots) ',all))
       (defclass ,name ,supers
         ,(loop for (slot nil initform) in own
                collect `(,slot :initarg ,(alexandria:make-keyword slot)
                                :initform ,initform
                                :accessor ,(slot-accessor-name slot)))
         ,@(when documentation `((:documentation ,documentation))))
       (defun ,(alexandria:symbolicate "MAKE-" name) (&rest initargs)
         (apply #'make-instance ',name initargs))
       ',name)))

(defun node-slot-specs (node)
  "List of (slot child-kind) of NODE including inherited slots."
  (get (class-name (class-of node)) 'node-slots))

(defun node-children (node)
  "Direct child nodes of NODE in slot order."
  (loop for (slot kind) in (node-slot-specs node)
        for value = (slot-value node slot)
        append (case kind
                 (:one (when (node-p value) (list value)))
                 (:list (remove-if-not #'node-p value))
                 (t nil))))

(defun walk-nodes (fn node)
  "Call FN on NODE and all descendants in pre-order. When FN returns :SKIP the
children of that node are not visited."
  (when (node-p node)
    (unless (eq :skip (funcall fn node))
      (dolist (child (node-children node))
        (walk-nodes fn child))))
  node)

(defun rebuild-node (node &rest changes)
  "Shallow copy of NODE with the slots in the plist CHANGES replaced. NODE
itself is not modified."
  (let ((copy (allocate-instance (class-of node))))
    (loop for (slot) in (node-slot-specs node)
          do (setf (slot-value copy slot)
                   (let ((key (alexandria:make-keyword slot)))
                     (if (member key changes)
                         (getf changes key)
                         (slot-value node slot)))))
    ;; annotation slots that are not node slots (none by design) stay unbound
    copy))

(defun map-list-slot (fn items)
  "Map FN over ITEMS; a result that is a list (not a node) is spliced."
  (loop for item in items
        for new = (if (node-p item) (map-tree fn item) item)
        if (and (listp new) (node-p item)) append new
        else collect new))

(defun map-tree (fn node)
  "Post-order transformation: rebuild NODE with its children transformed, then
return (FN rebuilt). FN may return a node, or for elements of list slots a list
of nodes that is spliced. The input tree is never modified."
  (let ((changes
         (loop for (slot kind) in (node-slot-specs node)
               for value = (slot-value node slot)
               append (case kind
                        (:one (list (alexandria:make-keyword slot)
                                    (if (node-p value) (map-tree fn value) value)))
                        (:list (list (alexandria:make-keyword slot)
                                     (map-list-slot fn value)))
                        (t nil)))))
    (funcall fn (apply #'rebuild-node node changes))))

(defun copy-node-tree (node)
  "Deep copy of NODE."
  (map-tree #'identity node))

(defun node-summary (node)
  (let ((*print-length* 4) (*print-level* 2))
    (prin1-to-string (ir-source node))))

(defmethod print-object ((n node) stream)
  (print-unreadable-object (n stream :type t)
    (format stream "~a" (node-summary n))))
