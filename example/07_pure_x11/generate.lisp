;;;; generate.lisp — Orchestrator for Pure X11 Dynamic Code Generator

(in-package :cl-user)

;; Load sub-files in order
(load "01_package.lisp")
(load "02_x11_spec.lisp")
(load "03_widgets_core.lisp")
(load "04_widgets_builtin.lisp")
(load "05_event_loop.lisp")
(load "06_example_template.lisp")
(load "07_tests_template.lisp")
(load "08_orbit_demo_template.lisp")

(in-package :cl-cl-generator/example-x11-gen)

(defun run-generator ()
  (ensure-directories-exist *output-dir*)

  ;; 1. Emit package.lisp
  (write-source "package"
    `(toplevel
       ,@(make-header-comments)
       (defpackage :pure-x11-gen
         (:use :cl :sb-bsd-sockets)
         (:export #:connect
                  #:make-window
                  #:map-window
                  #:destroy-window
                  #:change-window-attributes
                  #:configure-window
                  #:clear-area
                  #:draw-window
                  #:poly-rectangle
                  #:poly-fill-rectangle
                  #:poly-arc
                  #:poly-fill-arc
                  #:create-gc
                  #:next-resource-id
                  #:read-reply-timeout
                  #:query-pointer
                  #:imagetext8
                  #:query-extension
                  #:big-requests-enable
                  #:put-image-big-req
                  #:free-gc
                  #:create-cursor
                  #:open-font
                  #:close-font
                  #:grab-pointer
                  #:ungrab-pointer
                  #:get-keyboard-mapping
                  #:read-reply-wait
                  #:read-reply-packet
                  #:*pending-events*
                  #:run-gui
                  
                  #:parse-expose
                  #:parse-motion-notify
                  #:parse-button-press
                  #:parse-button-release
                  #:parse-key-press
                  #:parse-configure-notify

                  #:draw-line
                  #:*s*
                  #:*root*
                  #:*window*
                  #:*gc-light*
                  #:*gc-face*
                  #:*gc-shadow*
                  #:*gc-dark*
                  #:*gc-text*
                  #:*packet-buffer*
                  #:with-buffered-output
                  #:flush-packets
                  #:resolve-layout
                  #:widget-p
                  #:*big-request-opcode*)))
    *output-dir*)

  ;; 2. Emit pure-x11-gen.asd
  (let* ((asd-path (merge-pathnames "pure-x11-gen.asd" *output-dir*))
         (asd-code
           `(toplevel
              ,@(make-header-comments)
              (asdf:defsystem :pure-x11-gen
                :version "0.1.0"
                :description "X11 client library generated dynamically via cl-cl-generator"
                :depends-on (:sb-bsd-sockets)
                :serial t
                :components ((:file "package")
                             (:file "x11-core")
                             (:file "widgets-core")
                             (:file "widgets-builtin")
                             (:file "event-loop")
                             (:file "example")
                             (:file "orbit-demo")
                             (:file "tests"))))))
    (ensure-directories-exist asd-path)
    (with-open-file (stream asd-path
                            :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create)
      (write-sequence (emit-cl asd-code) stream)))

  ;; 3. Emit x11-core.lisp
  (let ((x11-core-code
          `(toplevel
             ,@(make-header-comments)
             (in-package :pure-x11-gen)

             (defparameter *s* nil "Socket for communication with X server.")
             (defparameter *resp* nil "Reply of the X server to a request")
             (defparameter *root* nil "Root ID as extracted from the initial reply of the X server.")
             (defparameter *window* nil)
             (defparameter *gc-light* nil)
             (defparameter *gc-face* nil)
             (defparameter *gc-shadow* nil)
             (defparameter *gc-dark* nil)
             (defparameter *gc-text* nil)
             (defparameter *big-request-opcode* nil)

             (defun pad (n)
               "Difference to next number that is divisible by 4."
               (if (= 0 (mod n 4))
                   0
                   (- (* 4 (1+ (floor n 4))) n)))
             (comment "Macros for packet writing and reply reading")
             (raw "
(defvar *packet-buffer* nil)
(defvar *buffering-p* nil)

(defun flush-packets ()
  \"Write all buffered packets to the socket in one batch.\"
  (when (and *packet-buffer* *s*)
    (dolist (buf (nreverse *packet-buffer*))
      (write-sequence buf *s*))
    (force-output *s*))
  (setf *packet-buffer* nil))

(defmacro with-buffered-output (&body body)
  \"Execute body with request buffering. Flushes on exit.\"
  `(let ((*packet-buffer* (list))
         (*buffering-p* t))
     (unwind-protect (progn ,@body)
       (flush-packets))))

(defmacro with-packet (&body body)
  \"Write values into a list of bytes and send over the socket *s* or buffer it.\"
  `(let* ((l ()))
     (labels ((string8 (a)
                (declare (type string a))
                (loop for i below (length a) do
                  (push (char-code (aref a i)) l)))
              (card8 (a)
                (declare ((unsigned-byte 8) a))
                (push a l))
              (card16 (a)
                (declare ((unsigned-byte 16) a))
                (dotimes (i 2)
                  (push (ldb (byte 8 (* 8 i)) a) l)))
              (card32 (a)
                (declare ((unsigned-byte 32) a))
                (dotimes (i 4)
                  (push (ldb (byte 8 (* 8 i)) a) l))))
       ,@body
       (let ((buf (make-array (length l)
                              :element-type '(unsigned-byte 8)
                              :initial-contents (nreverse l))))
         (if *buffering-p*
             (push buf *packet-buffer*)
             (progn
               (write-sequence buf *s*)
               (force-output *s*)))))))
")

             (raw "
(defmacro with-reply (buf &body body)
  \"Parse a socket reply buffer.\"
  (let ((r (gensym)))
    `(let ((,r ,buf)
           (current 0))
       (labels ((card8 ()
                  (prog1
                      (aref ,r current)
                    (incf current)))
                (card16 ()
                  (prog1
                      (+ (aref ,r current)
                         (* 256 (aref ,r (1+ current))))
                    (incf current 2)))
                (int16 ()
                  (let ((v (card16)))
                    (if (< v (ash 1 15))
                        v
                        (- v (ash 1 16)))))
                (card32 ()
                  (prog1
                      (+ (aref ,r current)
                         (* 256 (+ (aref ,r (1+ current))
                                   (* 256 (+ (aref ,r (+ 2 current))
                                             (* 256 (aref ,r (+ 3 current))))))))
                    (incf current 4)))
                (string8 (n)
                  (prog1
                      (map 'string #'code-char (subseq ,r current (+ current n)))
                    (incf current n)))
                (inc-current (n)
                  (incf current n)))
         ,@body))))
")

             (defun read-exactly (stream buf &optional (start 0) (end (length buf)))
               "Read exactly from start to end bytes from stream into buf, blocking if necessary."
               (let ((pos start))
                 (loop while (< pos end) do
                   (let ((n (read-sequence buf stream :start pos :end end)))
                     (if (= n pos)
                         (error "EOF on socket stream")
                         (setf pos n))))
                 buf))

             (defun read-reply-wait ()
                "Read standard 32-byte reply header and optional variable-length body from *s*."
                (let* ((buf (make-array 32 :element-type '(unsigned-byte 8))))
                  (read-exactly *s* buf)
                  (format t "read-reply-wait: read packet code ~a~%" (aref buf 0))
                  (force-output)
                  (with-reply buf
                    (let ((reply (card8))
                          (unused (card8))
                          (sequence-number (card16))
                          (reply-length (card32)))
                      (declare (ignorable reply unused))
                      (if (or (= reply 0)
                              (< 1 reply)
                              (and (= reply 1) (= 0 reply-length)))
                          (values buf sequence-number)
                          (let ((m (make-array (* 4 reply-length) :element-type '(unsigned-byte 8))))
                            (read-exactly *s* m)
                            (values (concatenate '(vector (unsigned-byte 8)) buf m) sequence-number)))))))

              (defun read-reply-timeout (timeout-sec)
                "Wait up to TIMEOUT-SEC seconds for input on *s*. Returns the packet buffer if read, or NIL on timeout."
                (when *s*
                  (let ((fd (sb-sys:fd-stream-fd *s*)))
                    (if (sb-sys:wait-until-fd-usable fd :input (coerce timeout-sec 'double-float))
                        (read-reply-wait)
                        nil))))

              (defvar *resource-id-counter* 10)
              (defun next-resource-id ()
                "Allocate a new X11 resource ID dynamically."
                (logior *resource-id-base* (logand *resource-id-mask* (incf *resource-id-counter*))))

             (defvar *pending-events* nil)

             (defun read-reply-packet ()
               "Read packets from *s* until we receive a reply (code 1) or error (code 0). Queue events in *pending-events*."
               (loop
                 (multiple-value-bind (buf seq) (read-reply-wait)
                   (declare (ignore seq))
                   (let ((code (logand (aref buf 0) #x7f)))
                     (cond
                       ((or (= code 0) (= code 1))
                        (return buf))
                       (t
                        (setf *pending-events* (nconc *pending-events* (list buf)))))))))

             (defun read-connection-response ()
               "Read the initial connection response from X server."
               (let ((buf (make-array 8 :element-type '(unsigned-byte 8))))
                 (read-exactly *s* buf)
                 (with-reply buf
                   (let ((success-state (card8))
                         (length-of-reason (card8))
                         (protocol-major-version (card16))
                         (protocol-minor-version (card16))
                         (reply-length (card16)))
                     (let ((m (make-array (+ 8 (* 4 reply-length)) :element-type '(unsigned-byte 8))))
                       (dotimes (i 8)
                         (setf (aref m i) (aref buf i)))
                       (read-exactly *s* m 8 (+ 8 (* 4 reply-length)))
                       (ecase success-state
                         (0 (error "Connection failed"))
                         (2 (error "Authentication required"))
                         (1 m)))))))

             (defun parse-initial-reply (r)
               "Extract connection constants and root ID from initial response."
               (with-reply r
                 (let* ((success (card8))
                        (unused (card8))
                        (protocol-major (card16))
                        (protocol-minor (card16))
                        (length (card16))
                        (release (card32))
                        (resource-id-base (card32))
                        (resource-id-mask (card32))
                        (motion-buffer-size (card32))
                        (length-of-vendor (card16))
                        (maximum-request-length (card16))
                        (number-of-screens (card8))
                        (number-of-formats (card8))
                        (image-byte-order (card8))
                        (bitmap-format-bit-order (card8))
                        (bitmap-format-scanline-unit (card8))
                        (bitmap-format-scanline-pad (card8))
                        (min-keycode (card8))
                        (max-keycode (card8))
                        (unused2 (card32))
                        (vendor (string8 length-of-vendor))
                        (unused3 (inc-current (pad length-of-vendor))))
                   (unless (= 1 success)
                     (error "Connection didn't succeed."))
                   (defparameter *resource-id-base* resource-id-base)
                   (defparameter *resource-id-mask* resource-id-mask)
                   (dotimes (i number-of-formats)
                     (let ((depth (card8))
                           (bpp (card8))
                           (scanline-pad (card8))
                           (unused (inc-current 5)))
                       (declare (ignorable depth bpp scanline-pad unused))))
                   (dotimes (i number-of-screens)
                     (let ((root (card32))
                           (default-colormap (card32))
                           (white-pixel (card32))
                           (black-pixel (card32))
                           (current-input-mask (card32))
                           (width (card16))
                           (height (card16))
                           (width-in-mm (card16))
                           (height-in-mm (card16))
                           (min-installed-maps (card16))
                           (max-installed-maps (card16))
                           (root-visual (card32))
                           (backing-stores (card8))
                           (save-unders (card8))
                           (root-depth (card8))
                           (number-of-allowed-depths (card8)))
                       (declare (ignorable default-colormap white-pixel black-pixel current-input-mask
                                           width height width-in-mm height-in-mm min-installed-maps
                                           max-installed-maps root-visual backing-stores save-unders
                                           root-depth number-of-allowed-depths))
                       (defparameter *root* root)
                       (dotimes (i number-of-allowed-depths)
                         (let ((depth (card8))
                               (unused (card8))
                               (number-of-visuals (card16))
                               (unused2 (card32)))
                           (declare (ignorable depth unused number-of-visuals unused2))
                           (dotimes (j number-of-visuals)
                             (let ((visual-id (card32))
                                   (class (card8))
                                   (bits-per-rgb (card8))
                                   (colormap-entries (card16))
                                   (red-mask (card32))
                                   (green-mask (card32))
                                   (blue-mask (card32))
                                   (unused (card32)))
                               (declare (ignorable visual-id class bits-per-rgb colormap-entries
                                                   red-mask green-mask blue-mask unused)))))))))))

             (defun connect (&key (ip #(127 0 0 1)) (filename nil) (port nil) (display nil))
               "Connect to the X server. If display is not specified, it is read from the environment."
               (let* ((display-str (or display (sb-ext:posix-getenv "DISPLAY") ":0"))
                      (colon-pos (position #\: display-str)))
                 (cond
                   (filename
                    (defparameter *s*
                      (socket-make-stream (let ((s (make-instance 'local-socket :type :stream)))
                                            (socket-connect s filename)
                                            s)
                                          :element-type '(unsigned-byte 8)
                                          :input t
                                          :output t
                                          :buffering :none)))
                   ((or (null colon-pos) (= 0 colon-pos))
                    (let* ((disp-num-str (if colon-pos
                                             (subseq display-str (1+ colon-pos))
                                             display-str))
                           (dot-pos (position #\. disp-num-str))
                           (disp-num (if dot-pos (subseq disp-num-str 0 dot-pos) disp-num-str))
                           (path (format nil "/tmp/.X11-unix/X~a" disp-num)))
                      (defparameter *s*
                        (socket-make-stream (let ((s (make-instance 'local-socket :type :stream)))
                                              (socket-connect s path)
                                              s)
                                            :element-type '(unsigned-byte 8)
                                            :input t
                                            :output t
                                            :buffering :none))))
                   (t
                    (let* ((host (subseq display-str 0 colon-pos))
                           (disp-num-str (subseq display-str (1+ colon-pos)))
                           (dot-pos (position #\. disp-num-str))
                           (disp-num-str-clean (if dot-pos (subseq disp-num-str 0 dot-pos) disp-num-str))
                           (disp-num (parse-integer disp-num-str-clean :junk-allowed t))
                           (resolved-port (or port (+ 6000 disp-num)))
                           (resolved-ip (if (or (string= host "") (string= host "localhost"))
                                            ip
                                            ip)))
                      (defparameter *s*
                        (socket-make-stream (let ((s (make-instance 'inet-socket :type :stream :protocol :tcp)))
                                              (socket-connect s resolved-ip resolved-port)
                                              s)
                                            :element-type '(unsigned-byte 8)
                                            :input t
                                            :output t
                                            :buffering :none))))))
               (with-packet
                 (card8 #x6c)            ; little endian
                 (card8 0)
                 (card16 11)
                 (card16 0)
                 (card16 0)
                 (card16 0)
                 (card16 0))
               (setf *resp* (read-connection-response))
               (parse-initial-reply *resp*)
               (big-requests-enable))

             (comment "Flag and Option Lookups")
             (defparameter *set-of-value-mask* ',*set-of-value-mask*)
             (defparameter *set-of-event* ',*set-of-event*)
             (defparameter *set-of-key-button* ',*set-of-key-button*)

             ,(generate-lookup-function 'value '*set-of-value-mask*)
             ,(generate-lookup-function 'event    '*set-of-event*)
             ,(generate-lookup-function 'key-button '*set-of-key-button*)

             (comment "Dynamically Generated Request APIs")
             ,@(loop for req in *x11-requests*
                     collect (emit-request-function req))

             (comment "Dynamically Generated Event Parsers")
             ,@(loop for ev in *x11-events*
                      collect (emit-event-parser ev))
              )))
  (write-source "x11-core" x11-core-code *output-dir*))

  ;; 4. Emit widget & event-loop files
  (write-source "widgets-core" *widgets-core-template-code* *output-dir*)
  (write-source "widgets-builtin" *widgets-builtin-template-code* *output-dir*)
  (write-source "event-loop" *event-loop-template-code* *output-dir*)

  ;; 5. Emit example.lisp
  (write-source "example" *example-template-code* *output-dir*)

  ;; 5b. Emit orbit-demo.lisp
  (write-source "orbit-demo" *orbit-demo-template-code* *output-dir*)

  ;; 6. Emit tests.lisp
  (write-source "tests" *tests-template-code* *output-dir*)
  (format t "Successfully generated X11 example client codebase in ~a~%" *output-dir*))

;; Run the generator when loaded
(run-generator)
