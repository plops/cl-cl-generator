# Pure X11 Client Library (`pure-x11-gen`)

This directory contains a **pure-Lisp, raw socket-based X11 client library** generated dynamically using the `cl-cl-generator` transpiler. 

Unlike traditional libraries that bind to `Xlib` or `XCB` (which are written in C), this library communicates directly with the X11 server by writing binary packets to a network stream. It requires **no external C libraries** and works anywhere Common Lisp has a socket implementation.

---

## 1. What is X11? A Brief Introduction

The **X Window System (X11)** uses a **client-server architecture**:
*   **The Server (X Server)**: The program running on your computer that controls the physical display, keyboard, mouse, and graphics hardware.
*   **The Client**: Your application (this Lisp program). It connects to the X Server over a socket (local Unix domain socket or TCP port 6000).

When your program wants to do something (like draw a line or show a window), it sends a **Request packet** to the server. When the user interacts with the mouse or keyboard, or when a window becomes visible, the server sends an **Event packet** back to your program.

### Protocol Basics
*   **Requests**: Serialized binary packets. Every request starts with a 1-byte opcode. Most requests are one-way (asynchronous) to maximize performance.
*   **Replies**: Sent by the server in response to query requests (like checking pointer positions).
*   **Events**: Asynchronous notifications sent from the server (always 32 bytes).

---

## 2. Core Concepts of the Library

### Sockets and Streams
Communication happens via a socket stream stored in `*s*`. 
*   To send a packet, we serialize values (bytes, 16-bit integers, 32-bit integers) onto a buffer and write it to the socket.
*   To read, we wait for bytes from the socket.

### Resource IDs
X11 requires the client to allocate unique 32-bit IDs for windows, graphics contexts (GCs), and fonts before creating them.
*   When we connect, the server sends a **Resource ID Base** and a **Resource ID Mask**.
*   We generate new IDs by combining the base and mask using bitwise logic (e.g. `(logior base (logand mask counter))`).

### Padding
X11 requires all requests to be aligned to **4-byte boundaries**. If a string or array length is not a multiple of 4, we must append padding bytes (zeros) using the generated `pad` function.

---

## 3. The Code Generation Architecture

This library is generated from declarative tables in `gen.lisp`:
*   `*x11-requests*`: Defines requests (opcodes, structures, and parameters).
*   `*x11-events*`: Defines event specs (opcodes and binary field layouts).

The transpiler uses generator-time loops like `,@(loop for req in *x11-requests* ...)` to automatically output the functions for serialization and parsing, eliminating hundreds of lines of repetitive, error-prone binary formatting boilerplate.

---

## 4. API Reference

### Connection & Setup
*   `connect (&key ip filename port)`: Connects to the X server (via local Unix sockets or TCP), negotiates the initial connection handshake, and retrieves server constants (like screen size, root window ID, and resource mask).
*   `big-requests-enable ()`: Enables the X11 extension for sending very large request payloads (e.g., big image uploads).

### Window Management
*   `make-window (&key width height x y border)`: Creates a new window, maps (shows) it on the screen, and creates two graphics contexts (`*gc*` for white pixel drawing and `*gc2*` for black pixel drawing). Returns the unique window ID.
*   `map-window (window)`: Makes the window visible on the screen.
*   `destroy-window (window)`: Destroys the window and releases its resources.

### Drawing
*   `draw-window (x1 y1 x2 y2 &key gc)`: Draws a line segment from `(x1, y1)` to `(x2, y2)`. By default, it uses the foreground graphics context `*gc*`.
*   `imagetext8 (str &key x y)`: Draws a single-byte string `str` at coordinate `(x, y)`.
*   `put-image-big-req (img &key dst-x dst-y)`: Uploads a 3D raw byte array of pixels to the window using high-performance big request packets.

### Input & Querying
*   `query-pointer ()`: Queries and returns multiple values: `(values root-x root-y win-x win-y)` indicating the current mouse position.
*   `get-keyboard-mapping (first-keycode count)`: Queries the keyboard mapping layout from the server.
*   `grab-pointer (grab-window event-mask &key ...)`: Grabs exclusive mouse pointer control.
*   `ungrab-pointer (&key time)`: Releases pointer grab.

### Event Parsers
Events are read from the socket using `(read-reply-wait)`. You inspect the first byte (the event code) and call the corresponding event parser to extract values:
*   `parse-expose (reply-buffer)`: Extracts `(values sequence-number window x y width height count)`. Tells you which part of the window needs redrawing.
*   `parse-motion-notify (reply-buffer)`: Extracts `(values event-x event-y state time)`. Tells you the cursor coordinates.
*   `parse-button-press (reply-buffer)`: Extracts `(values detail-button event-x event-y state time)`.
*   `parse-button-release (reply-buffer)`: Extracts `(values detail-button event-x event-y state time)`.

---

## 5. Walkthrough of the Demo Client

The generated demo in `source/example.lisp` demonstrates how to coordinate these calls into a working window application:

```lisp
(defun run-x11-example ()
  ;; 1. Connect to the local X Server (starts handshake)
  (connect)

  ;; 2. Create the window and show it on the display
  (let ((win (make-window :width 400 :height 300)))
    (map-window win)
    
    ;; 3. Initial drawing (some text and a line)
    (imagetext8 "Hello Pure X11!" :x 20 :y 50)
    (draw-window 20 60 200 60)
    
    ;; 4. Start the event loop
    (loop
      ;; Wait for an event packet (32 bytes) from the X server
      (let* ((reply (read-reply-wait))
             (code (aref reply 0)))
        (cond
          ;; Code 12 = Expose event (window exposed, needs redraw)
          ((= code 12)
           (multiple-value-bind (seq w x y width height count) (parse-expose reply)
             (declare (ignorable seq w count))
             (format t "Expose event: x=~a, y=~a, w=~a, h=~a~%" x y width height)
             ;; Redraw graphics
             (imagetext8 "Hello Pure X11!" :x 20 :y 50)
             (draw-window 20 60 200 60)))
          
          ;; Code 6 = MotionNotify (mouse moved inside window)
          ((= code 6)
           (multiple-value-bind (x y state time) (parse-motion-notify reply)
             (declare (ignorable time))
             (format t "MotionNotify event: x=~a, y=~a, state=~a~%" x y state)))
          
          ;; Code 4 = ButtonPress (mouse button clicked)
          ((= code 4)
           (multiple-value-bind (btn x y state time) (parse-button-press reply)
             (declare (ignorable state time))
             (format t "ButtonPress event: button=~a, x=~a, y=~a~%" btn x y)))
          
          (t
           (format t "Received event code ~a~%" code)))))))
```

---

## 6. How to Run the Example

Start an SBCL process, add the generated source folder to your central registry, quickload it, and run:

```lisp
(push "/workspace/src/cl-cl-generator/example/07_pure_x11/source/" asdf:*central-registry*)
(ql:quickload :pure-x11-gen)
(load "/workspace/src/cl-cl-generator/example/07_pure_x11/source/example.lisp")

;; Run the client!
(pure-x11-gen/example:run-x11-example)
```
