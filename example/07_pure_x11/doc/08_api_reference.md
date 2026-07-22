# Complete API Reference

> Part of the [Pure X11 GUI Toolkit](../README.md) documentation.
> Generated: 2026-07-22

## Overview

This reference provides complete documentation for all functions, macros, structures, special parameters, and exported symbols in the `pure-x11-gen` package.

---

## 1. Connection & Protocol Setup

### `connect`
- **Signature:** `connect (&key (ip #(127 0 0 1)) filename port display)`
- **Description:** Establishes socket connection to the X11 display server, authenticates via `MIT-MAGIC-COOKIE-1` from `.Xauthority`, negotiates initial handshake payload, initializes `*root*` and `*root-depth*`, and enables BigRequests extension.
- **Parameters:**
  - `ip`: IP byte array vector for TCP connections (default `#(127 0 0 1)`).
  - `filename`: String path to Unix domain socket (e.g. `"/tmp/.X11-unix/X0"`).
  - `port`: TCP port number (default `6000 + display-number`).
  - `display`: Display string (defaults to `$DISPLAY` environment variable or `":0"`).
- **Return Value:** `max-request-length` integer returned by BigRequests query.
- **Example:**
  ```lisp
  (pure-x11-gen:connect :display ":0")
  ```

### `big-requests-enable`
- **Signature:** `big-requests-enable ()`
- **Description:** Queries the X server for the `BIG-REQUESTS` extension and enables support for request packets exceeding 256 KB.
- **Return Value:** Maximum supported request length (32-bit integer).

### `query-extension`
- **Signature:** `query-extension (name)`
- **Description:** Queries the X server whether named extension `name` (string) is supported.
- **Return Value:** Extension major opcode integer.

### `intern-atom`
- **Signature:** `intern-atom (name &key (only-if-exists 0))`
- **Description:** Interns (resolves) a string atom name to a 32-bit atom ID. Used for ICCCM protocol atoms like `"WM_PROTOCOLS"` and `"WM_DELETE_WINDOW"`.
- **Return Value:** Atom ID (32-bit integer).

### `change-property`
- **Signature:** `change-property (window property type data &key (mode 0) (format 32))`
- **Description:** Sets a window property. Used to announce ICCCM `WM_PROTOCOLS` support by setting the `WM_PROTOCOLS` atom on the window.

---

## 2. Window & Resource Management

### `make-window`
- **Signature:** `make-window (&key (width 512) (height 512) (x 0) (y 0) (border 1))`
- **Description:** Allocates a window resource ID, creates the window, allocates 5 Graphics Contexts for Athena 3D bevels (`*gc-light*`, `*gc-face*`, `*gc-shadow*`, `*gc-dark*`, `*gc-text*`), maps the window, sets default parameters (`*window*`), and returns the window ID.
- **Return Value:** Window resource ID (integer).

### `map-window`
- **Signature:** `map-window (window)`
- **Description:** Maps window `window` onto the screen, making it visible.

### `destroy-window`
- **Signature:** `destroy-window (window)`
- **Description:** Destroys window `window` and releases associated server resources.

### `change-window-attributes`
- **Signature:** `change-window-attributes (window value-mask values)`
- **Description:** Changes window attributes specified by bitmask `value-mask` and list of integer values `values`.

### `configure-window`
- **Signature:** `configure-window (window value-mask values)`
- **Description:** Configures geometric position, size, border width, and stacking parameters.

---

## 3. Drawing & Graphics Contexts

### `draw-line`
- **Signature:** `draw-line (x1 y1 x2 y2 &key (gc *gc-text*))`
- **Description:** Draws a single line segment from `(x1, y1)` to `(x2, y2)` using graphics context `gc`.

### `draw-window`
- **Signature:** `draw-window (x1 y1 x2 y2 &key (gc *gc-text*))`
- **Description:** Alias for drawing a line segment via `PolySegment`.

### `clear-area`
- **Signature:** `clear-area (&key (x 0) (y 0) (w 0) (h 0) (exposures 0))`
- **Description:** Clears a rectangular region in `*window*` to background color.

### `imagetext8`
- **Signature:** `imagetext8 (str &key (x 0) (y 0) (gc *gc-text*))`
- **Description:** Renders single-byte ASCII string `str` at coordinate `(x, y)` using server core font in `gc`. Automatically appends padding bytes to 4-byte boundary.

