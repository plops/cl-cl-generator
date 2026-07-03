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

## 2. Window-per-Widget vs. Windowless Widgets

For an Athena-style GUI, we choose a **Window-per-Widget** design (similar to the X Toolkit Intrinsics / Xt):
*   Every Button, Checkbox, and Text Field is created as a **child subwindow** of the main window.
*   **Why this is fast and robust**:
    *   **Clipping**: The X server automatically clips text and lines to the widget's boundary. No client-side clipping math is needed.
    *   **Automatic Redraws**: When a subwindow is uncovered, the X server sends an `Expose` event specifically for that widget's window ID.
    *   **Event Routing**: The X server handles event routing (e.g., clicking on a button sends a `ButtonPress` with the button's subwindow ID). The client doesn't need to perform manual coordinate hit-testing.
    *   **Bandwidth Efficiency**: We only request events we care about on a per-widget basis. For example, text fields listen for `KeyPress`, buttons listen for `ButtonPress` and `Enter/LeaveWindow`, while static labels listen for nothing but `Expose`.

---

## 3. Bulletproof Widget State Machines

To make input widgets robust under high latency and quick mouse movements:

### A. Button State Machine
*   **States**:
    *   `Idle`: Normal raised bevel.
    *   `Hover`: Mouse is over. (Optional: draw highlighted background).
    *   `Pressed`: Mouse button 1 is down inside the button window. Sunken bevel.
    *   `Pressed-Outside`: Mouse button 1 is down, but the user dragged the cursor outside the button. Raised bevel.
*   **Transitions**:
    *   `EnterNotify` (while mouse button is up): `Idle` -> `Hover`
    *   `LeaveNotify` (while mouse button is up): `Hover` -> `Idle`
    *   `ButtonPress` (while in `Hover`): `Hover` -> `Pressed`. (Draw sunken bevel).
    *   `LeaveNotify` (while in `Pressed`): `Pressed` -> `Pressed-Outside`. (Draw raised bevel, do not trigger action).
    *   `EnterNotify` (while in `Pressed-Outside`): `Pressed-Outside` -> `Pressed`. (Draw sunken bevel).
    *   `ButtonRelease`:
        *   If in `Pressed`: Trigger `on-click` callback, go to `Hover`.
        *   If in `Pressed-Outside`: Go to `Idle` (cancel action).

### B. Checkbox State Machine
*   Inherits the button state machine for clicking.
*   Maintains a boolean state `checked-p`.
*   Draws a 3D inset box. When `checked-p` is true, draws an "X" or a filled inner box using `PolyFillRectangle`.

### C. Text Input Field State Machine
*   **States**:
    *   `Unfocused`: Static text. Cursor is hidden.
    *   `Focused`: Cursor is visible and blinking. Keyboard input is active.
*   **Transitions**:
    *   `ButtonPress` inside the text field: Client sends `SetInputFocus` to the subwindow.
    *   `FocusIn` (sent by server): Transition to `Focused`, draw cursor.
    *   `FocusOut` (sent by server): Transition to `Unfocused`, hide cursor.
*   **Keyboard Handling (Focused State)**:
    *   The client maps KeyCodes to KeySyms once at startup via `GetKeyboardMapping`.
    *   `KeyPress` events contain the `state` bitmask (tracking `Shift`, `Control`, `Caps Lock`).
    *   *Printable Characters*: Insert at cursor index, advance cursor, trigger redraw.
    *   *Backspace*: Delete char before cursor, decrement cursor index, redraw.
    *   *Left / Right Arrows*: Move cursor index locally without network roundtrips.
    *   *Return*: Trigger `on-submit` callback.
