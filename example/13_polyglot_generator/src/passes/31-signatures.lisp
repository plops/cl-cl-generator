;;;; 31-signatures.lisp --- methods inherit an undeclared result type
;;;;
;;;; (defmethod area ((c circle :in)) ...) without (values T) takes the result
;;;; type of the method it implements (interface) or overrides (base class).
;;;; Runs before desugar so that implicit tail returns are added correctly.

(in-package :polyglot)

(defun syntactic-type-item (project module name)
  "Struct or interface NAME in MODULE or in one of the modules it imports."
  (flet ((in (m)
           (find-if (lambda (i) (and (typep i '(or struct-item interface-item))
                                     (string= (ir-name i) name)))
                    (ir-items m))))
    (or (in module)
        (loop for imp in (ir-imports module)
              for m = (find imp (ir-modules project) :key #'ir-name :test #'string=)
              for hit = (and m (in m))
              when hit return hit))))

(defun declared-super-method (project module item name &optional (depth 0))
  "The method NAME with a declared result type in a supertype of ITEM."
  (when (> depth 50)
    (dsl-error (ir-source item) "cyclic inheritance involving ~a" (ir-name item)))
  (let ((supers (append (when (typep item 'struct-item)
                          (append (ir-implements item) (alexandria:ensure-list (ir-base item))))
                        (when (typep item 'interface-item) (ir-extends item)))))
    (loop for s in supers
          for super = (syntactic-type-item project module s)
          for m = (and super (find name (ir-methods super) :key #'ir-name :test #'string=))
          when (and m (ir-ret-declared m)) return m
          do (let ((deeper (and super (declared-super-method project module super name (1+ depth)))))
               (when deeper (return deeper))))))

(defun inherit-signatures (project)
  (dolist (module (ir-modules project) project)
    (dolist (item (ir-items module))
      (when (typep item '(or struct-item interface-item))
        (dolist (m (ir-methods item))
          (unless (ir-ret-declared m)
            (let ((super (declared-super-method project module item (ir-name m))))
              (when super
                (setf (ir-ret m) (ir-ret super)
                      (ir-ret-declared m) t)))))))))

(define-pass :signatures (:order 5) (project)
             "Undeclared method result types are inherited from interfaces and bases."
             (inherit-signatures project))
