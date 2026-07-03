# Plan 02 — GUI Widgets Implementation Steps

This document outlines the concrete implementation steps to build the declarative, high-performance X11 widget toolkit.

---

## 1. Code Generator Updates (`gen.lisp`)

We will add the following X11 request definitions to `*x11-requests*` in `gen.lisp`:
1.  **`poly-rectangle` (Opcode 76)**: Draw rectangles outlines.
2.  **`poly-fill-rectangle` (Opcode 78)**: Draw filled rectangles for widget backgrounds.
3.  **`set-input-focus` (Opcode 42)**: Focus a window (or subwindow) to receive keypress events.

We will also update `gen.lisp` to write a new file `widgets.lisp`.

---

## 2. Widget Toolkit Design (`source/widgets.lisp`)

We will implement:
1.  **State Structures**:
    *   `state` record containing immutable global application state.
    *   `widget` structure tracking:
        *   `type`: `:panel`, `:button`, `:label`, `:checkbox`, `:text-input`.
        *   `name`: Keyword name.
        *   `x`, `y`, `w`, `h`: Absolute coordinates.
        *   `props`: Plist of properties (like `:text`, `:on-click`, `:default`, etc.).
2.  **Spatial Operations**:
    *   `find-widget-at (layout x y)`: Linear search matching bounding boxes.
    *   `find-nearest-widget (layout current-widget direction)`: Cone proximity search (find closest focusable widget within $\pm 45^\circ$ of direction).
3.  **Rendering Engine**:
    *   `render-widget (widget &key active-p pressed-p)`: Draws backgrounds via `poly-fill-rectangle`, 3D bevels via `poly-segment`, and text via `imagetext8` based on widget type and states.
4.  **The Elm Event Loop**:
    *   Main loop manages `*state*` and window dimensions `*width* *height*`.
    *   Maintains focus widget `*focused-widget-name*` and pressed widget `*pressed-widget-name*`.
    *   On `ConfigureNotify` (Resize): Re-evaluates layout, rebuilds focus graph, clears screen.
    *   On `Expose`: Re-renders current virtual layout.
    *   On Mouse/Key events: Modifies state via a pure `update` function and queues redraws.

---

## 3. Demo Application (`source/example.lisp`)

We will replace the simple example client in `example.lisp` with:
1.  A pure `render-ui (w h state)` layout function containing:
    *   A panel filling the window.
    *   A text label for a counter: `"Counter: <clicks>"`.
    *   An increment button and a decrement button.
    *   A toggle checkbox.
    *   A text input field.
2.  A pure `update (state msg)` function modifying the state.
3.  A main loop coordinating X11 connection, event reading, and dispatch.
