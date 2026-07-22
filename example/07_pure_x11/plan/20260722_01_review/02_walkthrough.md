# Walkthrough 02: ICCCM Window Closing, Portable Scripts & Documentation Alignment

**Date:** 2026-07-22  
**Target Area:** Pure X11 GUI Toolkit (`example/07_pure_x11`)  
**Implementation Plan:** [02_implementation_plan_protocols_scripts_docs.md](file:///workspace/src/cl-cl-generator/example/07_pure_x11/plan/20260722_01_review/02_implementation_plan_protocols_scripts_docs.md)

---

## 1. Summary of Changes

### Task 2.1: ICCCM `WM_DELETE_WINDOW` Protocol Support
- **Protocol Specs (`02_x11_spec.lisp`):**
  - Added declarative request specification for `intern-atom` (opcode 16) to resolve string atom names to 32-bit atom IDs.
  - Added declarative request specification for `change-property` (opcode 18) to set window manager properties (`WM_PROTOCOLS`).
  - Added declarative event parser specification for `client-message` (opcode 33).
- **Package Exports (`generate.lisp`):**
  - Exported `#:intern-atom`, `#:change-property`, `#:parse-client-message`, `#:handle-client-message-event`, `#:*wm-protocols-atom*`, and `#:*wm-delete-window-atom*` in `run-generator`.
- **Event Loop & Window Setup (`05_event_loop.lisp`):**
  - Defined special variables `*wm-protocols-atom*` and `*wm-delete-window-atom*`.
  - In `run-gui`, automatically intern `"WM_PROTOCOLS"` and `"WM_DELETE_WINDOW"` atoms and call `change-property` on window creation to announce ICCCM window deletion support.
  - Implemented `handle-client-message-event` and dispatched event code 33 (`ClientMessage`) in `run-gui` loop to break out cleanly when receiving `WM_DELETE_WINDOW`.
- **Test Suite (`07_tests_template.lisp`):**
  - Added unit test `test-client-message-event` verifying binary event parsing for opcode 33 and `WM_DELETE_WINDOW` match logic.

### Task 2.2: Fix Shell Scripts & Executable Paths
- **Git Executable (`01_package.lisp`):**
  - Replaced hardcoded `"/usr/bin/git"` path with `"git"` and `:search t` in `sb-ext:run-program`.
- **Headless Test Scripts (`run-xvfb-test.sh`, `run-xvfb-orbit-demo.sh`):**
  - Replaced hardcoded container scratch directory paths with local `$TMP_DIR` / `$ARTIFACT_DIR` fallbacks.
  - Added signal traps (`trap 'kill $CLIENT_PID $XVFB_PID 2>/dev/null || true' EXIT INT TERM`) for clean background process termination.
- **Example Scripts (`run-example.sh`, `run-orbit-demo.sh`):**
  - Removed duplicate `--load` flags (since `ql:quickload :pure-x11-gen` automatically loads `example.lisp` and `orbit-demo.lisp` via system ASD).

### Task 2.3: Align Documentation (`README.md`)
- Corrected generator file reference from `gen.lisp` to `generate.lisp`.
- Clarified hit-testing algorithm (`find-widget-at`): accurately documented as linear tree traversal of bounding boxes (noting Quadtree as a planned optimization).
- Clarified spatial keyboard navigation (`find-nearest-widget`): documented as 45-degree directional cone search.
- Updated API Reference in `README.md` to document `intern-atom`, `change-property`, `parse-client-message`, and `handle-client-message-event`.

---

## 2. Key Design Decisions

1. **ICCCM Atom Allocation:**
   - Atoms are interned dynamically via `intern-atom` during `run-gui` startup rather than hardcoding static IDs, maintaining compatibility across different X server instances.
2. **Resource ID Allocation:**
   - Updated `make-window` bindings to use `(next-resource-id)` instead of hardcoded 1..6 offsets, preventing resource ID collisions when creating custom GCs in applications.
3. **Double-Colon Package Splicing in Generator Templates:**
   - Unit tests in `07_tests_template.lisp` use `pure-x11-gen::parse-client-message` double-colon qualifications because template forms are evaluated at generator read time before `package.lisp` is written to disk.

---

## 3. Verification & Test Results

### Unit Test Suite Execution
Command:
```bash
sbcl --eval '(push "/workspace/src/cl-cl-generator/example/07_pure_x11/source/" asdf:*central-registry*)' \
     --eval '(ql:quickload :pure-x11-gen)' \
     --eval '(pure-x11-gen/tests:run-all-tests)' \
     --eval '(quit)'
```

Output:
```text
--- Running test-parse-node ---
PASS: Widget type is PANEL
PASS: Widget name is :main-panel
PASS: Widget x is 10
...
--- Running test-client-message-event ---
PASS: ClientMessage parsed type 42
PASS: ClientMessage parsed data0 99
PASS: ClientMessage with WM_DELETE_WINDOW returned :close
ALL TESTS PASSED!
```

### Xvfb Headless GUI Test Runs
1. **Example GUI Client:**
```bash
./run-xvfb-test.sh
```
Output:
```text
Starting Pure X11 Example Client via SBCL...
Connecting to X server...
Creating window...
Window created with ID: 2097153
Mapping window...
Entering event loop. Press Ctrl+C to exit.
Screenshot captured and saved.
```

2. **Orbit Demo Animation:**
```bash
./run-xvfb-orbit-demo.sh
```
Output:
```text
Starting Pure X11 Orbit Demo via SBCL...
Connecting to X server...
Creating window...
Window created with ID: 2097153
Mapping window...
Entering event loop. Press Ctrl+C to exit.
Orbit screenshot captured and saved.
```

---

## 4. Issues & Iterations

1. **`CreateGC` Value-Mask & Alignment:**
   - *Issue:* Initial `create-gc` calls contained `#x1000c` with a 7th word for font ID 0, causing `BadIDChoice` or `BadGC` protocol errors on servers without font ID 0.
   - *Resolution:* Fixed `create-gc` value mask to `#x0000c` (foreground + background, length 6 words).
2. **Double Colon vs Single Colon in Generator Templates:**
   - *Issue:* SBCL reader failed with `Symbol "PARSE-CLIENT-MESSAGE" not found in package PURE-X11-GEN` when loading `07_tests_template.lisp`.
   - *Resolution:* Switched to `pure-x11-gen::parse-client-message` package-qualified symbol in the template file.
3. **Environment Package Installation:**
   - Installed `xvfb`, `xdotool`, and `imagemagick` to enable automated GUI screenshot capturing and headless testing in the container.
