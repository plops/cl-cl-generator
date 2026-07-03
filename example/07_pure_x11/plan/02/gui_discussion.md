# Plan 02 — High-Performance Network GUI & State Machines

This document analyzes the design of a fast, network-transparent, Athena-style GUI toolkit in Common Lisp using raw X11 socket communication.

---

## 1. Network Latency & Performance Primitives

To maintain a fast GUI response over a network (e.g. X11 forwarding over SSH or internet connections), we must **minimize round-trip times (RTT)**. Every synchronous request (where the client blocks waiting for a server reply) adds latency equal to the network ping.

### Primitives & Design Choices to Maximize Speed:
1.  **Asynchronous Only inside the Event Loop**:
    *   **No synchronous calls** like `QueryPointer`, `GetGeometry`, or `TranslateCoordinates` during user interaction.
    *   Instead, we rely entirely on **asynchronous event payloads** (e.g. `MotionNotify` events contain the cursor `(x, y)` and modifier state; `ConfigureNotify` contains updated window dimensions).
    *   The Lisp client keeps an in-memory mirror of the widget hierarchy's geometry to resolve positions locally.
2.  **X11 Server-Side Graphics (Core Fonts & Fills)**:
    *   Avoid client-side pixel rendering (uploading images is high-bandwidth and slow over network).
    *   Use `PolyFillRectangle` (flat background fills) and `PolySegment` (3D bevel line drawing).
    *   Use X11 Core Fonts via `OpenFont` and `ImageText8` text drawing. These render natively on the server side using server-cached fonts, requiring only a few bytes of network payload.
3.  **Athena-style 3D Bevels**:
    *   We draw classic 3D bevels using two GCs: `*gc*` (foreground/white) and `*gc2*` (background/black/shadow).
    *   *Raised Bevel*: White lines on top/left, black lines on bottom/right.
    *   *Sunken Bevel* (Pressed state): Black lines on top/left, white lines on bottom/right.

---

## 2. Declarative GUI Design

Instead of imperatively constructing windows, we declare the interface structure in a single nested S-expression:

```lisp
(ui-layout
  (panel :name :main-panel :x 0 :y 0 :w 400 :h 300 :bg #x00d0d0d0
    (label :name :title-lbl :text "Interactive GUI Demo" :x 20 :y 20)
    (button :name :btn-inc :text "Increment" :x 20 :y 60 :w 120 :h 30
            :on-click (lambda () (incf *counter*)))
    (button :name :btn-dec :text "Decrement" :x 160 :y 60 :w 120 :h 30
            :on-click (lambda () (decf *counter*)))
    (text-input :name :txt-input :x 20 :y 110 :w 260 :h 30 :default "Hello")
    (checkbox :name :chk-box :label "Enable Action" :x 20 :y 160 :w 150 :h 24)))
```

When this layout is compiled, we create **one single top-level X11 window** (reducing server resource utilization) and manage coordinates and events entirely on the client side using two spatial algorithms.

---

## 3. Spatial Event Assignment Algorithms

### A. 2D Quadtree for Mouse Hit-Testing (Zero-Latency Event Dispatch)
To handle mouse hover, clicks, and dragging efficiently without X11 subwindows:
1.  **Quadtree Structure**: The client builds a 2D Quadtree in memory containing the bounding boxes of all widgets.
2.  **Zero-Latency Routing**:
    *   When the server sends a single `ButtonPress` or `MotionNotify` event for the main window, the client queries the Quadtree with the cursor `(x, y)` coordinate.
    *   The Quadtree locates the targeted widget in $O(\log N)$ time locally, without querying the X11 server.
    *   The client updates the widget's internal state (e.g., transitions a button to `Pressed`) and issues a one-way `PolyFillRectangle` or `PolySegment` command to redraw only the affected bounding box.

### B. Delaunay Triangulation for Keyboard Navigation
Determining focus shift (e.g., when the user presses Arrow Keys `Up/Down/Left/Right` or `Tab`) traditionally requires manual focus chain linking. We solve this dynamically:
1.  **Spatial Graph Construction**:
    *   At compile time, we extract the center coordinates `(cx, cy)` of all focusable widgets.
    *   We construct the **Delaunay Triangulation** of these points.
    *   The edges of the triangulation form the focus adjacency graph.