### `poly-rectangle`
- **Signature:** `poly-rectangle (rects &key (gc *gc-text*))`
- **Description:** Draws outline boundaries for a list of rectangles `rects` where each element is `(x y width height)`.

### `poly-fill-rectangle`
- **Signature:** `poly-fill-rectangle (rects &key (gc *gc-text*))`
- **Description:** Draws filled solid rectangles for a list of rects `(x y width height)`.

### `poly-arc`
- **Signature:** `poly-arc (arcs &key (gc *gc-text*))`
- **Description:** Draws arc outlines for a list of arcs `(x y width height angle1 angle2)` where angles are specified in 1/64th of a degree.

### `poly-fill-arc`
- **Signature:** `poly-fill-arc (arcs &key (gc *gc-text*))`
- **Description:** Draws filled sector arcs for a list of arcs `(x y width height angle1 angle2)`.

### `create-gc`
- **Signature:** `create-gc (gc &key (foreground #x000000) (background #x00ffffff))`
- **Description:** Creates a new Graphics Context resource `gc` with specified 24-bit RGB foreground and background colors.

### `free-gc`
- **Signature:** `free-gc (gc)`
- **Description:** Frees Graphics Context resource `gc`.

---

## 4. Offscreen Pixmaps & Image Operations

### `create-pixmap`
- **Signature:** `create-pixmap (pix width height &key (depth 24))`
- **Description:** Creates an offscreen pixmap drawable resource `pix` of specified `width`, `height`, and bit `depth`.

### `free-pixmap`
- **Signature:** `free-pixmap (pix)`
- **Description:** Destroys offscreen pixmap resource `pix`.

### `copy-area`
- **Signature:** `copy-area (src dst gc src-x src-y dst-x dst-y width height)`
- **Description:** Copies pixel rectangle from source drawable `src` to destination drawable `dst` using graphics context `gc`.

### `put-image-big-req`
- **Signature:** `put-image-big-req (img &key (dst-x 0) (dst-y 0))`
- **Description:** Uploads raw 3D pixel byte array `img` (dimensions `[height, width, channels]`) to `*window*` using BigRequests protocol headers.

---

## 5. Input & Keyboard Navigation

### `query-pointer`
- **Signature:** `query-pointer ()`
- **Description:** Queries pointer coordinates and modifier bitmask.
- **Return Values:** `(values root-x root-y win-x win-y)`

### `grab-pointer`
- **Signature:** `grab-pointer (grab-window event-mask &key owner-events pointer-mode keyboard-mode confine-to cursor time)`
- **Description:** Actively grabs pointer control. Returns status code integer.

### `ungrab-pointer`
- **Signature:** `ungrab-pointer (&key (time 0))`
- **Description:** Releases active pointer grab.

### `get-keyboard-mapping`
- **Signature:** `get-keyboard-mapping (first-keycode count)`
- **Description:** Queries keycode mapping table from X server.
- **Return Values:** `(values keysyms keysyms-per-keycode)`

---

## 6. Fonts & Cursor Management

### `open-font`
- **Signature:** `open-font (fid name)`
- **Description:** Opens server-side font by name string `name` (e.g. `"fixed"`) into font resource ID `fid`.

### `close-font`
- **Signature:** `close-font (fid)`
- **Description:** Closes opened font resource `fid`.

### `create-cursor`
- **Signature:** `create-cursor (cid source-font mask-font source-char mask-char &key colors...)`
- **Description:** Creates custom cursor resource `cid` from glyph characters in opened fonts.

---

## 7. Widget System & Layout Engine

### `defstruct widget`
- **Slots:** `type`, `name`, `x`, `y`, `w`, `h`, `props`, `children`.
- **Functions:** `make-widget`, `widget-p`, `widget-type`, `widget-name`, `widget-x`, `widget-y`, `widget-w`, `widget-h`, `widget-props`, `widget-children`.

### `parse-node`
- **Signature:** `parse-node (node)`
- **Description:** Parses S-expression representation into a `widget` struct instance.

### `resolve-layout`
- **Signature:** `resolve-layout (node &optional default-x default-y default-w default-h)`
- **Description:** Recursively calculates absolute pixel coordinates for widget tree `node` and returns resolved root `widget` struct.

### `solve-glue`
- **Signature:** `solve-glue (glue-items available-space)`
- **Description:** TeX glue distribution solver. Accepts list of `glue` structs and returns integer size allocation list.

