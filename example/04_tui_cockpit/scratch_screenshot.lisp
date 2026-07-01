(push "/workspace/src/cl-cl-generator/example/04_tui_cockpit/" asdf:*central-registry*)
(ql:quickload :cockpit :silent t)

(let ((cpu-history nil)
      (net-rx-history nil)
      (net-tx-history nil)
      (last-steal 0)
      (last-total 0)
      (last-net-rx 0)
      (last-net-tx 0)
      (interval-sec 1))
  ;; Baseline
  (multiple-value-bind (steal total) (cockpit::parse-cpu-steal)
    (setf last-steal steal last-total total))
  (multiple-value-bind (rx tx) (cockpit::parse-net-dev)
    (setf last-net-rx rx last-net-tx tx))
  (cockpit::gather-process-metrics interval-sec)
  
  (sleep interval-sec)
  
  ;; Actual sample
  (cockpit::clear-screen-buffer)
  (cockpit::write-str-to-buffer 0 2 "=== Linux TUI Cockpit (Bandwidth-Optimiert) ===")
  
  (multiple-value-bind (steal total) (cockpit::parse-cpu-steal)
    (when (and steal total)
      (let* ((d-steal (- steal last-steal))
             (d-total (- total last-total))
             (steal-pct (if (> d-total 0) (float (* 100 (/ d-steal d-total))) 0.0)))
        (push steal-pct cpu-history)
        (cockpit::write-str-to-buffer 2 2 (format nil "CPU Steal: ~5,2f% [~a]" steal-pct (cockpit::make-sparkline cpu-history :max-val 100))))))
        
  (multiple-value-bind (some-io full-io) (cockpit::parse-io-pressure)
    (cockpit::write-str-to-buffer 4 2 (format nil "I/O Pressure Stall (PSI): SOME: ~a%, FULL: ~a%" (or some-io 0.0) (or full-io 0.0))))
    
  (multiple-value-bind (pswpin pswpout) (cockpit::parse-vmstat)
    (cockpit::write-str-to-buffer 6 2 (format nil "Swap Page In/Out: pswpin: ~a, pswpout: ~a" pswpin pswpout)))
    
  (multiple-value-bind (rx tx) (cockpit::parse-net-dev)
    (when (and rx tx)
      (let* ((d-rx (- rx last-net-rx))
             (d-tx (- tx last-net-tx))
             (rx-rate-kb (/ d-rx interval-sec 1024))
             (tx-rate-kb (/ d-tx interval-sec 1024)))
        (push rx-rate-kb net-rx-history)
        (push tx-rate-kb net-tx-history)
        (cockpit::write-str-to-buffer 8 2
          (format nil "Net Rate: RX: ~5,2f kB/s [~a]  TX: ~5,2f kB/s [~a]"
                  rx-rate-kb (cockpit::make-sparkline net-rx-history)
                  tx-rate-kb (cockpit::make-sparkline net-tx-history))))))
                  
  (let* ((raw-procs (cockpit::gather-process-metrics interval-sec))
         (sorted-procs (sort raw-procs #'> :key (lambda (p) (+ (cockpit::process-info-rx-rate p) (cockpit::process-info-tx-rate p)))))
         (top-procs (subseq sorted-procs 0 (min 5 (length sorted-procs)))))
    (cockpit::write-str-to-buffer 11 2 "Top Bandwidth Processes:")
    (cockpit::write-str-to-buffer 12 2 "   PID      NAME             NET-RX    NET-TX    DISK-R/W     OOM")
    (loop for p in top-procs
          for i from 0
          do (let* ((rx-kb (/ (cockpit::process-info-rx-rate p) 1024))
                    (tx-kb (/ (cockpit::process-info-tx-rate p) 1024))
                    (disk-r-kb (/ (cockpit::process-info-read-bytes p) 1024 1024))
                    (disk-w-kb (/ (cockpit::process-info-write-bytes p) 1024 1024))
                    (name (cockpit::process-info-name p))
                    (short-name (subseq name 0 (min 15 (length name)))))
               (cockpit::write-str-to-buffer (+ 13 i) 2
                 (format nil " ~7d  ~15a  ~8a  ~8a  ~11a  ~4d"
                         (cockpit::process-info-pid p)
                         short-name
                         (format nil "~5,1f K" rx-kb)
                         (format nil "~5,1f K" tx-kb)
                         (format nil "~4,1fM/~4,1fM" disk-r-kb disk-w-kb)
                         (cockpit::process-info-oom-score p))))))
                         
  ;; Output the terminal buffer lines
  (dotimes (y 19)
    (let ((line-str (make-array 80 :element-type 'character)))
      (dotimes (x 80)
        (setf (aref line-str x) (aref cockpit::*current-buffer* y x)))
      (format t "~a~%" (string-right-trim '(#\Space) line-str)))))