2.  **Directional Event Dispatch**:
    *   When the user presses the `Right` arrow key while focused on widget $A$, the client checks all Delaunay edges incident to $A$.
    *   It measures the angles of these edges relative to the horizontal vector ($0^\circ$) and selects the closest neighbor $B$.
    *   Focus shifts to $B$ instantly. This yields a completely self-organizing keyboard navigation layout.

---

## 4. Window Resizing & Programming Paradigms

When the user resizes the window, the X server sends a `ConfigureNotify` event containing the new window width and height. How the GUI handles recalculating widget layouts and coordinates depends on the programming paradigm.

### A. Paradigm Comparison:
*   **Object-Oriented (OO)**: Widgets are stateful objects with layout bounds. Resizing recursively calls `.resize(new-w, new-h)` on layout managers.
    *   *Problem*: Leads to scattered, mutable state and layout synchronization bugs.
*   **Functional Reactive Programming (FRP)**: Window size is modeled as a continuous signal (`window-size-signal`), and widget sizes are derived signals that propagate changes dynamically.
    *   *Problem*: Elegant, but can introduce heavy performance overhead during high-frequency drag-to-resize events.
*   **Declarative Virtual Render (Elm Architecture)**:
    *   The UI is declared as a pure function of the window size and client state: `(render-ui width height state)`.
    *   *Solution*: This is the ideal match. The layout is rebuilt entirely from scratch upon resizing, and the spatial databases (Quadtree & Delaunay graph) are recomputed in memory.

### B. Declarative Resizing Flow:
1.  **ConfigureNotify Event (Resize)**:
    *   Update local variables `*window-width*` and `*window-height*` to the new dimensions.
    *   Call the user's pure layout function: `(setf *current-layout* (render-ui *window-width* *window-height* *state*))`.
    *   Rebuild the **Quadtree** and **Delaunay Triangulation** with the new absolute coordinates.
    *   Issue a `ClearArea` request (with `exposures = True`) to clear the canvas on the server side and trigger a full redraw.
2.  **Expose Event (Redraw)**:
    *   Traverse `*current-layout*` and render each widget asynchronously (with zero synchronous network queries).

---

## 5. Architectural Patterns: MVC vs. Model-Update-View (MUV)

### A. Model-View-Controller (MVC)
*   **How it works**: Models store state and notify observers. Views draw the graphics. Controllers modify the Model based on events.
*   **The Issue**: Traditional MVC is highly stateful and imperative. Views and Models become tightly coupled, and keeping state synchronized across many individual widgets (e.g. checking whether a button text matches the model state) becomes complex and prone to race conditions.

### B. Model-Update-View (MUV / The Elm Architecture) - Recommended
An alternative, purely functional pattern that provides a **single source of truth** and **unidirectional data flow**:

1.  **Model**: A single, immutable Lisp structure representing the entire application state.
    ```lisp
    (defstruct state
      (clicks 0)
      (input-buffer "")
      (action-enabled-p nil))
    ```
2.  **Update**: A pure function that takes the current `state` and an `action-msg` (e.g., `:increment`, `:decrement`, `:type-char`, `:toggle-checkbox`) and returns a new `state` structure.
    ```lisp
    (defun update (state msg)
      (ecase (car msg)
        (:increment
         (make-state :clicks (1+ (state-clicks state))
                     :input-buffer (state-input-buffer state)
                     :action-enabled-p (state-action-enabled-p state)))
        (:toggle-checkbox
         (make-state :clicks (state-clicks state)
                     :input-buffer (state-input-buffer state)
                     :action-enabled-p (not (state-action-enabled-p state))))))
    ```
3.  **View**: A pure function mapping the current `state` (and window size) to a virtual UI layout tree.
    ```lisp
    (defun view (w h state)
      `(panel :w ,w :h ,h
         (label :text ,(format nil "Clicks: ~a" (state-clicks state)) :x 20 :y 20)
         (button :text "Click Me" :x 20 :y 60 :w 120 :h 30 :msg (:increment))))
    ```

### Why MUV is Clean and High-Performance:
*   **No Redundant State**: Individual widgets do not store state. Focus, hover, and press states are easily managed at the toolkit level or in the Model.
*   **Ease of Testing**: Since `Update` and `View` are pure Lisp functions, you can unit-test your entire application logic, layout positioning, and user interaction flows offline without running an X server or opening socket streams.
*   **Unidirectional Flow**: Event -> Message -> Update -> New Model -> Re-render -> Rebuild Spatial Index.
