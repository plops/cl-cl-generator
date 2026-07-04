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

### 4. API Reference

### Connection & Setup
*   `connect (&key ip filename port)`: Connects to the X server, negotiates connection handshake, and retrieves server constants.
*   `big-requests-enable ()`: Enables the X11 extension for sending very large request payloads (e.g., big image uploads).

### Window & GC Management
*   `make-window (&key width height x y border)`: Creates a new window, maps it on the screen, and creates 5 Graphics Contexts:
    *   `*gc-light*`: Bevel highlight (white, `#ffffff`)
    *   `*gc-face*`: Widget face fill/background (light gray, `#c0c0c0`)
    *   `*gc-shadow*`: Bevel shadow (mid gray, `#808080`)
    *   `*gc-dark*`: Bevel dark edge (dark gray, `#404040`)
    *   `*gc-text*`: Default text and border color (black, `#000000`)
*   `map-window (window)`: Makes the window visible on the screen.
*   `destroy-window (window)`: Destroys the window and releases its resources.

### Drawing & Buffering
*   `draw-line (x1 y1 x2 y2 &key gc)`: Draws a line segment from `(x1, y1)` to `(x2, y2)` using the specified Graphics Context (defaults to `*gc-text*`).
*   `imagetext8 (str &key x y gc)`: Draws a single-byte string `str` at coordinate `(x, y)` using the specified GC (defaults to `*gc-text*`).
*   `with-buffered-output (&body body)`: Executes the body with request buffering enabled. All X11 packets generated inside the body are accumulated and written to the socket in a single batch, minimizing RTT overhead.
*   `flush-packets ()`: Flushes the accumulated packets to the socket.

### Widgets & Layout Engine
*   `defstruct widget`: Standard structure representing a widget node (`type`, `name`, `x`, `y`, `w`, `h`, `props`, `children`).
*   `register-widget (type-name render-fn)`: Registers a renderer function for a widget type. The renderer function is called as `(funcall render-fn w-struct focused pressed hovered)`.
*   `render-layout (layout focused pressed hovered)`: Renders the layout tree starting from the root node.
*   `defstruct glue`: Represents layout elasticity (`natural` size, `stretch` factor, and `shrink` factor).
*   `solve-glue (items available-space)`: Distributes space among a list of glue structures using TeX's layout algorithm.
*   `compute-box-layout (w-struct axis)`: Lays out children of `hbox` (`axis=:x`) or `vbox` (`axis=:y`) container nodes.

### Event loop & Parsers
*   `run-gui (update-fn view-fn initial-state)`: Starts the Elm-style Model-Update-View (MUV) event loop with state dirty-tracking and partial widget redraws.
*   `parse-expose (reply-buffer)`: Parses Expose events.
*   `parse-motion-notify (reply-buffer)`: Parses mouse motion coordinates.
*   `parse-button-press (reply-buffer)`: Parses mouse clicks.
*   `parse-button-release (reply-buffer)`: Parses mouse releases.
*   `parse-key-press (reply-buffer)`: Parses key presses.
*   `parse-configure-notify (reply-buffer)`: Parses window resize notifications.

---

## 5. Walkthrough of the Demo Client

The generated demo in `source/example.lisp` demonstrates how to coordinate these calls into a working window application:

```lisp
(defstruct app-state
  (clicks 0)
  (input-buffer "Type here")
  (cursor-pos 9)
  (checkbox-val nil))

(defun update (state msg)
  "Pure state update function."
  (let ((clicks (app-state-clicks state))
        (buf (app-state-input-buffer state))
        (pos (app-state-cursor-pos state))
        (chk (app-state-checkbox-val state)))
    (case (car msg)
      (:increment
       (make-app-state :clicks (1+ clicks) :input-buffer buf :cursor-pos pos :checkbox-val chk))
      (:decrement
       (make-app-state :clicks (1- clicks) :input-buffer buf :cursor-pos pos :checkbox-val chk))
      (:toggle-checkbox
       (make-app-state :clicks clicks :input-buffer buf :cursor-pos pos :checkbox-val (not chk)))
      (:text-change
       (let ((new-text (cadr msg))
             (new-pos (caddr msg)))
         (make-app-state :clicks clicks :input-buffer new-text :cursor-pos new-pos :checkbox-val chk)))
      (:cursor-move
       (let ((new-pos (caddr msg)))
         (make-app-state :clicks clicks :input-buffer buf :cursor-pos new-pos :checkbox-val chk)))
      (t state))))

(defun view (w h state)
  "Pure layout render function returning the virtual DOM."
  (let ((clicks (app-state-clicks state))
        (buf (app-state-input-buffer state))
        (pos (app-state-cursor-pos state))
        (chk (app-state-checkbox-val state)))
    `(panel :name :root :x 0 :y 0 :w ,w :h ,h
       (vbox :name :main-vbox :x 10 :y 10 :w ,(- w 20) :h ,(- h 20) :padding 0 :spacing 10
         (label :name :title :text ,(format nil "Athena GUI Demo (Clicks: ~a)" clicks)
                :glue (:natural 20 :stretch 0 :shrink 0))
         (hbox :name :buttons :glue (:natural 30 :stretch 0 :shrink 0) :spacing 10
           (button :name :btn-inc :text "Increment" :msg (:increment)
                   :glue (:natural 120 :stretch 1 :shrink 0))
           (button :name :btn-dec :text "Decrement" :msg (:decrement)
                   :glue (:natural 120 :stretch 1 :shrink 0)))
         (text-input :name :txt :text ,buf
                     :cursor-pos ,pos
                     :msg-change (:text-change)
                     :glue (:natural 30 :stretch 1 :shrink 0))
         (checkbox :name :chk :label "Enable Action Mode"
                   :checked-p ,chk
                   :msg (:toggle-checkbox)
                   :glue (:natural 24 :stretch 0 :shrink 0))))))

(defun run-x11-example ()
  "Connect to X11 and run the declarative GUI application."
  (run-gui #'update #'view (make-app-state)))
```

---

## 6. How to Run the Example

Start an SBCL process, add the generated source folder to your central registry, quickload it, and run:

```lisp
(push "/workspace/src/cl-cl-generator/example/07_pure_x11/source/" asdf:*central-registry*)
(ql:quickload :pure-x11-gen)

;; Run the client!
(pure-x11-gen/example:run-x11-example)
```
