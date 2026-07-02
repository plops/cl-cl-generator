(eval-when (:compile-toplevel :execute :load-toplevel)
  (let ((current-dir (make-pathname :directory (pathname-directory *load-pathname*))))
    (push (merge-pathnames "../../" current-dir) asdf:*central-registry*))
  (ql:quickload '(:cl-cl-generator :tuition))
  (unless (find-package :cockpit-tui)
    (make-package :cockpit-tui :use '(:cl :tuition))))

(defpackage :cockpit-generator-02
  (:use :cl :cl-cl-generator))

(in-package :cockpit-generator-02)

(defparameter *output-dir* (asdf:system-relative-pathname :cl-cl-generator "example/04_tui_cockpit/source02/"))

;; Define package.lisp code
(defparameter *package-code*
  `(toplevel
     (defpackage :cockpit-tui
       (:use :cl :tuition)
       (:export :run-cockpit :cockpit-model :process-info))))

;; Define cockpit.asd code
(defparameter *asd-code*
  `(toplevel
     (asdf:defsystem cockpit-tui
       :version "0.1.0"
       :description "An interactive bandwidth-optimized Linux system cockpit TUI using cl-tuition."
       :depends-on ("alexandria" "uiop" "tuition")
       :serial t
       :components ((:file "package")
                    (:file "cockpit"))
       :in-order-to ((asdf:test-op (asdf:test-op "cockpit-tui/tests"))))

     (asdf:defsystem cockpit-tui/tests
       :depends-on ("cockpit-tui" "rove")
       :components ((:file "tests"))
       :perform (asdf:test-op (op c) (uiop:symbol-call :rove :run c)))))

;; Define cockpit.lisp code
(defparameter *cockpit-code*
  `(toplevel
     (in-package :cockpit-tui)

     (comment "=====================================================")
     (comment " Generated Bandwidth-Optimized Interactive Linux TUI  ")
     (comment "=====================================================")

     (tui:defmessage tick-msg ())

     (defstruct process-info
       pid
       name
       rx-rate
       tx-rate
       read-bytes
       write-bytes
       oom-score
       accumulated-rx
       rx-history)

     (defclass cockpit-model ()
       ((cpu-history :initarg :cpu-history :initform nil :accessor cpu-history)
        (net-rx-history :initarg :net-rx-history :initform nil :accessor net-rx-history)
        (net-tx-history :initarg :net-tx-history :initform nil :accessor net-tx-history)
        (last-steal :initarg :last-steal :initform 0 :accessor last-steal)
        (last-total :initarg :last-total :initform 0 :accessor last-total)
        (last-net-rx :initarg :last-net-rx :initform 0 :accessor last-net-rx)
        (last-net-tx :initarg :last-net-tx :initform 0 :accessor last-net-tx)
        (io-pressure-some :initarg :io-pressure-some :initform 0.0 :accessor io-pressure-some)
        (io-pressure-full :initarg :io-pressure-full :initform 0.0 :accessor io-pressure-full)
        (vmstat-pswpin :initarg :vmstat-pswpin :initform 0 :accessor vmstat-pswpin)
        (vmstat-pswpout :initarg :vmstat-pswpout :initform 0 :accessor vmstat-pswpout)
        (top-processes :initarg :top-processes :initform nil :accessor top-processes)
        (selected-index :initarg :selected-index :initform 0 :accessor selected-index)
        (interval-sec :initarg :interval-sec :initform 3 :accessor interval-sec)
        (show-help-p :initarg :show-help-p :initform nil :accessor show-help-p)
        (status-message :initarg :status-message :initform "Started Cockpit" :accessor status-message)
        ;; Hash tables for per-process history tracking
        (last-proc-io :initarg :last-proc-io :initform (make-hash-table :test 'equal) :accessor last-proc-io)
        (accumulated-rx :initarg :accumulated-rx :initform (make-hash-table :test 'equal) :accessor accumulated-rx)
        (rx-histories :initarg :rx-histories :initform (make-hash-table :test 'equal) :accessor rx-histories)
        ;; Custom root path for proc mocking in tests
        (proc-root :initarg :proc-root :initform "" :accessor proc-root)))

     (comment "Proc parsing logic")
     (defun parse-cpu-steal (&optional (proc-root ""))
       (with-open-file (stream (format nil "~a/proc/stat" proc-root) :direction :input :if-does-not-exist nil)
         (when stream
           (let ((line (read-line stream nil)))
             (when (and line (string= "cpu " (subseq line 0 (min 4 (length line)))))
               (let* ((parts (uiop:split-string line :separator '(#\Space)))
                      (parts (remove "" parts :test #'string=))
                      (user (parse-integer (nth 1 parts)))
                      (nice (parse-integer (nth 2 parts)))
                      (sys (parse-integer (nth 3 parts)))
                      (idle (parse-integer (nth 4 parts)))
                      (iowait (parse-integer (nth 5 parts)))
                      (irq (parse-integer (nth 6 parts)))
                      (softirq (parse-integer (nth 7 parts)))
                      (steal (parse-integer (nth 8 parts)))
                      (total (+ user nice sys idle iowait irq softirq steal)))
                 (values steal total)))))))

     (defun parse-io-pressure (&optional (proc-root ""))
       (with-open-file (stream (format nil "~a/proc/pressure/io" proc-root) :direction :input :if-does-not-exist nil)
         (if stream
             (let ((some-line (read-line stream nil))
                   (full-line (read-line stream nil)))
               (flet ((extract-avg10 (line)
                        (when line
                          (let ((pos (search "avg10=" line)))
                            (when pos
                              (let ((end (search " " line :start2 pos)))
                                (read-from-string (subseq line (+ pos 6) end))))))))
                 (values (or (extract-avg10 some-line) 0.0) (or (extract-avg10 full-line) 0.0))))
             (values 0.0 0.0))))

     (defun parse-vmstat (&optional (proc-root ""))
       (let ((pswpin 0)
             (pswpout 0))
         (with-open-file (stream (format nil "~a/proc/vmstat" proc-root) :direction :input :if-does-not-exist nil)
           (when stream
             (loop for line = (read-line stream nil)
                   while line
                   do (let ((parts (uiop:split-string line :separator '(#\Space))))
                        (cond
                          ((string= (first parts) "pswpin")
                           (setf pswpin (parse-integer (second parts))))
                          ((string= (first parts) "pswpout")
                           (setf pswpout (parse-integer (second parts)))))))))
         (values pswpin pswpout)))

     (defun parse-net-dev (&optional (proc-root ""))
       (let ((rx 0) (tx 0))
         (with-open-file (stream (format nil "~a/proc/net/dev" proc-root) :direction :input :if-does-not-exist nil)
           (when stream
             (read-line stream nil)
             (read-line stream nil)
             (loop for line = (read-line stream nil)
                   while line
                   do (let ((colon (position #\Colon line)))
                        (when colon
                          (let* ((iface (string-trim '(#\Space) (subseq line 0 colon)))
                                 (data (subseq line (1+ colon)))
                                 (parts (uiop:split-string data :separator '(#\Space)))
                                 (parts (remove "" parts :test #'string=)))
                            (unless (string= iface "lo")
                              (incf rx (parse-integer (nth 0 parts)))
                              (incf tx (parse-integer (nth 8 parts))))))))))
         (values rx tx)))

     (defun parse-sockets (&optional (proc-root ""))
       (let ((inodes (make-hash-table :test 'equal)))
         (dolist (file '("/proc/net/tcp" "/proc/net/tcp6" "/proc/net/udp" "/proc/net/udp6"))
           (with-open-file (stream (format nil "~a~a" proc-root file) :direction :input :if-does-not-exist nil)
             (when stream
               (read-line stream nil)
               (loop for line = (read-line stream nil)
                     while line
                     do (let* ((parts (uiop:split-string line :separator '(#\Space)))
                               (parts (remove "" parts :test #'string=))
                               (local-addr (nth 1 parts))
                               (remote-addr (nth 2 parts))
                               (inode (nth 9 parts)))
                          (when (and inode (not (string= inode "0")))
                            (setf (gethash inode inodes) (cons local-addr remote-addr))))))))
         inodes))

     (defun map-pids-to-sockets (socket-map &optional (proc-root ""))
       (let ((pid-map (make-hash-table :test 'equal)))
         (dolist (pid-dir (uiop:subdirectories (format nil "~a/proc/" proc-root)))
           (let* ((pid-str (car (last (pathname-directory pid-dir))))
                  (pid (parse-integer pid-str :junk-allowed t)))
             (when pid
               (let ((fd-dir (merge-pathnames "fd/" pid-dir)))
                 (ignore-errors
                   (when (uiop:directory-exists-p fd-dir)
                     (dolist (path (uiop:directory-files fd-dir))
                       (let ((link (ignore-errors (sb-posix:readlink (namestring path)))))
                         (when (and link (string= "socket:[" (subseq link 0 (min 8 (length link)))))
                           (let* ((inode (subseq link 8 (1- (length link))))
                                  (conn (gethash inode socket-map)))
                             (when conn
                               (push conn (gethash pid pid-map)))))))))))))
         pid-map))

     (defun parse-pid-io (pid &optional (proc-root ""))
       (let ((io-file (format nil "~a/proc/~a/io" proc-root pid))
             (rchar 0)
             (wchar 0)
             (read-bytes 0)
             (write-bytes 0))
         (with-open-file (stream io-file :direction :input :if-does-not-exist nil)
           (when stream
             (loop for line = (read-line stream nil)
                   while line
                   do (let ((parts (uiop:split-string line :separator '(#\Space))))
                        (cond
                          ((string= (first parts) "rchar:")
                           (setf rchar (parse-integer (second parts))))
                          ((string= (first parts) "wchar:")
                           (setf wchar (parse-integer (second parts))))
                          ((string= (first parts) "read_bytes:")
                           (setf read-bytes (parse-integer (second parts))))
                          ((string= (first parts) "write_bytes:")
                           (setf write-bytes (parse-integer (second parts)))))))))
         (values rchar wchar read-bytes write-bytes)))

     (defun parse-pid-oom (pid &optional (proc-root ""))
       (let ((oom-file (format nil "~a/proc/~a/oom_score" proc-root pid)))
         (with-open-file (stream oom-file :direction :input :if-does-not-exist nil)
           (if stream
               (or (parse-integer (read-line stream nil) :junk-allowed t) 0)
               0))))

     (defun parse-pid-name (pid &optional (proc-root ""))
       (let ((comm-file (format nil "~a/proc/~a/comm" proc-root pid)))
         (with-open-file (stream comm-file :direction :input :if-does-not-exist nil)
           (if stream
               (string-trim '(#\Newline #\Return #\Space) (read-line stream nil))
               "unknown"))))

     (defun setup-throttling-class (bandwidth-kb)
       (uiop:run-program "mkdir -p /sys/fs/cgroup/tui-throttle" :ignore-error-status t)
       (let ((cmd (format nil "tc qdisc replace dev eth0 root handle 1: htb default 10 && tc class replace dev eth0 parent 1: classid 1:1 htb rate ~akbit" (* bandwidth-kb 8))))
         (uiop:run-program cmd :ignore-error-status t)))

     (defun throttle-pid (pid)
       (let ((path "/sys/fs/cgroup/tui-throttle/cgroup.procs")
             (pid-str (format nil "~a" pid)))
         (with-open-file (stream path :direction :output :if-exists :append :if-does-not-exist nil)
           (when stream
             (write-line pid-str stream)
             t))))

     (comment "Calculate process metrics using IO rates")
     (defun gather-process-metrics (model)
       (let* ((socket-map (parse-sockets (proc-root model)))
              (pid-sockets (map-pids-to-sockets socket-map (proc-root model)))
              (interval-sec (interval-sec model))
              (processes nil))
         (maphash (lambda (pid sockets)
                    (declare (ignore sockets))
                    (multiple-value-bind (rchar wchar read-b write-b) (parse-pid-io pid (proc-root model))
                      (let* ((pid-key (format nil "~a" pid))
                             (last-io (gethash pid-key (last-proc-io model)))
                             (rx-rate 0)
                             (tx-rate 0)
                             (delta-rx 0)
                             (delta-tx 0))
                        (when last-io
                          (let* ((d-rchar (- rchar (first last-io)))
                                 (d-wchar (- wchar (second last-io)))
                                 (d-read (- read-b (third last-io)))
                                 (d-write (- write-b (fourth last-io))))
                            (setf delta-rx (max 0 (- d-rchar d-read)))
                            (setf delta-tx (max 0 (- d-wchar d-write)))
                            (setf rx-rate (floor (/ delta-rx interval-sec)))
                            (setf tx-rate (floor (/ delta-tx interval-sec)))))
                        ;; Save state for next delta
                        (setf (gethash pid-key (last-proc-io model)) (list rchar wchar read-b write-b))
                        ;; Accumulate RX
                        (let ((accum (gethash pid-key (accumulated-rx model) 0)))
                          (incf accum delta-rx)
                          (setf (gethash pid-key (accumulated-rx model)) accum))
                        ;; Update history queue
                        (let ((hist (gethash pid-key (rx-histories model) nil)))
                          (push rx-rate hist)
                          (when (> (length hist) 8)
                            (setf hist (subseq hist 0 8)))
                          (setf (gethash pid-key (rx-histories model)) hist))

                        (push (make-process-info
                               :pid pid
                               :name (parse-pid-name pid (proc-root model))
                               :rx-rate rx-rate
                               :tx-rate tx-rate
                               :read-bytes read-b
                               :write-bytes write-b
                               :oom-score (parse-pid-oom pid (proc-root model))
                               :accumulated-rx (gethash pid-key (accumulated-rx model))
                               :rx-history (gethash pid-key (rx-histories model)))
                              processes))))
                  pid-sockets)
         processes))

     (defun make-sparkline (values &key (min-val 0) (max-val nil))
       (let* ((non-nil (remove nil values))
              (max (or max-val (if non-nil (reduce #'max non-nil) 1)))
              (min (or min-val (if non-nil (reduce #'min non-nil) 0)))
              (range (max 1 (- max min)))
              (chars #(" " " " "▂" "▃" "▄" "▅" "▆" "▇" "█")))
         (map 'string
              (lambda (val)
                (if val
                    (let* ((normalized (floor (* 8 (/ (- val min) range))))
                           (idx (max 0 (min 8 normalized))))
                      (char (aref chars idx) 0))
                    #\Space))
              (reverse values))))

     (comment "Tuition Init Method")
     (defmethod tui:init ((model cockpit-model))
       (lambda () (make-instance 'tick-msg)))

     (comment "Tuition Update Method")
     (defmethod tui:update-message ((model cockpit-model) (msg tui:key-press-msg))
       (let ((key (tui:key-event-code msg)))
         (cond
           ((or (and (characterp key) (or (char= key #\q) (char= key #\Q)))
                (eq key :escape))
            (values model (tui:quit-cmd)))
           ((or (and (characterp key) (or (char= key #\h) (char= key #\H)))
                (eq key :f1))
            (setf (show-help-p model) (not (show-help-p model)))
            (values model nil))
           ((eq key :up)
            (let ((len (length (top-processes model))))
              (when (> len 0)
                (setf (selected-index model)
                      (mod (1- (selected-index model)) len))))
            (values model nil))
           ((eq key :down)
            (let ((len (length (top-processes model))))
              (when (> len 0)
                (setf (selected-index model)
                      (mod (1+ (selected-index model)) len))))
            (values model nil))
           ((and (characterp key) (char= key #\+))
            (setf (interval-sec model) (max 1 (1- (interval-sec model))))
            (setf (status-message model) (format nil "Update interval set to ~d sec" (interval-sec model)))
            (values model nil))
           ((and (characterp key) (char= key #\-))
            (setf (interval-sec model) (min 30 (1+ (interval-sec model))))
            (setf (status-message model) (format nil "Update interval set to ~d sec" (interval-sec model)))
            (values model nil))
           ((or (and (characterp key) (char= key #\t))
                (eq key :enter))
            (let ((procs (top-processes model))
                  (idx (selected-index model)))
              (if (and procs (< idx (length procs)))
                  (let* ((p (nth idx procs))
                         (pid (process-info-pid p))
                         (name (process-info-name p)))
                    (handler-case
                        (progn
                          (throttle-pid pid)
                          (setf (status-message model) (format nil "Throttled PID ~d (~a)" pid name)))
                      (error (c)
                        (setf (status-message model) (format nil "Throttling failed: ~a" c)))))
                  (setf (status-message model) "No process selected")))
            (values model nil))
           (t (values model nil)))))

     (defmethod tui:update-message ((model cockpit-model) (msg tick-msg))
       (handler-case
           (progn
             (multiple-value-bind (steal total) (parse-cpu-steal (proc-root model))
               (when (and steal total)
                 (let* ((d-steal (- steal (last-steal model)))
                        (d-total (- total (last-total model)))
                        (steal-pct (if (> d-total 0) (float (* 100 (/ d-steal d-total))) 0.0)))
                   (setf (last-steal model) steal
                         (last-total model) total)
                   (push steal-pct (cpu-history model))
                   (when (> (length (cpu-history model)) 20)
                     (setf (cpu-history model) (subseq (cpu-history model) 0 20))))))

             (multiple-value-bind (some-io full-io) (parse-io-pressure (proc-root model))
               (setf (io-pressure-some model) (or some-io 0.0)
                     (io-pressure-full model) (or full-io 0.0)))

             (multiple-value-bind (pswpin pswpout) (parse-vmstat (proc-root model))
               (setf (vmstat-pswpin model) pswpin
                     (vmstat-pswpout model) pswpout))

             (multiple-value-bind (rx tx) (parse-net-dev (proc-root model))
               (when (and rx tx)
                 (let* ((d-rx (if (= (last-net-rx model) 0) 0 (- rx (last-net-rx model))))
                        (d-tx (if (= (last-net-tx model) 0) 0 (- tx (last-net-tx model))))
                        (rx-rate-kb (/ d-rx (interval-sec model) 1024))
                        (tx-rate-kb (/ d-tx (interval-sec model) 1024)))
                   (setf (last-net-rx model) rx
                         (last-net-tx model) tx)
                   (push rx-rate-kb (net-rx-history model))
                   (push tx-rate-kb (net-tx-history model))
                   (when (> (length (net-rx-history model)) 15)
                     (setf (net-rx-history model) (subseq (net-rx-history model) 0 15))
                     (setf (net-tx-history model) (subseq (net-tx-history model) 0 15))))))

             (let* ((raw-procs (gather-process-metrics model))
                    (sorted-procs (sort raw-procs #'> :key (lambda (p) (+ (process-info-rx-rate p) (process-info-tx-rate p))))))
               (setf (top-processes model) (subseq sorted-procs 0 (min 5 (length sorted-procs))))))
         (error (c)
           (setf (status-message model) (format nil "Update error: ~a" c))))
       (values model
               (lambda ()
                 (sleep (interval-sec model))
                 (make-instance 'tick-msg))))

     (comment "Tuition View Method")
     (defmethod tui:view ((model cockpit-model))
       (let* ((title-style (tui:make-style :bold t :foreground tui:*fg-bright-magenta*))
              (label-style (tui:make-style :bold t :foreground tui:*fg-bright-cyan*))
              (status-style (tui:make-style :foreground tui:*fg-bright-yellow*))
              (selection-style (tui:make-style :bold t :foreground tui:*fg-bright-green*))
              (out-str (make-string-output-stream)))
         
         (format out-str "~A~%" (tui:render-styled title-style "=== Linux TUI Cockpit (Interactive cl-tuition) ==="))
         (format out-str "Status: ~A | Interval: ~d sec~%" 
                 (tui:render-styled status-style (status-message model))
                 (interval-sec model))
         (format out-str "-------------------------------------------------------------~%")

         ;; CPU Steal
         (let ((cpu-spark (make-sparkline (cpu-history model) :max-val 100.0)))
           (format out-str "~A ~5,2f% [~A]~%" 
                   (tui:render-styled label-style "CPU Steal:")
                   (or (car (cpu-history model)) 0.0)
                   cpu-spark))

         ;; IO Pressure
         (format out-str "~A SOME: ~5,2f%, FULL: ~5,2f%~%"
                 (tui:render-styled label-style "I/O Pressure Stall (PSI):")
                 (io-pressure-some model)
                 (io-pressure-full model))

         ;; Swap Activity
         (format out-str "~A pswpin: ~d, pswpout: ~d~%"
                 (tui:render-styled label-style "Swap Page In/Out:")
                 (vmstat-pswpin model)
                 (vmstat-pswpout model))

         ;; Network Download/Upload rates
         (let ((rx-spark (make-sparkline (net-rx-history model)))
               (tx-spark (make-sparkline (net-tx-history model))))
           (format out-str "~A RX: ~5,2f kB/s [~A]  TX: ~5,2f kB/s [~A]~%"
                   (tui:render-styled label-style "Net Rates:")
                   (or (car (net-rx-history model)) 0.0) rx-spark
                   (or (car (net-tx-history model)) 0.0) tx-spark))
         
         (format out-str "~%~A~%" (tui:render-styled label-style "Top Bandwidth Processes:"))
         (format out-str "   PID      NAME             NET-RX (ACCUMULATED)   RX-HIST    NET-TX     DISK-R/W     OOM~%")
         
         (let ((procs (top-processes model))
               (sel-idx (selected-index model)))
           (loop for p in procs
                 for idx from 0
                 do (let* ((rx-kb (/ (process-info-rx-rate p) 1024))
                           (tx-kb (/ (process-info-tx-rate p) 1024))
                           (accum-mb (/ (process-info-accumulated-rx p) 1024 1024))
                           (disk-r-kb (/ (process-info-read-bytes p) 1024 1024))
                           (disk-w-kb (/ (process-info-write-bytes p) 1024 1024))
                           (name (process-info-name p))
                           (short-name (subseq name 0 (min 15 (length name))))
                           (prefix (if (= idx sel-idx) "-> " "   "))
                           (row-str (format nil "~A~5d  ~15a  ~5,1fK (~5,1fM)      [~A]   ~5,1fK  ~4,1fM/~4,1fM  ~4d"
                                            prefix
                                            (process-info-pid p)
                                            short-name
                                            rx-kb accum-mb
                                            (make-sparkline (process-info-rx-history p))
                                            tx-kb
                                            disk-r-kb disk-w-kb
                                            (process-info-oom-score p))))
                      (format out-str "~A~%" 
                              (if (= idx sel-idx)
                                  (tui:render-styled selection-style row-str)
                                  row-str)))))

         ;; Render Help overlay if toggled
         (if (show-help-p model)
             (progn
               (format out-str "~%=============================================================~%")
               (format out-str "HELP INSTRUCTIONS:~%")
               (format out-str "  [q] or [Esc]      - Quit Cockpit~%")
               (format out-str "  [h] or [F1]       - Toggle Help Overlay~%")
               (format out-str "  [Up] / [Down]     - Select process from Top Bandwidth list~%")
               (format out-str "  [t] or [Enter]    - Throttle selected process (Traffic Control)~%")
               (format out-str "  [+] / [-]         - Increase / Decrease polling update speed~%")
               (format out-str "=============================================================~%"))
             (format out-str "~%[q] Quit | [h] Help | [↑/↓] Select | [t] Throttle | [+/-] Refresh~%"))
         
         (tui:make-view (get-output-stream-string out-str) :alt-screen t)))

     (defun run-cockpit ()
       (tui:run (tui:make-program (make-instance 'cockpit-model))))))

;; Define tests.lisp code
(defparameter *tests-code*
  `(toplevel
     (defpackage :cockpit-tui/tests
       (:use :cl :rove :cockpit-tui))
     
     (in-package :cockpit-tui/tests)
     
     (deftest test-state-transitions
       (testing "Increment and decrement interval-sec using + and -"
         (let ((model (make-instance 'cockpit-model :interval-sec 3)))
           ;; Send + key
           (multiple-value-bind (m cmd)
               (tui:update-message model (make-instance 'tui:key-press-msg :code #\+))
             (declare (ignore cmd))
             (ok (= 2 (cockpit-tui::interval-sec m))))
           ;; Send - key
           (multiple-value-bind (m cmd)
               (tui:update-message model (make-instance 'tui:key-press-msg :code #\-))
             (declare (ignore cmd))
             (ok (= 3 (cockpit-tui::interval-sec m))))))

       (testing "Help overlay toggle"
         (let ((model (make-instance 'cockpit-model :show-help-p nil)))
           (multiple-value-bind (m cmd)
               (tui:update-message model (make-instance 'tui:key-press-msg :code #\h))
             (declare (ignore cmd))
             (ok (cockpit-tui::show-help-p m))
             (multiple-value-bind (m2 cmd2)
                 (tui:update-message m (make-instance 'tui:key-press-msg :code :f1))
               (declare (ignore cmd2))
               (ok (not (cockpit-tui::show-help-p m2))))))))

     (deftest test-rendering
       (testing "Help overlay is present in the rendered view"
         (let ((model (make-instance 'cockpit-model :show-help-p t)))
           (let ((view-str (tui:view-state-content (tui:view model))))
             (ok (search "HELP INSTRUCTIONS:" view-str)))))
       (testing "Selection indicator shows up in rendered view"
         (let ((model (make-instance 'cockpit-model :selected-index 0)))
           (setf (cockpit-tui::top-processes model)
                 (list (cockpit-tui::make-process-info
                        :pid 100
                        :name "test-proc"
                        :rx-rate 1024
                        :tx-rate 512
                        :read-bytes 0
                        :write-bytes 0
                        :oom-score 0
                        :accumulated-rx 1024
                        :rx-history '(1024))))
           (let ((view-str (tui:view-state-content (tui:view model))))
             (ok (search "-> " view-str))
             (ok (search "test-proc" view-str))))))))

;; Define file creation logic
(defun generate-all ()
  (ensure-directories-exist *output-dir*)
  
  ;; 1. Generate Lisp sources
  (let ((p (write-source "package" *package-code* *output-dir*))
        (c (write-source "cockpit" *cockpit-code* *output-dir*))
        (t-file (write-source "tests" *tests-code* *output-dir*)))
    (format t "Generated ~a, ~a, and ~a~%" p c t-file))
  
  ;; 2. Generate cockpit-tui.asd
  (let* ((asd-path (merge-pathnames "cockpit-tui.asd" *output-dir*))
         (asd-str (emit-cl *asd-code*)))
    (with-open-file (stream asd-path :direction :output :if-exists :supersede :if-does-not-exist :create)
      (write-sequence asd-str stream))
    (format t "Generated ~a~%" asd-path))
  
  ;; 3. Generate run-cockpit.sh
  (let* ((sh-path (merge-pathnames "run-cockpit.sh" *output-dir*))
         (sh-content (format nil "#!/bin/bash
# run-cockpit.sh - Startup script for Tuition Interactive TUI Cockpit

if [ \"$EUID\" -ne 0 ]; then
  echo \"Error: Please run this script as root (required for socket inspection and cgroups).\" >&2
  exit 1
fi

SCRIPT_DIR=\"$(cd \"$(dirname \"${BASH_SOURCE[0]}\")\" && pwd)\"

# Find sbcl core
SBCL_CORE=\"\"
for path in \\
    \"/usr/lib64/sbcl/sbcl.core\" \\
    \"/usr/lib/sbcl/sbcl.core\" \\
    \"/usr/local/lib/sbcl/sbcl.core\"; do
  if [ -f \"$path\" ]; then
    SBCL_CORE=\"$path\"
    break
  fi
done

CORE_ARG=\"\"
if [ -n \"$SBCL_CORE\" ]; then
  CORE_ARG=\"--core $SBCL_CORE\"
  export SBCL_HOME=\"$(dirname \"$SBCL_CORE\")\"
fi

if [ -n \"$SUDO_USER\" ]; then
  INVOKING_HOME=\"$(getent passwd \"$SUDO_USER\" | cut -d: -f6)\"
else
  INVOKING_HOME=\"$HOME\"
fi

QL_SETUP=\"\"
for path in \\
    \"$HOME/quicklisp/setup.lisp\" \\
    \"$INVOKING_HOME/quicklisp/setup.lisp\"; do
  if [ -f \"$path\" ]; then
    QL_SETUP=\"$path\"
    break
  fi
done

QL_ARG=\"\"
if [ -n \"$QL_SETUP\" ]; then
  QL_ARG=\"--load $QL_SETUP\"
fi

exec sbcl $CORE_ARG --disable-debugger $QL_ARG \\
     --eval \"(push \\\"${SCRIPT_DIR}/\\\" asdf:*central-registry*)\" \\
     --eval \"(ql:quickload :cockpit-tui :silent t)\" \\
     --eval \"(cockpit-tui:run-cockpit)\"
")))
    (with-open-file (stream sh-path :direction :output :if-exists :supersede :if-does-not-exist :create)
      (write-sequence sh-content stream))
    (sb-ext:run-program "chmod" (list "+x" (namestring sh-path)) :search t)
    (format t "Generated ~a (executable)~%" sh-path))
  
  ;; 4. Generate README.md
  (let* ((readme-path (merge-pathnames "README.md" *output-dir*))
         (readme-content (format nil "# Tuition Interactive TUI Cockpit

This is version 2 of the bandwidth-optimized Linux cockpit, built using the modern `cl-tuition` framework.

## Features

1. **Interactive Process Throttling**:
   * Navigate using **Up / Down** arrows.
   * Press **[t]** or **[Enter]** to throttle the selected process using Traffic Control and Cgroups.
2. **Process Network History & Accumulation**:
   * Tracks and displays process-level network download rate trends using Unicode sparklines.
   * Keeps a session running total of accumulated downloaded bytes per process.
3. **Responsive Polling Speeds**:
   * Press **[+]** to speed up refresh rates (decrement interval seconds).
   * Press **[-]** to slow down refresh rates (increment interval seconds).
4. **Help Overlay**:
   * Press **[h]** or **[F1]** to toggle helper key bindings inline.

## How to Run

Must be run as root:
```bash
sudo ./run-cockpit.sh
```

## Running Tests

To run the Rove test suite:
```bash
sbcl --eval '(push \"$(pwd)/\" asdf:*central-registry*)' \\
     --eval '(asdf:test-system :cockpit-tui/tests)' \\
     --quit
```
")))
    (with-open-file (stream readme-path :direction :output :if-exists :supersede :if-does-not-exist :create)
      (write-sequence readme-content stream))
    (format t "Generated ~a~%" readme-path)))

(generate-all)
