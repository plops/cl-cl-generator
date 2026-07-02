(defpackage :cockpit-tui/tests
  (:use :cl :rove :cockpit-tui))

(in-package :cockpit-tui/tests)

(deftest test-state-transitions
 (testing "Increment and decrement interval-sec using + and -"
  (let ((model (make-instance 'cockpit-model :interval-sec 3)))
    (multiple-value-bind (m cmd) (tuition:update-message model
                                                         (make-instance
                                                          'tuition:key-press-msg
                                                          :code #\+))
      (declare (ignore cmd))
      (ok (= 2 (cockpit-tui::interval-sec m))))
    (multiple-value-bind (m cmd) (tuition:update-message model
                                                         (make-instance
                                                          'tuition:key-press-msg
                                                          :code #\-))
      (declare (ignore cmd))
      (ok (= 3 (cockpit-tui::interval-sec m))))))
 (testing "Help overlay toggle"
  (let ((model (make-instance 'cockpit-model :show-help-p nil)))
    (multiple-value-bind (m cmd) (tuition:update-message model
                                                         (make-instance
                                                          'tuition:key-press-msg
                                                          :code #\h))
      (declare (ignore cmd))
      (ok (cockpit-tui::show-help-p m))
      (multiple-value-bind (m2 cmd2) (tuition:update-message m
                                                             (make-instance
                                                              'tuition:key-press-msg
                                                              :code :f1))
        (declare (ignore cmd2))
        (ok (not (cockpit-tui::show-help-p m2))))))))

(deftest test-rendering
 (testing "Help overlay is present in the rendered view"
  (let ((model (make-instance 'cockpit-model :show-help-p t)))
    (let ((view-str (tuition:view-state-content (tuition:view model))))
      (ok (search "HELP INSTRUCTIONS:" view-str)))))
 (testing "Selection indicator shows up in rendered view"
  (let ((model (make-instance 'cockpit-model :selected-index 0)))
    (setf (cockpit-tui::top-processes model)
            (list
             (cockpit-tui::make-process-info :pid 100 :name "test-proc"
              :rx-rate 1024 :tx-rate 512 :read-bytes 0 :write-bytes 0
              :oom-score 0 :accumulated-rx 1024 :rx-history '(1024))))
    (let ((view-str (tuition:view-state-content (tuition:view model))))
      (ok (search "-> " view-str))
      (ok (search "test-proc" view-str))))))