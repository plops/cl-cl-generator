# plan 02 — GUI Widgets Documentation Blueprint

This document acts as the API specification and architectural documentation for the pure Lisp X11 declarative widget toolkit.

---

## 1. Architectural Overview (The Elm Architecture / MUV)

The toolkit operates as a **single-window, windowless-widget, retained-mode system** driven by unidirectional data flow (Model-Update-View):

```
       +---------------------------------------------+
       |                                             |
       v                                             |
+------------+     Action Msg     +------------+     |
|   State    | -----------------> |   Update   |     |
|  (Model)   |                    | (Modifier) |     |
+------------+                    +------------+     |
       |                                             |
       | state                                       |
       v                                             |
+------------+                                       |
|    View    |                                       |
| (Renderer) |                                       |
+------------+                                       |
       |                                             |
       | virtual UI tree                             |
       v                                             |
+------------+                                       |
|  Layout &  |                                       |
| Spatial DB |                                       |
+------------+                                       |
       |                                             |
       | coordinates & bounds                        |
       v                                             |
+------------+        X11 Event                      |
| X11 Canvas | --------------------------------------+
+------------+
```

1.  **State (Model)**: A single, immutable structure holding all application state.
2.  **Update (Controller)**: A pure function that takes the current state and an action message, returning a new state.
3.  **View (Renderer)**: A pure function mapping the current state (and window size) to a nested S-expression tree.
4.  **Layout Engine**: Processes the S-expression tree to determine absolute coordinates, rebuilding the **Mouse Hit-Testing (Bounding Boxes)** index and the **Keyboard Adjacency (Cone Proximity Graph)** in memory.
5.  **Event Loop**: Listens for raw X11 events, dispatches them through the spatial indexes to trigger state transitions or update messages, and requests redraws.

---

## 2. Declarative Layout DSL Reference

The user-defined layout function `(render-ui width height state)` returns a nested list structure representing the UI elements.

### Layout Node Types:

#### A. `panel`
A container node that groups child nodes and draws a flat background.
*   **Properties**:
    *   `:name` (keyword): Unique identifier.
    *   `:x`, `:y`, `:w`, `:h` (integers): Position and dimensions.
    *   `:bg` (32-bit hex color): Background fill color.
*   **Syntax**:
    ```lisp
    (panel :name :main-panel :x 0 :y 0 :w width :h height :bg #x00d0d0d0
      (child-node-1)
      (child-node-2))
    ```

#### B. `button`
A clickable button displaying a text label and rendering classic 3D bevels (raised when idle, sunken when pressed).
*   **Properties**:
    *   `:name` (keyword): Unique identifier.
    *   `:x`, `:y`, `:w`, `:h` (integers): Geometry.
    *   `:text` (string): Text label inside the button.
    *   `:msg` (list): The message dispatched to the `update` function when clicked.
*   **Syntax**:
    ```lisp
    (button :name :btn-inc :text "Increment" :x 20 :y 60 :w 120 :h 30 :msg '(:increment))
    ```

#### C. `label`
A static text element for headings, read-only data, or state readouts.
*   **Properties**:
    *   `:name` (keyword): Unique identifier.
    *   `:x`, `:y` (integers): Text base alignment coordinates.
    *   `:text` (string): Display text.
*   **Syntax**:
    ```lisp
    (label :name :count-lbl :text (format nil "Clicks: ~a" (state-clicks state)) :x 20 :y 20)
    ```

#### D. `checkbox`
A toggleable boolean input displaying a 3D inset box next to a text label. When active, draws a checkmark "X".
*   **Properties**:
    *   `:name` (keyword): Unique identifier.
    *   `:x`, `:y`, `:w`, `:h` (integers): Bounding geometry.
    *   `:label` (string): Accompanying text label.
    *   `:checked-p` (boolean): Whether to draw checked.
    *   `:msg` (list): Action message sent when toggled.
*   **Syntax**:
    ```lisp
    (checkbox :name :chk-active :label "Enable Action" :x 20 :y 160 :w 150 :h 24 :checked-p (state-active-p state) :msg '(:toggle-active))
    ```

#### E. `text-input`
A focusable text input field that parses keyboard characters, renders a blinking vertical cursor, and handles edit keys.
*   **Properties**:
    *   `:name` (keyword): Unique identifier.
    *   `:x`, `:y`, `:w`, `:h` (integers): Bounding box.
    *   `:text` (string): Current text content.
    *   `:cursor-pos` (integer): Cursor character index.
    *   `:focused-p` (boolean): Whether to draw focus cursor.
    *   `:msg-change` (list structure): Sent on every keystroke (e.g. `(:text-change "new-text")`).
*   **Syntax**:
    ```lisp
    (text-input :name :input-field :x 20 :y 110 :w 260 :h 30 :text (state-buffer state) :cursor-pos (state-cursor state) :focused-p (eq :input-field *focused-widget*))
    ```

---

## 3. Spatial Algorithms Specifications

### A. Mouse Event Hit-Testing (Bounding Boxes)
When a mouse button press or motion event arrives, we traverse the virtual layout tree:
```lisp
(defun find-widget-at (layout mx my)
  "Recursively search the layout list for the leaf widget enclosing the mouse coordinates (mx, my)."
  ...)
```
This returns the matching `widget` structure, allowing the dispatch loop to trigger its hover or press state.

### B. Keyboard Focus Graph (Cone Proximity)
To move focus using Arrow Keys (`Up/Down/Left/Right`), we calculate the spatial target:
```lisp
(defun find-nearest-widget (layout current-widget direction)
  "Search the layout for the closest focusable widget whose center point lies within a 90-degree cone originating from the current-widget in the specified direction (:up, :down, :left, :right)."
  ...)
```
1.  **Direction Vector**: Determine unit vector corresponding to direction (e.g. `:right` -> `(1, 0)`).
2.  **Cone Filtering**: For all other widgets, check if the vector from `current-widget` to `target-widget` forms an angle of $\le 45^\circ$ with the direction vector.
3.  **Euclidean Distance**: Select the candidate widget that satisfies the cone filter and has the minimum Euclidean distance.
