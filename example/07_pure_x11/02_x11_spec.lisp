;;;; 02_x11_spec.lisp — X11 core protocol request and event specifications

(in-package :cl-cl-generator/example-x11-gen)

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
     :doc "Create a window and map it, creating GCs for Athena 3D bevels and text."
     :params (&key (width 512) (height 512) (x 0) (y 0) (border 1))
     :bindings ((window (logior *resource-id-base* (logand *resource-id-mask* 1)))
                (gc-light (logior *resource-id-base* (logand *resource-id-mask* 2)))
                (gc-face (logior *resource-id-base* (logand *resource-id-mask* 3)))
                (gc-shadow (logior *resource-id-base* (logand *resource-id-mask* 4)))
                (gc-dark (logior *resource-id-base* (logand *resource-id-mask* 5)))
                (gc-text (logior *resource-id-base* (logand *resource-id-mask* 6)))
                (vals '(colormap backing-store event-mask bit-gravity border-pixel background-pixel))
                (n (length vals)))
     :post ((defparameter *window* window)
            (defparameter *gc-light* gc-light)
            (defparameter *gc-face* gc-face)
            (defparameter *gc-shadow* gc-shadow)
            (defparameter *gc-dark* gc-dark)
            (defparameter *gc-text* gc-text))
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
              (card32 (event '(PointerMotion ButtonPress ButtonRelease KeyPress Exposure StructureNotify)))
              (card32 #x0)              ; colormap

              (card8 55)                ; opcode create-gc (gc-light: white fg, 0 bg)
              (card8 0)
              (card16 6)
              (card32 gc-light)
              (card32 window)
              (card32 #x0c)
              (card32 #x00ffffff)
              (card32 0)

              (card8 55)                ; opcode create-gc (gc-face: light gray fg/bg)
              (card8 0)
              (card16 6)
              (card32 gc-face)
              (card32 window)
              (card32 #x0c)
              (card32 #x00c0c0c0)
              (card32 #x00c0c0c0)

              (card8 55)                ; opcode create-gc (gc-shadow: mid gray fg, face bg)
              (card8 0)
              (card16 6)
              (card32 gc-shadow)
              (card32 window)
              (card32 #x0c)
              (card32 #x00808080)
              (card32 #x00c0c0c0)

              (card8 55)                ; opcode create-gc (gc-dark: dark gray fg, face bg)
              (card8 0)
              (card16 6)
              (card32 gc-dark)
              (card32 window)
              (card32 #x0c)
              (card32 #x00404040)
              (card32 #x00c0c0c0)

              (card8 55)                ; opcode create-gc (gc-text: black fg, face bg)
              (card8 0)
              (card16 6)
              (card32 gc-text)
              (card32 window)
              (card32 #x0c)
              (card32 #x00000000)
              (card32 #x00c0c0c0)

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
     :params (x1 y1 x2 y2 &key (gc *gc-text*))
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

    ;; 7b. DrawLine (simpler single segment)
    (:name draw-line
     :doc "Draw a single line segment from (x1,y1) to (x2,y2) using specified GC."
     :params (x1 y1 x2 y2 &key (gc *gc-text*))
     :packet ((card8 66)
              (card8 0)
              (card16 5)
              (card32 *window*)
              (card32 gc)
              (card16 x1) (card16 y1) (card16 x2) (card16 y2)))

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
     :params (str &key (x 0) (y 0) (gc *gc-text*))
     :bindings ((n (length str))
                (p (pad n)))
     :packet ((card8 76)
              (card8 n)
              (card16 (+ 4 (/ (+ n p) 4)))
              (card32 *window*)
              (card32 gc)
              (card16 x)
              (card16 y)
              (string8 str)
              (dotimes (i p)
                (card8 0))))

    ;; 9b. PolyRectangle
    (:name poly-rectangle
     :doc "Draw outlines of one or more rectangles."
     :params (rects &key (gc *gc-text*))
     :packet ((card8 74)
              (card8 0)
              (card16 (+ 3 (* 2 (length rects))))
              (card32 *window*)
              (card32 gc)
              (dolist (r rects)
                (dolist (v r)
                  (card16 v)))))

    ;; 9c. PolyFillRectangle
    (:name poly-fill-rectangle
     :doc "Draw one or more filled rectangles."
     :params (rects &key (gc *gc-text*))
     :packet ((card8 76)
              (card8 0)
              (card16 (+ 3 (* 2 (length rects))))
              (card32 *window*)
              (card32 gc)
              (dolist (r rects)
                (dolist (v r)
                  (card16 v)))))

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
              (card32 *gc-text*)
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
             (unused (inc-current 24))
             (keysyms (let* ((num-keysyms (* count keysyms-per-keycode))
                             (arr (make-array num-keysyms :element-type '(unsigned-byte 32))))
                        (dotimes (i num-keysyms)
                          (setf (aref arr i) (card32)))
                        arr)))
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

    (configure-notify
     :code 22
     :doc "Parse ConfigureNotify event."
     :fields ((code (card8))
              (unused (card8))
              (sequence-number (card16))
              (event (card32))
              (window (card32))
              (above-sibling (card32))
              (x (card16))
              (y (card16))
              (width (card16))
              (height (card16))
              (border-width (card16))
              (override-redirect (card8))
              (unused2 (inc-current 5)))
     :returns (values width height))
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
           (assert (= ,code (logand code #x7f)))
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
