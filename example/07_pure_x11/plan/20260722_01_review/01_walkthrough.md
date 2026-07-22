# Walkthrough - Implementation Plan 01: Critical Bug Fixes & Event Loop Refactoring

**Target Area:** Pure X11 GUI Toolkit (`example/07_pure_x11`)  
**Date:** 2026-07-22  
**Status:** Completed  
**Plan Reference:** [01_implementation_plan_critical_fixes.md](file:///workspace/src/cl-cl-generator/example/07_pure_x11/plan/20260722_01_review/01_implementation_plan_critical_fixes.md)

---

## 1. Summary of Changes

All planned critical bug fixes and refactoring items were successfully implemented and verified:

| Task | Plan Item | Status | Key Changes & Target Files |
|:---|:---|:---|:---|
| **1.1** | Fix `put-image-big-req` Socket Buffering Bypass | **Completed** | Modified `:post` of `put-image-big-req` in [`02_x11_spec.lisp`](file:///workspace/src/cl-cl-generator/example/07_pure_x11/02_x11_spec.lisp#L447-L451) to execute `(flush-packets)` prior to `(write-sequence img1 *s*)`. |
| **1.2** | Canvas Pixmap Resource Management & Exception Safety | **Completed** | Wrapped canvas double-buffering render & copy logic in `unwind-protect` in [`04_widgets_builtin.lisp`](file:///workspace/src/cl-cl-generator/example/07_pure_x11/04_widgets_builtin.lisp#L127-L236) and full window double-buffering in [`05_event_loop.lisp`](file:///workspace/src/cl-cl-generator/example/07_pure_x11/05_event_loop.lisp#L45-L50) to guarantee `free-pixmap` cleanup. |
| **1.3** | Refactor Event Loop (`run-gui`) into Modular Handlers | **Completed** | Extracted the 15-level nested `cond` event dispatch in [`05_event_loop.lisp`](file:///workspace/src/cl-cl-generator/example/07_pure_x11/05_event_loop.lisp#L84-L217) into 6 dedicated modular functions (`handle-expose-event`, `handle-configure-event`, `handle-motion-event`, `handle-button-press-event`, `handle-button-release-event`, `handle-key-press-event`). Unified duplicate button and checkbox release logic. Exported functions in [`generate.lisp`](file:///workspace/src/cl-cl-generator/example/07_pure_x11/generate.lisp#L69-L75). Added unit tests in [`07_tests_template.lisp`](file:///workspace/src/cl-cl-generator/example/07_pure_x11/07_tests_template.lisp#L140-L180). |

---

## 2. Key Design Decisions

1. **`flush-packets` before Big-Request Raw Byte Writes:**
   - In X11 socket communication, `with-buffered-output` accumulates byte vectors in `*packet-buffer*`.
   - `put-image-big-req` packs its header via `with-packet` (which pushes to `*packet-buffer*` when buffering) and then writes raw pixel bytes directly to socket stream `*s*`.
   - Calling `(flush-packets)` inside `:post` ensures all prior queued request packets and the big request header itself are flushed to socket stream `*s*` *before* raw image payload bytes are written.

2. **`unwind-protect` for Server-Side Pixmap Reclamation:**
   - X11 server pixmap resources (`create-pixmap`) allocate server-side memory.
   - If rendering or `copy-area` signals a Common Lisp condition or exits via non-local control transfer, leaked pixmaps accumulate on the X server.
   - Wrapping render execution and `copy-area` inside `(unwind-protect (progn ...) (free-pixmap pix))` guarantees cleanup under all execution paths.

3. **Modular Event Handlers & State Flow:**
   - Decoupled `run-gui` event handling into pure/single-responsibility functions:
     - `handle-expose-event (layout)`
     - `handle-configure-event (reply layout rebuild-layout-fn)`
     - `handle-motion-event (reply layout)`
     - `handle-button-press-event (reply layout)`
     - `handle-button-release-event (reply layout state update-fn rebuild-layout-fn)` -> returns updated state
     - `handle-key-press-event (reply layout state keyboard-map update-fn rebuild-layout-fn)` -> returns updated state
   - Unified `BUTTON` and `CHECKBOX` release dispatch under `(member type-name '("BUTTON" "CHECKBOX") :test #'string-equal)` to remove duplicate code paths.

---

## 3. Verification & Test Results

### Code Generation (`generate.lisp`)
```
$ sbcl --load generate.lisp --eval '(quit)'
This is SBCL 2.6.0.debian...
To load "cl-cl-generator":
  Load 1 ASDF system:
    cl-cl-generator
; Loading "cl-cl-generator"

Successfully generated X11 example client codebase in /workspace/src/cl-cl-generator/example/07_pure_x11/source/
```

### Unit Test Suite Execution
```
$ sbcl --eval '(push #p"/workspace/src/cl-cl-generator/example/07_pure_x11/source/" asdf:*central-registry*)' --eval '(ql:quickload :pure-x11-gen)' --eval '(pure-x11-gen/tests:run-all-tests)' --eval '(quit)'
To load "pure-x11-gen":
  Load 1 ASDF system:
    pure-x11-gen
; Loading "pure-x11-gen"
[package pure-x11-gen]............................
[package pure-x11-gen/example]....................
[package pure-x11-gen/orbit-demo].................
[package pure-x11-gen/tests]..
--- Running test-parse-node ---
PASS: Widget type is PANEL
PASS: Widget name is :main-panel
PASS: Widget x is 10
PASS: Widget y is 20
PASS: Widget w is 100
PASS: Widget h is 200
PASS: Children parsed correctly
--- Running test-collect-focusable ---
PASS: Found 3 focusable widgets
PASS: First is :b1
PASS: Second is :c1
PASS: Third is :t1
--- Running test-hit-testing ---
PASS: Hit button 1
PASS: Hit button 2
PASS: Hit panel background
PASS: No hit outside bounds
--- Running test-cone-focus-search ---
PASS: b1 -> right is b2
PASS: b1 -> down is b3
PASS: b2 -> left is b1
PASS: b3 -> up is b1
--- Running test-widget-registry ---
PASS: Mock widget renderer dispatched successfully
--- Running test-glue-solver ---
PASS: Stretched to 300: 100, 100, 100
PASS: Stretched to 600: 200, 200, 200
PASS: Proportional stretch 1:2: size is correct
PASS: Shrunk to 300: 150, 150
--- Running test-bevel-coordinates ---
PASS: Buffered 8 draw-line packets for bevel
--- Running test-dirty-widgets ---
PASS: :w1 is dirty (focus change)
PASS: :w2 is dirty (hover change)
PASS: Only 2 dirty widgets
PASS: prev-focused snapshot correct
PASS: No dirty widgets after save
--- Running test-x11-opcodes ---
PASS: poly-fill-rectangle major opcode is 70
PASS: imagetext8 major opcode is 76
PASS: poly-rectangle major opcode is 74
--- Running test-event-handlers ---
PASS: Motion event updates hovered widget to :b1
PASS: ButtonPress updates pressed widget to :b1
PASS: ButtonPress updates focused widget to :b1
PASS: ButtonRelease dispatched update-fn with widget :msg
PASS: ButtonRelease returned updated state
PASS: ButtonRelease cleared pressed widget
ALL TESTS PASSED!
```

---

## 4. Issues & Iterations

1. **Parenthesis Depth in S-expression Templates (`05_event_loop.lisp` and `04_widgets_builtin.lisp`):**
   - *Issue:* During initial refactoring of `05_event_loop.lisp` and `04_widgets_builtin.lisp`, additional `unwind-protect` and helper function forms altered the closing parenthesis count at the end of backquoted `toplevel` lists.
   - *Resolution:* Used the SBCL diagnostic reader loop technique (from `parenthesis-matching` skill) to read each form independently:
     ```lisp
     sbcl --eval '(with-open-file (s "05_event_loop.lisp") ...)'
     ```
     This pinpointed exact line positions of parenthesis mismatches, allowing precise adjustment of closing parentheses.

2. **Standalone Test Environment Bindings (`test-event-handlers`):**
   - *Issue:* Running event handler unit tests outside an active X server connection triggered unbound variable errors for `*window*`, graphics context dynamic variables (`*gc-face*`, `*gc-text*`), and resource ID counters (`*resource-id-base*`, `*resource-id-mask*`).
   - *Resolution:* Added top-level `defparameter` declarations for `*resource-id-base*`, `*resource-id-mask*`, and `*resource-id-counter*` in `generate.lisp` and bound mock values locally within `test-event-handlers` in `07_tests_template.lisp`.