### `register-widget`
- **Signature:** `register-widget (type-name render-fn)`
- **Description:** Registers `render-fn` renderer callback for widget type string `type-name`. `render-fn` signature: `(w-struct focused pressed hovered)`.

---

## 8. Event Loop & Redraw Tier

### `run-gui`
- **Signature:** `run-gui (update-fn view-fn initial-state &key tick-interval tick-msg init-fn)`
- **Description:** Main MUV event loop. Orchestrates connection, window mapping, layout resolution, event handling, state updates, and double-buffered redrawing.

### Event Parsers
- `parse-expose (reply-buffer)`
- `parse-motion-notify (reply-buffer)`
- `parse-button-press (reply-buffer)`
- `parse-button-release (reply-buffer)`
- `parse-key-press (reply-buffer)`
- `parse-configure-notify (reply-buffer)`
- `parse-client-message (reply-buffer)`

### Modular Event Handlers
- `handle-expose-event (layout)` — Triggers full redraw on Expose events.
- `handle-configure-event (reply layout rebuild-layout-fn)` — Handles window resize.
- `handle-motion-event (reply layout)` — Updates hover state on mouse motion.
- `handle-button-press-event (reply layout)` — Handles mouse press, updates focus/pressed state.
- `handle-button-release-event (reply layout state update-fn rebuild-layout-fn)` — Dispatches widget click messages, returns updated state.
- `handle-key-press-event (reply layout state keyboard-map update-fn rebuild-layout-fn)` — Dispatches keyboard input, returns updated state.
- `handle-client-message-event (reply)` — Returns `:close` when `WM_DELETE_WINDOW` is received.

---

## Global Variables & Special Parameters

| Symbol | Type | Description |
| :--- | :--- | :--- |
| `*s*` | Stream / Socket | Active socket stream connected to X server. |
| `*root*` | Integer ID | Root window resource ID of default display screen. |
| `*root-depth*` | Integer | Bit depth of root window (typically 24). |
| `*window*` | Integer ID | Active main application window ID. |
| `*gc-light*` | Integer ID | Graphics Context for Athena 3D bevel highlight (`#ffffff`). |
| `*gc-face*` | Integer ID | Graphics Context for widget background fill (`#c0c0c0`). |
| `*gc-shadow*` | Integer ID | Graphics Context for Athena 3D bevel mid-shadow (`#808080`). |
| `*gc-dark*` | Integer ID | Graphics Context for Athena 3D bevel dark outline (`#404040`). |
| `*gc-text*` | Integer ID | Graphics Context for foreground text & border lines (`#000000`). |
| `*packet-buffer*` | List | Accumulator list for buffered output packets during `with-buffered-output`. |
| `*pending-events*` | List | Queue holding unhandled X11 event buffers. |
| `*wm-protocols-atom*` | Integer | Interned atom ID for `WM_PROTOCOLS` ICCCM property. |
| `*wm-delete-window-atom*` | Integer | Interned atom ID for `WM_DELETE_WINDOW` ICCCM close message. |
| `*resource-id-base*` | Integer | Base offset for client-allocated X11 resource IDs. |
| `*resource-id-mask*` | Integer | Bitmask for client resource ID space. |
| `*resource-id-counter*` | Integer | Monotonically incrementing counter for resource ID allocation. |

---

## Complete Exported Symbols List (`package.lisp`)

```lisp
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
           #:create-pixmap
           #:free-pixmap
           #:copy-area
           #:*root-depth*
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
           #:parse-client-message
           #:handle-expose-event
           #:handle-configure-event
           #:handle-motion-event
           #:handle-button-press-event
           #:handle-button-release-event
           #:handle-key-press-event
           #:handle-client-message-event
           #:intern-atom
           #:change-property
           #:*wm-protocols-atom*
           #:*wm-delete-window-atom*
           #:draw-line
           #:*s*
           #:*root*
           #:*window*
           #:*gc-light*
           #:*gc-face*
           #:*gc-shadow*
           #:*gc-dark*
           #:*gc-text*
           #:*resource-id-base*
           #:*resource-id-mask*
           #:*resource-id-counter*
           #:*packet-buffer*
           #:with-buffered-output
           #:flush-packets
           #:resolve-layout
           #:widget-p
           #:*big-request-opcode*))
```
