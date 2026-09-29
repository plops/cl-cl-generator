;;;; 35-vtable.lisp --- method resolution, overrides, call-super targets and
;;;; vtables (K3)
;;;;
;;;; For every method the overridden method (base class or interface) is stored
;;;; in SUPER-TARGET. For every struct/class the VTABLE is an alist
;;;; name -> implementing method for all virtual and interface methods.

(in-package :polyglot)

(defun method-virtual-p (m)
  "Dynamic dispatch: declared virtual/abstract, an interface method, or an
override of such a method."
  (or (function-flag-p m :virtual) (function-flag-p m :abstract)
      (typep (ir-owner-item m) 'interface-item)
      (and (ir-super-target m) (method-virtual-p (ir-super-target m)))))

(defun base-method (item name)
  "Nearest method NAME in the base classes of ITEM (not ITEM itself)."
  (loop for s in (cdr (struct-base-chain item))
        for m = (find name (ir-methods s) :key #'ir-name :test #'string=)
        when m return m))

(defun interface-method-of (item name)
  (find-interface-method (type-interfaces item) name))

(defun link-override (item m)
  (let* ((name (ir-name m))
         (base (base-method item name))
         (iface (interface-method-of item name))
         (super (or base iface)))
    (cond ((and (function-flag-p m :override) (null super))
           (dsl-error (ir-source m) "~a.~a is declared override but overrides nothing" (ir-name item) name))
          ((and base (not (method-virtual-p base)))
           (dsl-error (ir-source m) "~a.~a hides the non-virtual method of ~a; declare it (virtual) there"
                      (ir-name item) name (ir-name (ir-owner-item base))))
          ((and base (not (function-flag-p m :override)))
           (dsl-error (ir-source m) "~a.~a overrides ~a.~a; declare (override)"
                      (ir-name item) name (ir-name (ir-owner-item base)) name)))
    (setf (ir-super-target m) super)))

(defun virtual-names (item)
  "Names of all virtual methods visible in ITEM, base first."
  (let ((names '()))
    (dolist (s (reverse (struct-base-chain item)))
      (dolist (m (ir-methods s))
        (when (method-virtual-p m) (pushnew (ir-name m) names :test #'string=))))
    (dolist (i (type-interfaces item))
      (dolist (m (ir-methods i)) (pushnew (ir-name m) names :test #'string=)))
    (nreverse names)))

(defun most-derived-method (item name)
  (or (loop for s in (struct-base-chain item)
            for m = (find name (ir-methods s) :key #'ir-name :test #'string=)
            when m return m)
      (interface-method-of item name)))

(defun abstract-class-p (item)
  (some (lambda (entry) (function-flag-p (cdr entry) :abstract)) (ir-vtable item)))

(defun build-vtable (item)
  (setf (ir-vtable item)
        (loop for name in (virtual-names item)
              collect (cons name (most-derived-method item name)))))

(defun check-implemented (item)
  "A struct that is instantiated must not leave abstract methods."
  (dolist (entry (ir-vtable item))
    (when (and (function-flag-p (cdr entry) :abstract)
               (typep (ir-owner-item (cdr entry)) 'interface-item))
      (dsl-error (ir-source item) "~a does not implement ~a.~a"
                 (ir-name item) (ir-name (ir-owner-item (cdr entry))) (car entry)))))

(defun link-supers (fn)
  (walk-nodes (lambda (n)
                (when (typep n 'super-expr)
                  (let ((target (ir-super-target fn)))
                    (when (or (null target) (function-flag-p target :abstract))
                      (dsl-error (ir-source n) "call-super in ~a: there is no inherited implementation"
                                 (ir-name fn)))
                    (setf (ir-target n) target))))
              fn))

(defun check-instantiation (project)
  (walk-nodes (lambda (n)
                (when (and (typep n 'make-expr) (abstract-class-p (ir-target n)))
                  (dsl-error (ir-source n) "~a is abstract and cannot be instantiated"
                             (ir-type-name n))))
              project))

(defun compute-vtables (project)
  (let ((structs (loop for m in (ir-modules project)
                       append (remove-if-not (lambda (i) (typep i 'struct-item)) (ir-items m)))))
    (dolist (s structs) (dolist (m (ir-methods s)) (setf (ir-super-target m) nil)))
    (dolist (s structs) (dolist (m (ir-methods s)) (link-override s m)))
    (dolist (s structs)
      (build-vtable s)
      (check-implemented s)
      (mapc #'link-supers (ir-methods s)))
    (check-instantiation project)
    project))

(define-pass :vtable (:order 50) (project)
             "Overrides, call-super targets and per class vtables."
             (compute-vtables project))
