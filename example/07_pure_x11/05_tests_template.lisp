;;;; 05_tests_template.lisp — Unit and integration tests template specification

(in-package :cl-cl-generator/example-x11-gen)

(defparameter *tests-template-code*
  `(toplevel
     ,@(make-header-comments)
     (defpackage :pure-x11-gen/tests
       (:use :cl :pure-x11-gen)
       (:export #:run-all-tests))
     (in-package :pure-x11-gen/tests)

     (defparameter *test-failures* 0)

     (defmacro assert-test (form &optional msg)
       `(if ,form
            (format t "PASS: ~a~%" ,(or msg (format nil "~s" form)))
            (progn
              (format t "FAIL: ~a~%" ,(or msg (format nil "~s" form)))
              (incf *test-failures*))))

     (defun test-parse-node ()
       (format t "--- Running test-parse-node ---~%")
       (let ((w (pure-x11-gen::parse-node '(panel :name :main-panel :x 10 :y 20 :w 100 :h 200 :bg 123 (button :name :b1)))))
         (assert-test (string-equal (symbol-name (pure-x11-gen::widget-type w)) "PANEL") "Widget type is PANEL")
         (assert-test (eq (pure-x11-gen::widget-name w) :main-panel) "Widget name is :main-panel")
         (assert-test (= (pure-x11-gen::widget-x w) 10) "Widget x is 10")
         (assert-test (= (pure-x11-gen::widget-y w) 20) "Widget y is 20")
         (assert-test (= (pure-x11-gen::widget-w w) 100) "Widget w is 100")
         (assert-test (= (pure-x11-gen::widget-h w) 200) "Widget h is 200")
         (assert-test (equal (pure-x11-gen::widget-children w) '((button :name :b1))) "Children parsed correctly")))

     (defun test-collect-focusable ()
       (format t "--- Running test-collect-focusable ---~%")
       (let* ((layout '(panel :name :main-panel :x 0 :y 0 :w 400 :h 300
                        (label :name :l1 :text "Title" :x 10 :y 10)
                        (button :name :b1 :x 10 :y 30 :w 100 :h 30)
                        (checkbox :name :c1 :x 10 :y 70 :w 100 :h 20)
                        (text-input :name :t1 :x 10 :y 100 :w 100 :h 30)))
              (focusable (pure-x11-gen::collect-focusable-widgets layout)))
         (assert-test (= (length focusable) 3) "Found 3 focusable widgets")
         (assert-test (eq (pure-x11-gen::widget-name (first focusable)) :b1) "First is :b1")
         (assert-test (eq (pure-x11-gen::widget-name (second focusable)) :c1) "Second is :c1")
         (assert-test (eq (pure-x11-gen::widget-name (third focusable)) :t1) "Third is :t1")))

     (defun test-hit-testing ()
       (format t "--- Running test-hit-testing ---~%")
       (let* ((layout '(panel :name :main-panel :x 0 :y 0 :w 400 :h 300
                        (button :name :b1 :x 10 :y 30 :w 100 :h 30)
                        (button :name :b2 :x 120 :y 30 :w 100 :h 30))))
         (assert-test (eq (pure-x11-gen::widget-name (pure-x11-gen::find-widget-at layout 15 45)) :b1) "Hit button 1")
         (assert-test (eq (pure-x11-gen::widget-name (pure-x11-gen::find-widget-at layout 150 45)) :b2) "Hit button 2")
         (assert-test (eq (pure-x11-gen::widget-name (pure-x11-gen::find-widget-at layout 5 5)) :main-panel) "Hit panel background")
         (assert-test (null (pure-x11-gen::find-widget-at layout 500 500)) "No hit outside bounds")))

     (defun test-cone-focus-search ()
       (format t "--- Running test-cone-focus-search ---~%")
       (let* ((layout '(panel :name :main-panel :x 0 :y 0 :w 400 :h 300
                        (button :name :b1 :x 40 :y 40 :w 20 :h 20)
                        (button :name :b2 :x 140 :y 40 :w 20 :h 20)
                        (button :name :b3 :x 40 :y 140 :w 20 :h 20))))
         (assert-test (eq (pure-x11-gen::find-nearest-widget layout :b1 :right) :b2) "b1 -> right is b2")
         (assert-test (eq (pure-x11-gen::find-nearest-widget layout :b1 :down) :b3) "b1 -> down is b3")
         (assert-test (eq (pure-x11-gen::find-nearest-widget layout :b2 :left) :b1) "b2 -> left is b1")
         (assert-test (eq (pure-x11-gen::find-nearest-widget layout :b3 :up) :b1) "b3 -> up is b1")))

     (defun run-all-tests ()
       (setf *test-failures* 0)
       (test-parse-node)
       (test-collect-focusable)
       (test-hit-testing)
       (test-cone-focus-search)
       (if (zerop *test-failures*)
           (format t "ALL TESTS PASSED!~%")
           (progn
             (format t "SOME TESTS FAILED: ~a failures~%" *test-failures*)
             (sb-ext:exit :code 1))))))
