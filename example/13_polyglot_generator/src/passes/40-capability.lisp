;;;; 40-capability.lisp --- reject constructs the backend cannot express (R4)
;;;;
;;;; Config keys: :unsupported-nodes (list of node class names) and the
;;;; capabilities :inout-scalars (an :inout parameter of a copy type) and
;;;; :inout-rebind (assigning a new value to an :inout parameter itself).

(in-package :polyglot)

(defun capability-check-node (n)
  (typecase n
    ((or target-form-expr target-form-stmt)
     (unless (eq (ir-backend n) *current-backend*)
       (unsupported (ir-source n) "~(~a~)-specific form is not available for ~(~a~)"
                    (ir-backend n) *current-backend*)))
    (var-def
     (when (and (eq :param (ir-kind n)) (eq :inout (ir-mode n)) (copy-type-p (ir-ty n))
                (not (capability-p :inout-scalars)))
       (unsupported (ir-source n) ":inout parameter ~a of the copy type ~a (return the new value instead)"
                    (ir-name n) (type-string (ir-ty n)))))
    (assign-stmt
     (let ((b (ir-binding-or-nil (ir-place n))))
       (when (and (typep b 'var-def) (eq :param (ir-kind b)) (eq :inout (ir-mode b))
                  (not (capability-p :inout-rebind)))
         (unsupported (ir-source n) "assigning a new value to the :inout parameter ~a; assign its fields"
                      (ir-name b))))))
  (when (member (class-name (class-of n)) (config-get :unsupported-nodes))
    (unsupported (ir-source n) "~(~a~) is not supported" (class-name (class-of n)))))

(define-pass :capability (:order 90) (project)
             "Signal unsupported-construct for everything the backend cannot express."
             (walk-nodes #'capability-check-node project))
