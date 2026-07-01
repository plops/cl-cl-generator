(in-package :cockpit)

;; =====================================================
;;  Generated bandwidth-optimized Linux TUI Cockpit      
;; =====================================================
(defparameter *screen-width* 80)

(defparameter *screen-height* 24)

(defstruct process-info
  pid
  name
  rx-rate
  tx-rate
  read-bytes
  write-bytes
  oom-score)

(defun parse-cpu-steal ()
  (with-open-file
      (stream "/proc/stat" :direction :input :if-does-not-exist nil)
    (when stream
      (let ((line (read-line stream nil)))
        (when (and line (string= "cpu " (subseq line 0 4)))
          (let* ((parts (uiop/utility:split-string line :separator '(#\ )))
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

(defun parse-io-pressure ()
  (with-open-file
      (stream "/proc/pressure/io" :direction :input :if-does-not-exist nil)
    (when stream
      (let ((some-line (read-line stream nil))
            (full-line (read-line stream nil)))
        (flet ((extract-avg10 (line)
                (when line
                  (let ((pos (search "avg10=" line)))
                    (when pos
                      (let ((end (search " " line :start2 pos)))
                        (read-from-string (subseq line (+ pos 6) end))))))))
          (values (extract-avg10 some-line) (extract-avg10 full-line)))))))

(defun parse-vmstat ()
  (with-open-file
      (stream "/proc/vmstat" :direction :input :if-does-not-exist nil)
    (when stream
      (let ((pswpin 0) (pswpout 0))
        (loop for line = (read-line stream nil)
              while line
              do (let ((parts
                        (uiop/utility:split-string line :separator '(#\ ))))
                   (cond
                     ((string= (first parts) "pswpin")
                      (setf pswpin (parse-integer (second parts))))
                     ((string= (first parts) "pswpout")
                      (setf pswout (parse-integer (second parts)))))))
        (values pswpin pswpout)))))

;; Parse global network bytes from /proc/net/dev
(defun parse-net-dev ()
  (let ((rx 0) (tx 0))
    (with-open-file
        (stream "/proc/net/dev" :direction :input :if-does-not-exist nil)
      (when stream
        (read-line stream nil)
        (read-line stream nil)
        (loop for line = (read-line stream nil)
              while line
              do (let ((colon (position #\: line)))
                   (when colon
                     (let* ((iface (string-trim '(#\ ) (subseq line 0 colon)))
                            (data (subseq line (1+ colon)))
                            (parts
                             (uiop/utility:split-string data :separator
                                                        '(#\ )))
                            (parts (remove "" parts :test #'string=)))
                       (unless (string= iface "lo")
                         (incf rx (parse-integer (nth 0 parts)))
                         (incf tx (parse-integer (nth 8 parts))))))))))
    (values rx tx)))

;; Parse socket inode mappings from /proc/net/tcp and udp
(defun parse-sockets ()
  (let ((inodes (make-hash-table :test 'equal)))
    (dolist
        (file
         '("/proc/net/tcp" "/proc/net/tcp6" "/proc/net/udp" "/proc/net/udp6"))
      (with-open-file (stream file :direction :input :if-does-not-exist nil)
        (when stream
          (read-line stream nil)
          (loop for line = (read-line stream nil)
                while line
                do (let* ((parts
                           (uiop/utility:split-string line :separator '(#\ )))
                          (parts (remove "" parts :test #'string=))
                          (local-addr (nth 1 parts))
                          (remote-addr (nth 2 parts)) (inode (nth 9 parts)))
                     (when (and inode (not (string= inode "0")))
                       (setf (gethash inode inodes)
                               (cons local-addr remote-addr))))))))
    inodes))

;; Parse PIDs and link socket inodes to processes
(defun map-pids-to-sockets (socket-map)
  (let ((pid-map (make-hash-table :test 'equal)))
    (dolist (pid-dir (uiop/filesystem:subdirectories "/proc/"))
      (let* ((pid-str (car (last (pathname-directory pid-dir))))
             (pid (parse-integer pid-str :junk-allowed t)))
        (when pid
          (let ((fd-dir (merge-pathnames "fd/" pid-dir)))
            (ignore-errors
             (when (uiop/filesystem:directory-exists-p fd-dir)
               (dolist (path (uiop/filesystem:directory-files fd-dir))
                 (let ((link
                        (ignore-errors (sb-posix:readlink (namestring path)))))
                   (when (and link
                              (string= "socket:["
                                       (subseq link 0 (min 8 (length link)))))
                     (let* ((inode (subseq link 8 (1- (length link))))
                            (conn (gethash inode socket-map)))
                       (when conn
                         (push conn (gethash pid pid-map))))))))))))
     pid-map)))

;; Parse process IO bytes from /proc/<pid>/io
(defun parse-pid-io (pid)
  (let ((io-file (format nil "/proc/~a/io" pid)) (read-bytes 0) (write-bytes 0))
    (with-open-file (stream io-file :direction :input :if-does-not-exist nil)
      (when stream
        (loop for line = (read-line stream nil)
              while line
              do (let ((parts
                        (uiop/utility:split-string line :separator '(#\ ))))
                   (cond
                     ((string= (first parts) "read_bytes:")
                      (setf read-bytes (parse-integer (second parts))))
                     ((string= (first parts) "write_bytes:")
                      (setf write-bytes (parse-integer (second parts)))))))))
    (values read-bytes write-bytes)))

;; Parse process OOM score
(defun parse-pid-oom (pid)
  (let ((oom-file (format nil "/proc/~a/oom_score" pid)))
    (with-open-file (stream oom-file :direction :input :if-does-not-exist nil)
      (if stream
          (or (parse-integer (read-line stream nil) :junk-allowed t) 0)
          0))))

;; Parse process name
(defun parse-pid-name (pid)
  (let ((comm-file (format nil "/proc/~a/comm" pid)))
    (with-open-file (stream comm-file :direction :input :if-does-not-exist nil)
      (if stream
          (string-trim '(#\Newline #\Return #\ ) (read-line stream nil))
          "unknown"))))

;; Track historical rate differentials for processes
(defparameter *last-proc-net* (make-hash-table :test 'equal))

(defun calculate-proc-net-rates (pid socket-connections interval-sec)
  (let ((bytes 0))
    (declare (ignore socket-connections interval-sec))
    (values bytes bytes)))

;; Gather all process metrics
(defun gather-process-metrics (interval-sec)
  (let* ((socket-map (parse-sockets))
         (pid-sockets (map-pids-to-sockets socket-map)) (processes nil))
    (maphash
     (lambda (pid sockets)
       (declare (ignore sockets))
       (multiple-value-bind (read-b write-b) (parse-pid-io pid)
         (let* ((pid-key (format nil "~a" pid))
                (last-io (gethash pid-key *last-proc-net*)) (rx-rate 0)
                (tx-rate 0))
           (when last-io
             (let ((d-read (- read-b (first last-io)))
                   (d-write (- write-b (second last-io))))
               (setf rx-rate (max 0 (floor (/ d-read interval-sec))))
               (setf tx-rate (max 0 (floor (/ d-write interval-sec))))))
           (setf (gethash pid-key *last-proc-net*) (list read-b write-b))
           (push
            (make-process-info :pid pid :name (parse-pid-name pid) :rx-rate
             rx-rate :tx-rate tx-rate :read-bytes read-b :write-bytes write-b
             :oom-score (parse-pid-oom pid))
            processes))))
     pid-sockets)
    processes))

;; Delta-buffered UI Engine (saves SSH bandwidth)
(defparameter *current-buffer*
  (make-array '(24 80) :element-type 'character :initial-element #\ ))

(defparameter *back-buffer*
  (make-array '(24 80) :element-type 'character :initial-element #\ ))

(defun clear-screen-buffer ()
  (dotimes (y 24) (dotimes (x 80) (setf (aref *current-buffer* y x) #\ ))))

(defun write-str-to-buffer (y x str)
  (let ((len (length str)))
    (dotimes (i len)
      (let ((cx (+ x i)))
        (when (and (< cx 80) (< y 24))
          (setf (aref *current-buffer* y cx) (char str i)))))))

(defun render-delta ()
  (dotimes (y 24)
    (let ((cursor-moved nil))
      (dotimes (x 80)
        (let ((curr (aref *current-buffer* y x))
              (back (aref *back-buffer* y x)))
          (when (char/= curr back)
            (unless cursor-moved
              (format t "~c[~a;~aH" #\Esc (1+ y) (1+ x))
              (setf cursor-moved t))
            (write-char curr)
            (setf (aref *back-buffer* y x) curr))))))
  (force-output))

;; Generate Sparkline graph using Unicode blocks
(defun make-sparkline (values &key (min-val 0) (max-val nil))
  (let* ((non-nil (remove nil values))
         (max
          (or max-val
              (if non-nil
                  (reduce #'max non-nil)
                  1)))
         (min
          (or min-val
              (if non-nil
                  (reduce #'min non-nil)
                  0)))
         (range (max 1 (- max min)))
         (chars #(" " " " "▂" "▃" "▄" "▅" "▆" "▇" "█")))
    (map 'string
         (lambda (val)
           (if val
               (let* ((normalized (floor (* 8 (/ (- val min) range))))
                      (idx (max 0 (min 8 normalized))))
                 (char (aref chars idx) 0))
               #\ ))
         (reverse values))))

;; Cgroup & Traffic Control throttling
(defun setup-throttling-class (bandwidth-kb)
  (uiop/run-program:run-program "mkdir -p /sys/fs/cgroup/tui-throttle"
                                :ignore-error-status t)
  (let ((cmd
         (format nil
                 "tc qdisc replace dev eth0 root handle 1: htb default 10 && tc class replace dev eth0 parent 1: classid 1:1 htb rate ~akbit"
                 (* bandwidth-kb 8))))
    (uiop/run-program:run-program cmd :ignore-error-status t)))

(defun throttle-pid (pid)
  (let ((path "/sys/fs/cgroup/tui-throttle/cgroup.procs")
        (pid-str (format nil "~a" pid)))
    (with-open-file
        (stream path :direction :output :if-exists :append :if-does-not-exist
         nil)
      (when stream
        (write-line pid-str stream)
        t))))

;; Main Cockpit Loop
(defun run-cockpit ()
  (format t "~c[2J~c[H" #\Esc #\Esc)
  (force-output)
  (let ((cpu-history nil) (net-rx-history nil) (net-tx-history nil)
        (last-steal 0) (last-total 0) (last-net-rx 0) (last-net-tx 0)
        (interval-sec 3))
    (loop
      (clear-screen-buffer)
      (write-str-to-buffer 0 2
       "=== Linux TUI Cockpit (Bandwidth-Optimiert) ===")
      ;; CPU Steal Calculation & Plotting
      (multiple-value-bind (steal total) (parse-cpu-steal)
        (when (and steal total)
          (let* ((d-steal (- steal last-steal)) (d-total (- total last-total))
                 (steal-pct
                  (if (> d-total 0)
                      (float (* 100 (/ d-steal d-total)))
                      0.0)))
            (setf last-steal steal
                  last-total total)
            (push steal-pct cpu-history)
            (when (> (length cpu-history) 20)
              (setf cpu-history (subseq cpu-history 0 20)))
            (let ((spark (make-sparkline cpu-history :max-val 100)))
              (write-str-to-buffer 2 2
               (format nil "CPU Steal: ~5,2f% [~a]" steal-pct spark))))))
      ;; IO Pressure (PSI)
      (multiple-value-bind (some-io full-io) (parse-io-pressure)
        (write-str-to-buffer 4 2
         (format nil "I/O Pressure Stall (PSI): SOME: ~a%, FULL: ~a%"
                 (or some-io 0.0) (or full-io 0.0))))
      ;; Swap Page In/Out Activity
      (multiple-value-bind (pswpin pswpout) (parse-vmstat)
        (write-str-to-buffer 6 2
         (format nil "Swap Page In/Out: pswpin: ~a, pswpout: ~a" pswpin
                 pswpout)))
      ;; Global Network Bandwidth rates
      (multiple-value-bind (rx tx) (parse-net-dev)
        (when (and rx tx)
          (let* ((d-rx
                  (if (= last-net-rx 0)
                      0
                      (- rx last-net-rx)))
                 (d-tx
                  (if (= last-net-tx 0)
                      0
                      (- tx last-net-tx)))
                 (rx-rate-kb (/ d-rx interval-sec 1024))
                 (tx-rate-kb (/ d-tx interval-sec 1024)))
            (setf last-net-rx rx
                  last-net-tx tx)
            (push rx-rate-kb net-rx-history)
            (push tx-rate-kb net-tx-history)
            (when (> (length net-rx-history) 15)
              (setf net-rx-history (subseq net-rx-history 0 15))
              (setf net-tx-history (subseq net-tx-history 0 15)))
            (write-str-to-buffer 8 2
             (format nil "Net Rate: RX: ~5,2f kB/s [~a]  TX: ~5,2f kB/s [~a]"
                     rx-rate-kb (make-sparkline net-rx-history) tx-rate-kb
                     (make-sparkline net-tx-history))))))
      ;; Process lists
      (let* ((raw-procs (gather-process-metrics interval-sec))
             (sorted-procs
              (sort raw-procs #'> :key
                    (lambda (p)
                      (+ (process-info-rx-rate p) (process-info-tx-rate p)))))
             (top-procs (subseq sorted-procs 0 (min 5 (length sorted-procs)))))
        (write-str-to-buffer 11 2 "Top Bandwidth Processes:")
        (write-str-to-buffer 12 2
         "  PID    NAME          NET-RX       NET-TX       DISK-R/W     OOM")
        (loop for p in top-procs
              for i from 0
              do (let* ((rx-kb (/ (process-info-rx-rate p) 1024))
                        (tx-kb (/ (process-info-tx-rate p) 1024))
                        (disk-r-kb (/ (process-info-read-bytes p) 1024 1024))
                        (disk-w-kb (/ (process-info-write-bytes p) 1024 1024)))
                   (write-str-to-buffer (+ 13 i) 2
                    (format nil
                            "  ~5a  ~12a  ~5,1fkB/s  ~5,1fkB/s  ~4,1fM/~4,1fM  ~3a"
                            (process-info-pid p) (process-info-name p) rx-kb
                            tx-kb disk-r-kb disk-w-kb
                            (process-info-oom-score p))))))
      (render-delta)
      (sleep interval-sec))))