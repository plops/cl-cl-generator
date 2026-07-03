;;;; gen.lisp — Pure X11 Client Code Generator
;;;; Generates a socket-based Lisp-only interface to X11 using cl-cl-generator.
;;;;
;;;; Usage: sbcl --load gen.lisp

(eval-when (:compile-toplevel :execute :load-toplevel)
  (let ((current-dir (make-pathname :directory (pathname-directory *load-pathname*))))
    ;; Push the directory of the cl-cl-generator project onto the central registry
    (push (merge-pathnames "../../" current-dir) asdf:*central-registry*))
  (ql:quickload '(:cl-cl-generator)))

(defpackage :cl-cl-generator/example-x11-gen
  (:use :cl :cl-cl-generator))
(in-package :cl-cl-generator/example-x11-gen)

(defparameter *output-dir*
  (merge-pathnames "source/"
                   (make-pathname :directory (pathname-directory *load-pathname*))))

;;; ============================================================
;;; Section 1: Helper Specifications and Association Lists
;;; ============================================================

(defparameter *set-of-value-mask*
  '((background-pixmap     #x00000001)
    (background-pixel      #x00000002)
    (border-pixmap         #x00000004)
    (border-pixel          #x00000008)
    (bit-gravity           #x00000010)
    (win-gravity           #x00000020)
    (backing-store         #x00000040)
    (backing-planes        #x00000080)
    (backing-pixel         #x00000100)
    (override-redirect     #x00000200)
    (save-under            #x00000400)
    (event-mask            #x00000800)
    (do-not-propagate-mask #x00001000)
    (colormap              #x00002000)
    (cursor                #x00004000)))

(defparameter *set-of-event*
  '((KeyPress              #x00000001)
    (KeyRelease            #x00000002)
    (ButtonPress           #x00000004)
    (ButtonRelease         #x00000008)
    (EnterWindow           #x00000010)
    (LeaveWindow           #x00000020)
    (PointerMotion         #x00000040)
    (PointerMotionHint     #x00000080)
    (Button1Motion         #x00000100)
    (Button2Motion         #x00000200)
    (Button3Motion         #x00000400)
    (Button4Motion         #x00000800)
    (Button5Motion         #x00001000)
    (ButtonMotion          #x00002000)
    (KeymapState           #x00004000)
    (Exposure              #x00008000)
    (VisibilityChange      #x00010000)
    (StructureNotify       #x00020000)
    (ResizeRedirect        #x00040000)
    (SubstructureNotify    #x00080000)
    (SubstructureRedirect  #x00100000)
    (FocusChange           #x00200000)
    (PropertyChange        #x00400000)
    (ColormapChange        #x00800000)
    (OwnerGrabButton       #x01000000)))

(defparameter *set-of-key-button*
  '((Shift                 #x0001)
    (Lock                  #x0002)
    (Control               #x0004)
    (Mod1                  #x0008)
    (Mod2                  #x0010)
    (Mod3                  #x0020)
    (Mod4                  #x0040)
    (Mod5                  #x0080)
    (Button1               #x0100)
    (Button2               #x0200)
    (Button3               #x0400)
    (Button4               #x0800)
    (Button5               #x1000)))

;;; ============================================================
;;; Section 2: Declarative Request Specifications
;;; ============================================================

(defparameter *x11-requests*
  `(
    ;; 1. CreateWindow & MapWindow (make-window combines them)
    (:name make-window
     :doc "Create a window and map it, creating GCs for white/black pixel foregrounds."
     :params (&key (width 512) (height 512) (x 0) (y 0) (border 1))
     :bindings ((window (logior *resource-id-base* (logand *resource-id-mask* 1)))
                (gc (logior *resource-id-base* (logand *resource-id-mask* 2)))
                (gc2 (logior *resource-id-base* (logand *resource-id-mask* 3)))
                (vals '(colormap backing-store event-mask bit-gravity border-pixel background-pixel))
                (n (length vals)))
     :post ((defparameter *window* window)
            (defparameter *gc* gc)
            (defparameter *gc2* gc2))
     :packet ((card8 1)                 ; opcode create-window
              (card8 0)                 ; depth
              (card16 (+ 8 n))          ; length
              (card32 window)           ; wid
              (card32 *root*)           ; parent
              (card16 x)
              (card16 y)
              (card16 width)
              (card16 height)
              (card16 border)
              (card16 0)                ; window-class
              (card32 0)                ; visual-id
              (card32 (value vals))
              (card32 0)                ; bg
              (card32 #x00ffffff)       ; border
              (card32 5)                ; bit-grav center
              (card32 1)                ; backing store
              (card32 (event '(PointerMotion ButtonPress ButtonRelease Exposure)))
              (card32 #x0)              ; colormap

              (card8 55)                ; opcode create-gc (gc)
              (card8 0)
              (card16 6)
              (card32 gc)
              (card32 window)
              (card32 #x0c)
              (card32 #x00ffffff)
              (card32 0)

              (card8 55)                ; opcode create-gc (gc2)
              (card8 0)
              (card16 6)
              (card32 gc2)
              (card32 window)
              (card32 #x0c)
              (card32 0)
              (card32 #x00ffffff)

              (card8 8)                 ; map-window
              (card8 0)
              (card16 2)
              (card32 window))
     :returns window)

    ;; 2. MapWindow
    (:name map-window
     :doc "Map the window, making it visible."
     :params (window)
     :packet ((card8 8)
              (card8 0)
              (card16 2)
              (card32 window)))

    ;; 3. DestroyWindow
    (:name destroy-window
     :doc "Destroy the window."
     :params (window)
     :packet ((card8 4)
              (card8 0)
              (card16 2)
              (card32 window)))

    ;; 4. ChangeWindowAttributes
    (:name change-window-attributes
     :doc "Change attributes of the window."
     :params (window value-mask values)
     :packet ((card8 2)
              (card8 0)
              (card16 (+ 3 (length values)))
              (card32 window)
              (card32 value-mask)
              (dolist (v values)
                (card32 v))))

    ;; 5. ConfigureWindow
    (:name configure-window
     :doc "Configure geometric and stacking parameters of the window."
     :params (window value-mask values)
     :packet ((card8 12)
              (card8 0)
              (card16 (+ 3 (length values)))
              (card32 window)
              (card16 value-mask)
              (card16 0)               ; unused
              (dolist (v values)
                (card32 v))))

    ;; 6. ClearArea
    (:name clear-area
     :doc "Clear a rectangular area in the window."
     :params (&key (x 0) (y 0) (w 0) (h 0) (exposures 0))
     :packet ((card8 61)
              (card8 exposures)
              (card16 4)
              (card32 *window*)
              (card16 x)
              (card16 y)
              (card16 w)
              (card16 h)))

    ;; 7. DrawWindow (PolySegment)
    (:name draw-window
     :doc "Draw a single line segment from (x1 y1) to (x2 y2)."
     :params (x1 y1 x2 y2 &key (gc '*gc*))
     :decls ((declare ((unsigned-byte 16) x1 y1 x2 y2)))
     :bindings ((segs (list (list x1 y1 x2 y2))))
     :packet ((card8 66)
              (card8 0)
              (card16 (+ 3 (* 2 (length segs))))
              (card32 *window*)
              (card32 gc)
              (dolist (s segs)
                (dolist (p s)
                  (card16 p)))))

    ;; 8. QueryPointer
    (:name query-pointer
     :doc "Query pointer coordinates and modifiers."
     :params ()
     :packet ((card8 38)
              (card8 0)
              (card16 2)
              (card32 *window*))
     :reply ((reply (card8))
             (same-screen (card8))
             (sequence-number (card16))
             (reply-length (card32))
             (root (card32))
             (child (card32))
             (root-x (card16))
             (root-y (card16))
             (win-x (card16))
             (win-y (card16)))
     :returns (values root-x root-y win-x win-y))

    ;; 9. ImageText8
    (:name imagetext8
     :doc "Draw text string on the window."
     :params (str &key (x 0) (y 0))
     :bindings ((n (length str))
                (p (pad n)))
     :packet ((card8 76)
              (card8 n)
              (card16 (+ 4 (/ (+ n p) 4)))
              (card32 *window*)
              (card32 *gc*)
              (card16 x)
              (card16 y)
              (string8 str)
              (dotimes (i p)
                (card8 0))))

    ;; 10. QueryExtension
    (:name query-extension
     :doc "Query if an extension is supported and get its major opcode."
     :params (name)
     :decls ((declare (type string name)))
     :bindings ((n (length name))
                (p (pad n)))
     :packet ((card8 98)
              (card8 0)
              (card16 (+ 2 (floor (+ n p) 4)))
              (card16 n)
              (card16 0)
              (string8 name)
              (dotimes (i p)
                (card8 0)))
     :reply ((reply (card8))
             (unused (card8))
             (sequence-number (card16))
             (reply-length (card32))
             (present (card8))
             (major-opcode (card8))
             (first-event (card8))
             (first-error (card8)))
     :returns major-opcode)

    ;; 11. BigRequestsEnable
    (:name big-requests-enable
     :doc "Enable support for requests larger than 256KB."
     :params ()
     :bindings ((opcode (unless *big-request-opcode*
                          (setf *big-request-opcode* (query-extension "BIG-REQUESTS")))))
     :packet ((card8 *big-request-opcode*)
              (card8 0)
              (card16 1)))

    ;; 12. PutImageBigReq
    (:name put-image-big-req
     :doc "Upload image data to the window using big requests."
     :params (img &key (dst-x 0) (dst-y 0))
     :decls ((declare (type (simple-array (unsigned-byte 8) 3) img)
                      (type (unsigned-byte 16) dst-x dst-y)))
     :bindings ((h-w-c (array-dimensions img))
                (h (first h-w-c))
                (w (second h-w-c))
                (img1 (sb-ext:array-storage-vector img))
                (n (length img1))
                (p (pad n)))
     :packet ((card8 72)
              (card8 2)
              (card16 0)                ; big request indicator
              (card32 (+ 7 (/ (+ n p) 4)))
              (card32 *window*)
              (card32 *gc*)
              (card16 w)
              (card16 h)
              (card16 dst-x)
              (card16 dst-y)
              (card8 0)
              (card8 24)
              (card16 0))
     :post ((write-sequence img1 *s*)
            (dotimes (i p)
              (write-byte 0 *s*))
            (force-output *s*)))

    ;; 13. FreeGC
    (:name free-gc
     :doc "Free a graphics context."
     :params (gc)
     :packet ((card8 60)
              (card8 0)
              (card16 2)
              (card32 gc)))

    ;; 14. CreateCursor
    (:name create-cursor
     :doc "Create a cursor from source and mask font glyphs."
     :params (cid source-font mask-font source-char mask-char
                  &key (fore-red 0) (fore-green 0) (fore-blue 0)
                       (back-red #xffff) (back-green #xffff) (back-blue #xffff))
     :packet ((card8 94)
              (card8 0)
              (card16 8)
              (card32 cid)
              (card32 source-font)
              (card32 mask-font)
              (card16 source-char)
              (card16 mask-char)
              (card16 fore-red)
              (card16 fore-green)
              (card16 fore-blue)
              (card16 back-red)
              (card16 back-green)
              (card16 back-blue)))

    ;; 15. OpenFont
    (:name open-font
     :doc "Open a server-side font by name."
     :params (fid name)
     :decls ((declare (type string name)))
     :bindings ((n (length name))
                (p (pad n)))
     :packet ((card8 45)
              (card8 0)
              (card16 (+ 3 (/ (+ n p) 4)))
              (card32 fid)
              (card16 n)
              (card16 0)
              (string8 name)
              (dotimes (i p)
                (card8 0))))

    ;; 16. CloseFont
    (:name close-font
     :doc "Close an opened font."
     :params (fid)
     :packet ((card8 46)
              (card8 0)
              (card16 2)
              (card32 fid)))

    ;; 17. GrabPointer
    (:name grab-pointer
     :doc "Actively grab control of the pointer."
     :params (grab-window event-mask &key (owner-events 0) (pointer-mode 1) (keyboard-mode 1) (confine-to 0) (cursor 0) (time 0))
     :packet ((card8 26)
              (card8 owner-events)
              (card16 6)
              (card32 grab-window)
              (card16 event-mask)
              (card8 pointer-mode)
              (card8 keyboard-mode)
              (card32 confine-to)
              (card32 cursor)
              (card32 time))
     :reply ((reply (card8))
             (status (card8))
             (sequence-number (card16))
             (reply-length (card32))
             (unused (inc-current 24)))
     :returns status)

    ;; 18. UngrabPointer
    (:name ungrab-pointer
     :doc "Release pointer grab."
     :params (&key (time 0))
     :packet ((card8 27)
              (card8 0)
              (card16 2)
              (card32 time)))

    ;; 19. GetKeyboardMapping
    (:name get-keyboard-mapping
     :doc "Query keyboard layout mapping."
     :params (first-keycode count)
     :packet ((card8 101)
              (card8 0)
              (card16 2)
              (card8 first-keycode)
              (card8 count)
              (card16 0))
     :reply ((reply (card8))
             (keysyms-per-keycode (card8))
             (sequence-number (card16))
             (reply-length (card32))
             (unused (inc-current 24)))
     :post ((let* ((num-keysyms (* count keysyms-per-keycode))
                   (keysyms (make-array num-keysyms :element-type '(unsigned-byte 32))))
              (dotimes (i num-keysyms)
                (setf (aref keysyms i) (card32)))
              (values keysyms keysyms-per-keycode)))
     :returns (values keysyms keysyms-per-keycode))
   ))

;;; ============================================================
;;; Section 3: Declarative Event Specifications
;;; ============================================================

(defparameter *x11-events*
  '((expose
     :code 12
     :doc "Parse Expose event."
     :fields ((code (card8))
              (unused (card8))
              (sequence-number (card16))
              (window (card32))
              (x (card16))
              (y (card16))
              (width (card16))
              (height (card16))
              (count (card16))
              (unused2 (inc-current 14)))
     :returns (values sequence-number window x y width height count))

    (motion-notify
     :code 6
     :doc "Parse MotionNotify event."
     :fields ((code (card8))
              (detail (card8))
              (sequence-number (card16))
              (time (card32))
              (root-window (card32))
              (event-window (card32))
              (child-window (card32))
              (root-x (card16))
              (root-y (card16))
              (event-x (card16))
              (event-y (card16))
              (state (card16))
              (same-screen-p (card8))
              (unused (card8)))
     :returns (values event-x event-y state time))

    (button-press
     :code 4
     :doc "Parse ButtonPress event."
     :fields ((code (card8))
              (detail (card8))
              (sequence-number (card16))
              (time (card32))
              (root-window (card32))
              (event-window (card32))
              (child-window (card32))
              (root-x (card16))
              (root-y (card16))
              (event-x (card16))
              (event-y (card16))
              (state (card16))
              (same-screen-p (card8))
              (unused (card8)))
     :returns (values detail event-x event-y state time))

    (button-release
     :code 5
     :doc "Parse ButtonRelease event."
     :fields ((code (card8))
              (detail (card8))
              (sequence-number (card16))
              (time (card32))
              (root-window (card32))
              (event-window (card32))
              (child-window (card32))
              (root-x (card16))
              (root-y (card16))
              (event-x (card16))
              (event-y (card16))
              (state (card16))
              (same-screen-p (card8))
              (unused (card8)))
     :returns (values detail event-x event-y state time))

    (key-press
     :code 2
     :doc "Parse KeyPress event."
     :fields ((code (card8))
              (detail (card8))
              (sequence-number (card16))
              (time (card32))
              (root-window (card32))
              (event-window (card32))
              (child-window (card32))
              (root-x (card16))
              (root-y (card16))
              (event-x (card16))
              (event-y (card16))
              (state (card16))
              (same-screen-p (card8))
              (unused (card8)))
     :returns (values detail event-x event-y state time))
   ))

;;; ============================================================
;;; Section 4: Code Emission Helpers
;;; ============================================================

(defun emit-request-function (spec)
  "Construct the full defun form for a request spec."
  (destructuring-bind (&key name doc params decls bindings packet reply returns post) spec
    (let* ((packet-code
             `(with-packet
                ,@packet))
           (body-forms
             `(,@(when packet-code (list packet-code))
               ,@post
               ,@(when reply
                   `((with-reply (read-reply-wait)
                       (let* ,reply
                         ,returns))))
               ,@(when (and (not reply) returns)
                   (list returns)))))
      `(defun ,name ,params
         ,@(when doc (list doc))
         ,@decls
         ,(if bindings
              `(let* ,bindings
                 ,@body-forms)
              `(progn
                 ,@body-forms))))))

(defun emit-event-parser (spec)
  "Construct the full defun form for an event parser spec."
  (destructuring-bind (name &key code doc fields returns) spec
    `(defun ,(intern (format nil "PARSE-~a" (string-upcase (string name)))) (r)
       ,@(when doc (list doc))
       (with-reply r
         (let* ,fields
           (assert (= ,code code))
           ,returns)))))

(defun generate-lookup-function (name alist-var-name)
  "Construct a generic lookup function for flags/bitmasks."
  `(defun ,name (es)
     (flet ((lookup (e)
              (cadr (assoc e ,alist-var-name))))
       (if (listp es)
           (loop for e in es sum (lookup e))
           (lookup es)))))

;;; ============================================================
;;; Section 5: Metadata Headers
;;; ============================================================

(defparameter *git-version*
  (handler-case
      (string-trim '(#\Space #\Tab #\Newline #\Return)
                   (with-output-to-string (s)
                     (sb-ext:run-program "/usr/bin/git" '("rev-parse" "HEAD")
                                         :output s)))
    (error () "unknown")))

(defparameter *generation-time*
  (multiple-value-bind (sec min hour day month year)
      (get-decoded-time)
    (format nil "~4d-~2,'0d-~2,'0d ~2,'0d:~2,'0d:~2,'0d"
            year month day hour min sec)))

(defun make-header-comments ()
  (list `(comment "Auto-generated by cl-cl-generator — do not edit manually.")
        `(comments ,(format nil "Generated: ~a" *generation-time*)
                   ,(format nil "Git:       ~a" *git-version*))))

;;; ============================================================
;;; Section 6: Generation Execution
;;; ============================================================

;; Ensure target directory exists
(ensure-directories-exist *output-dir*)

;; 1. Generate package.lisp
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
                
                #:parse-expose
                #:parse-motion-notify
                #:parse-button-press
                #:parse-button-release
                #:parse-key-press

                #:*s*
                #:*root*
                #:*window*
                #:*gc*
                #:*gc2*
                #:*big-request-opcode*)))
  *output-dir*)

;; 2. Generate pure-x11-gen.asd
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
                           (:file "x11-core"))))))
  (ensure-directories-exist asd-path)
  (with-open-file (stream asd-path
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (write-sequence (emit-cl asd-code) stream)))

;; 3. Generate x11-core.lisp
(let ((x11-core-code
        `(toplevel
           ,@(make-header-comments)
           (in-package :pure-x11-gen)

           (defparameter *s* nil "Socket for communication with X server.")
           (defparameter *resp* nil "Reply of the X server to a request")
           (defparameter *root* nil "Root ID as extracted from the initial reply of the X server.")
           (defparameter *window* nil)
           (defparameter *gc* nil)
           (defparameter *gc2* nil)
           (defparameter *big-request-opcode* nil)

           (defun pad (n)
             "Difference to next number that is divisible by 4."
             (if (= 0 (mod n 4))
                 0
                 (- (* 4 (1+ (floor n 4))) n)))

           (comment "Macros for packet writing and reply reading")
           (raw "
(defmacro with-packet (&body body)
  \"Write values into a list of bytes and send over the socket *s*.\"
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
         (write-sequence buf *s*)
         (force-output *s*)))))
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

           (defun read-reply-wait ()
             "Read standard 32-byte reply header and optional variable-length body from *s*."
             (let* ((buf (make-array 32 :element-type '(unsigned-byte 8))))
               (read-sequence buf *s*)
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
                         (read-sequence m *s*)
                         (values (concatenate '(vector (unsigned-byte 8)) buf m) sequence-number)))))))

           (defun read-connection-response ()
             "Read the initial connection response from X server."
             (let ((buf (make-array 8 :element-type '(unsigned-byte 8))))
               (sb-sys:read-n-bytes *s* buf 0 (length buf))
               (with-reply buf
                 (let ((success-state (card8))
                       (length-of-reason (card8))
                       (protocol-major-version (card16))
                       (protocol-minor-version (card16))
                       (reply-length (card16)))
                   (let ((m (make-array (+ 8 (* 4 reply-length)) :element-type '(unsigned-byte 8))))
                     (dotimes (i 8)
                       (setf (aref m i) (aref buf i)))
                     (sb-sys:read-n-bytes *s* m 8 (* 4 reply-length))
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

           (defun connect (&key (ip #(127 0 0 1)) (filename nil) (port 6000))
             "Connect to the X server."
             (defparameter *s*
               (if filename
                   (socket-make-stream (let ((s (make-instance 'local-socket :type :stream)))
                                         (socket-connect s filename)
                                         s)
                                       :element-type '(unsigned-byte 8)
                                       :input t
                                       :output t
                                       :buffering :none)
                   (socket-make-stream (let ((s (make-instance 'inet-socket :type :stream :protocol :tcp)))
                                         (socket-connect s ip port)
                                         s)
                                       :element-type '(unsigned-byte 8)
                                       :input t
                                       :output t
                                       :buffering :none)))
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

;; 4. Generate example.lisp
(write-source "example"
  `(toplevel
     ,@(make-header-comments)
     (defpackage :pure-x11-gen/example
       (:use :cl :pure-x11-gen)
       (:export #:run-x11-example))
     (in-package :pure-x11-gen/example)

     (defun run-x11-example ()
       "A simple demo client connecting to X11, creating a window, drawing to it, and printing events."
       (format t "Connecting to X server...~%")
       (handler-case
           (connect)
         (error (c)
           (format t "Failed to connect to X server: ~a~%" c)
           (return-from run-x11-example nil)))
       (format t "Creating window...~%")
       (let ((win (make-window :width 400 :height 300)))
         (format t "Window created with ID: ~a~%" win)
         (format t "Mapping window...~%")
         (map-window win)
         
         (format t "Drawing text and line...~%")
         (imagetext8 "Hello Pure X11!" :x 20 :y 50)
         (draw-window 20 60 200 60)
         
         (format t "Entering event loop. Press Ctrl+C to exit.~%")
         (loop
           (let ((reply (read-reply-wait)))
             (let ((code (aref reply 0)))
               (cond
                 ((= code 12)
                  (multiple-value-bind (seq w x y width height count) (parse-expose reply)
                    (declare (ignorable seq w count))
                    (format t "Expose event: x=~a, y=~a, w=~a, h=~a~%" x y width height)
                    ;; Redraw
                    (imagetext8 "Hello Pure X11!" :x 20 :y 50)
                    (draw-window 20 60 200 60)))
                 ((= code 6)
                  (multiple-value-bind (x y state time) (parse-motion-notify reply)
                    (declare (ignorable time))
                    (format t "MotionNotify event: x=~a, y=~a, state=~a~%" x y state)))
                 ((= code 4)
                  (multiple-value-bind (btn x y state time) (parse-button-press reply)
                    (declare (ignorable state time))
                    (format t "ButtonPress event: button=~a, x=~a, y=~a~%" btn x y)))
                 ((= code 5)
                  (multiple-value-bind (btn x y state time) (parse-button-release reply)
                    (declare (ignorable state time))
                    (format t "ButtonRelease event: button=~a, x=~a, y=~a~%" btn x y)))
                 (t
                  (format t "Received event code ~a~%" code))))))))
     )
  *output-dir*)

(format t "Successfully generated Pure X11 Example library at ~a~%" *output-dir*)
