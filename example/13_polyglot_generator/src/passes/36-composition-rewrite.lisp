;;;; 36-composition-rewrite.lisp --- rewriting bodies and building the items

(in-package :polyglot)

(defgeneric compose-node (n)
  (:documentation "Copy of N rewritten for composition (annotations are recomputed by resolve)."))

(defun compose-children (n)
  "Copy of N with all node slots composed and type slots rewritten."
  (let ((changes
         (loop for (slot kind) in (node-slot-specs n)
               for v = (slot-value n slot)
               append (case kind
                        (:one (list (alexandria:make-keyword slot) (if (node-p v) (compose-node v) v)))
                        (:list (list (alexandria:make-keyword slot)
                                     (mapcar (lambda (x) (if (node-p x) (compose-node x) x)) v)))))))
    (let ((copy (apply #'rebuild-node n changes)))
      (dolist (slot '(elem-type key-type value-type ret))
        (when (and (slot-exists-p copy slot) (slot-boundp copy slot))
          (setf (slot-value copy slot) (compose-type (slot-value copy slot)))))
      copy)))

(defmethod compose-node ((n node)) (compose-children n))

(defmethod compose-node ((n var-def))
  (let ((copy (compose-children n)))
    (multiple-value-bind (ty mode) (compose-param-type n)
      (setf (ir-declared-ty copy) ty (ir-mode copy) mode (ir-ty copy) :unknown))
    copy))

(defmethod compose-node ((n var-expr))
  (if (and *compose-receiver* (eq (ir-binding n) *compose-receiver*))
      (mk-var "this")
      (compose-children n)))

(defmethod compose-node ((n field-expr))
  (let* ((field (ir-target n)) (owner (and field (ir-owner field))) (obj (ir-object n)))
    (cond ((not (in-hierarchy-p owner)) (compose-children n))
          ((polymorphic-handle-p obj)
           (let ((write (gethash n *write-places*)))
             (note-accessor owner write)
             (mk-field (mk-call (accessor-name owner write) (list (compose-node obj))) (ir-name field))))
          (t (mk-field (base-path (compose-node obj) (type-item (strip-indirection (ir-ty obj))) owner)
                       (ir-name field))))))

(defmethod compose-node ((n method-call-expr))
  (let* ((m (ir-target n)) (owner (ir-owner-item m))
         (args (mapcar #'compose-node (cons (ir-receiver n) (ir-args n)))))
    (cond ((not (in-hierarchy-p owner)) (compose-children n))
          ((method-virtual-p m) (mk-call (ir-name m) args (ir-source n)))
          (t (mk-call (free-fn-name owner m) args (ir-source n))))))

(defmethod compose-node ((n super-expr))
  (let ((target (ir-target n)))
    (mk-call (free-fn-name (ir-owner-item target) target)
             (cons (mk-var "this") (mapcar #'compose-node (ir-args n))) (ir-source n))))

(defun split-inits (class inits)
  "Field inits of CLASS: (values own-inits base-inits)."
  (let ((own (mapcar #'ir-name (ir-fields class))))
    (values (remove-if-not (lambda (i) (member (ir-name i) own :test #'string=)) inits)
            (remove-if (lambda (i) (member (ir-name i) own :test #'string=)) inits))))

(defun compose-make (class inits source)
  (multiple-value-bind (own base) (split-inits class inits)
    (make-make-expr
     :type-name (ir-name class) :source source
     :inits (append (when (ir-base-item class)
                      (list (make-field-init :name "base" :source source
                                             :value (compose-make (ir-base-item class) base source))))
                    (mapcar (lambda (i) (make-field-init :name (ir-name i) :value (compose-node (ir-value i))
                                                         :source (ir-source i)))
                            own)))))

(defmethod compose-node ((n make-expr))
  (if (in-hierarchy-p (ir-target n))
      (compose-make (ir-target n) (ir-inits n) (ir-source n))
      (compose-children n)))

;;; items

(defun mk-receiver (class mode)
  (make-var-def :name "self" :kind :receiver :receiver-p t :mode mode
                :declared-ty (list :named (ir-name class)) :source 'self))

(defun mk-method (class name mode ret body &key params flags)
  (make-method-item :name name :owner (ir-name class) :params (cons (mk-receiver class mode) params)
                    :ret ret :ret-declared t :body body :flags flags :source (list 'defmethod name)))

(defun copy-params (params)
  (mapcar (lambda (p) (compose-node p)) params))

(defun accessor-methods (class &key abstract)
  "Accessors of CLASS that are needed; ABSTRACT: declarations for the interface."
  (loop for need in (reverse (gethash class *accessor-needs*))
        for write = (eq need :write)
        collect (mk-method class (accessor-name class write) (if write :inout :in)
                           (list (if write :mut-ref :ref) (list :named (ir-name class)) nil)
                           nil
                           :flags (when abstract '(:abstract)))))

(defun introduced-virtuals (class)
  (remove-if-not (lambda (m) (and (method-virtual-p m) (null (ir-super-target m)))) (ir-methods class)))

(defun make-dyn-interface (class)
  (make-interface-item
   :name (dyn-name class) :visibility (ir-visibility class) :source (ir-source class)
   :extends (when (ir-base-item class) (list (dyn-name (ir-base-item class))))
   :methods (append (accessor-methods class :abstract t)
                    (loop for m in (introduced-virtuals class)
                          collect (mk-method class (ir-name m) (ir-mode (method-receiver m)) (compose-type (ir-ret m))
                                             nil :params (copy-params (rest (ir-params m)))
                                             :flags '(:abstract))))))

(defun accessor-impls (class)
  "Accessor implementations for CLASS and its ancestors (self or self.base...)."
  (loop for a in (struct-base-chain class)
        append (loop for m in (accessor-methods a)
                     collect (let ((write (eq :inout (ir-mode (method-receiver m)))))
                               (setf (ir-owner m) (ir-name class)
                                     (ir-params m) (cons (mk-receiver class (if write :inout :in)) (rest (ir-params m)))
                                     (ir-body m) (list (make-return-stmt :value (base-path (mk-var "self") class a)
                                                                         :source 'return)))
                               m))))

(defun delegation-impls (class)
  "Implementations of the virtual methods (and of the methods of ordinary
interfaces) that call the free function of the most derived implementation.
Interface default methods stay defaults."
  (loop for (name . impl) in (ir-vtable class)
        for root = (root-method impl)
        for params = (copy-params (rest (ir-params root)))
        unless (or (function-flag-p impl :abstract) (typep (ir-owner-item impl) 'interface-item))
        collect (mk-method class name (ir-mode (method-receiver root)) (compose-type (ir-ret root))
                           (list (make-return-stmt
                                  :value (mk-call (free-fn-name (ir-owner-item impl) impl)
                                                  (cons (mk-var "self") (mapcar (lambda (p) (mk-var (ir-name p))) params)))
                                  :source 'return))
                           :params params)))

(defun make-data-struct (class)
  (make-struct-item
   :name (ir-name class) :visibility (ir-visibility class) :doc (ir-doc class) :source (ir-source class)
   :implements (append (mapcar #'ir-name (ir-implements-items class)) (list (dyn-name class)))
   :fields (append (when (ir-base-item class)
                     (list (make-field-def :name "base" :ty (list :named (ir-name (ir-base-item class))) :source 'base)))
                   (mapcar #'compose-node (ir-fields class)))
   :methods (append (accessor-impls class) (delegation-impls class))))

(defun make-free-function (class m)
  (let* ((recv (method-receiver m))
         (*compose-receiver* recv)
         (this (make-var-def :name "this" :kind :param :mode :in :source 'this
                             :declared-ty (list (if (eq :inout (ir-mode recv)) :mut-ref :ref)
                                                (list :dyn (dyn-name class)) nil))))
    (when (eq :sink (ir-mode recv))
      (unsupported (ir-source m) ":sink receivers cannot be lowered to composition"))
    (make-function-item :name (free-fn-name class m) :visibility (ir-visibility class)
                        :params (cons this (copy-params (rest (ir-params m))))
                        :ret (compose-type (ir-ret m)) :ret-declared t :doc (ir-doc m)
                        :body (mapcar #'compose-node (ir-body m)) :source (ir-source m))))

;;; the pass

(defun compose-item (item)
  (let ((*compose-receiver* nil))
    (compose-node item)))

(defun class-replacement (class free-functions)
  (append (list (make-dyn-interface class) (make-data-struct class)) free-functions))

(defun compose-project (project)
  (let ((*hierarchy* (hierarchy-classes project)))
    (if (null *hierarchy*)
        project
        (let ((*write-places* (make-hash-table))
              (*accessor-needs* (make-hash-table))
              (free (make-hash-table)))
          (collect-write-places project)
          ;; 1. rewrite all bodies; this also records the needed accessors
          (dolist (c *hierarchy*)
            (setf (gethash c free)
                  (loop for m in (ir-methods c)
                        unless (function-flag-p m :abstract) collect (make-free-function c m))))
          (dolist (module (ir-modules project))
            (setf (ir-items module)
                  (loop for item in (ir-items module)
                        collect (if (in-hierarchy-p item) item (compose-item item)))))
          ;; 2. interfaces and data structs
          (dolist (module (ir-modules project) project)
            (setf (ir-items module)
                  (loop for item in (ir-items module)
                        append (if (in-hierarchy-p item)
                                   (class-replacement item (gethash item free))
                                   (list item)))))))))

(define-pass :composition (:order 60 :when (not (capability-p :implementation-inheritance))) (project)
             "Lower implementation inheritance to composition (Rust, Go)."
             (compose-project project))

(define-pass :re-resolve (:order 61 :when (not (capability-p :implementation-inheritance))) (project)
             "Resolve the composed project again."
             (resolve-project project))

(define-pass :re-vtable (:order 62 :when (not (capability-p :implementation-inheritance))) (project)
             "Recompute overrides for the generated interfaces."
             (compute-vtables project))

(define-pass :re-mutability (:order 63 :when (not (capability-p :implementation-inheritance))) (project)
             "Recompute mutability for the generated code."
             (infer-mutability project))
