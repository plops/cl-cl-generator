;;;; test-node.lisp --- tests of src/ir/10-node.lisp

(in-package :polyglot.tests)

(def-suite :polyglot.unit.node :in :polyglot.unit)
(in-suite :polyglot.unit.node)

(define-node test-leaf () ((value)))
(define-node test-pair () ((left :child :one) (right :child :one)))
(define-node test-seq () ((items :child :list) (tag :initform :none)))

(defun sample-tree ()
  (make-test-seq :items (list (make-test-leaf :value 1)
                              (make-test-pair :left (make-test-leaf :value 2)
                                              :right (make-test-leaf :value 3)))
                 :source '(seq 1 (pair 2 3))))

(test construction-and-accessors
  (let ((tree (sample-tree)))
    (is (eq :none (ir-tag tree)))
    (is (= 2 (length (node-children tree))))
    (is (equal '(seq 1 (pair 2 3)) (ir-source tree)))))

(test walk-pre-order
  (let ((seen '()))
    (walk-nodes (lambda (n) (when (typep n 'test-leaf) (push (ir-value n) seen)))
                (sample-tree))
    (is (equal '(1 2 3) (reverse seen)))))

(test walk-skip
  (let ((count 0))
    (walk-nodes (lambda (n) (incf count) (when (typep n 'test-pair) :skip))
                (sample-tree))
    (is (= 3 count))))

(test rebuild-does-not-modify-original
  (let* ((leaf (make-test-leaf :value 1 :source 'one))
         (copy (rebuild-node leaf :value 99)))
    (is (= 1 (ir-value leaf)))
    (is (= 99 (ir-value copy)))
    (is (eq 'one (ir-source copy)))))

(test map-tree-transforms-and-splices
  (let* ((tree (sample-tree))
         (new (map-tree (lambda (n)
                          (if (and (typep n 'test-leaf) (eql 1 (ir-value n)))
                              (list (make-test-leaf :value 10) (make-test-leaf :value 11))
                              n))
                        tree)))
    (is (= 3 (length (ir-items new))))
    (is (= 2 (length (ir-items tree))))
    (is (= 1 (ir-value (first (ir-items tree)))))))

(test print-object-readable
  (is (search "TEST-SEQ" (princ-to-string (sample-tree)))))
