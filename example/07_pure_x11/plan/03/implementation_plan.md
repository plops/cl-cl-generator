# Implementation Plan — GUI Widgets & Systematic X11 Expansion

We will systematically expand our generated X11 library to support child subwindows, shape drawing, and event dispatching. We will then build a lightweight GUI toolkit in Lisp utilizing X11 subwindows (a "window-per-widget" design) and showcase it with an interactive demo (e.g. a click counter).

---

## Proposed Changes

We will group changes under the `pure-x11-gen` example generator.

### 1. Code Generator Additions (`gen.lisp`)

We will expand our declarative tables to support the necessary requests:

#### [MODIFY] [gen.lisp](file:///workspace/src/cl-cl-generator/example/07_pure_x11/gen.lisp)

*   **Add Rectangle Drawing Requests**:
    *   `poly-rectangle` (Opcode 76): Draws outlines of rectangles.
    *   `poly-fill-rectangle` (Opcode 78): Draws filled rectangles (ideal for widget backgrounds and button shapes).
*   **Generalize Window Creation**:
    *   Currently, `make-window` is hardcoded to create a top-level window. We will add a general `create-subwindow` request that allows specifying a parent window, coordinates relative to the parent, background color, and a specific event mask.
*   **Generate `widgets.lisp`**:
    *   Add widgets file generation to `gen.lisp` so that `widgets.lisp` is output as part of the library.

---

### 2. Widget Toolkit Design (`widgets.lisp`)

We will generate a new file `widgets.lisp` containing the GUI framework:

#### [NEW] [widgets.lisp](file:///workspace/src/cl-cl-generator/example/07_pure_x11/source/widgets.lisp)

*   **Widget Base Structure**:
    *   A structure/class tracking `id` (X11 subwindow ID), `parent` window, geometry (`x`, `y`, `width`, `height`), background color, and hooks:
        *   `on-draw`: Lambda called on Expose event to draw the widget.
        *   `on-click`: Lambda called on ButtonPress event.
*   **Widget Registry**:
    *   A global hash-table `*widgets*` mapping X11 window IDs to widget objects.
*   **Standard Widgets**:
    *   `make-button`: Helper creating a child window, registering it in `*widgets*`, and setting background and text drawing.
    *   `make-label`: Simple text label widget.
*   **Event Dispatcher**:
    *   `dispatch-event (reply-buffer)`: Receives an event from the main loop, extracts the window ID from the event, looks up the corresponding widget, and executes its draw/click handler.

---

### 3. Demo Client Expansion (`example.lisp`)

#### [MODIFY] [example.lisp](file:///workspace/src/cl-cl-generator/example/07_pure_x11/source/example.lisp)

We will modify the example to show a functional GUI:
*   Create a main window.
*   Create a text label widget showing: `"Clicks: 0"`.
*   Create a button widget labeled `"Click Me!"`.
*   Assign a click handler to the button that increments a counter, updates the label's text, clears the label subwindow, and redraws it.
*   Update the event loop to route incoming events to `dispatch-event`.

---

### 4. System ASDF Update

#### [MODIFY] [pure-x11-gen.asd](file:///workspace/src/cl-cl-generator/example/07_pure_x11/source/pure-x11-gen.asd)

Add `"widgets"` to the components list:
```lisp
       :components ((:file "package")
                    (:file "x11-core")
                    (:file "widgets"))
```

---

## Verification Plan

### Automated Verification
We will run `run-example.sh` to compile and load the updated system to ensure that:
1. The new widgets file is compiled successfully.
2. The interactive example executes cleanly.

### Manual Verification
1. Run `./run-example.sh` on the host to open the GUI.
2. Click the button and verify the counter increments.
3. Verify that resizing or covering/uncovering the window successfully triggers expose events and redraws the buttons and labels.
