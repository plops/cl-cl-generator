# Implementation Plan 01: Critical Bug Fixes & Event Loop Refactoring

**Target Area:** Pure X11 GUI Toolkit (`example/07_pure_x11`)  
**Date:** 2026-07-22  
**Source Review:** [code_review.md](file:///workspace/src/cl-cl-generator/example/07_pure_x11/plan/20260722_01_review/code_review.md)  
**Corpus/Wiki:** `plops/cl-cl-generator` (DeepWiki MCP)

---

## 1. Overview & Objectives

This implementation plan addresses the **highest priority critical issues** identified in the code review. These issues affect resource stability, protocol reliability, and codebase maintainability:

1. **`put-image-big-req` Buffering Bypass:** Prevent out-of-order socket writes when sending large image buffers.
2. **Canvas Pixmap Resource Management & Optimization:** Ensure offscreen pixmaps are freed on error via `unwind-protect` and optimize canvas rendering.
3. **Event Loop (`run-gui`) Modularization:** Refactor the 15-level deeply nested `cond` event dispatch block into modular, single-responsibility handler functions.

---

## 2. Context & Required Files

Autonomous AI agents executing this plan must load and inspect the following source and documentation files:

### Primary Source Files
| File | Description & Key Line Ranges |
|:---|:---|
| [`02_x11_spec.lisp`](file:///workspace/src/cl-cl-generator/example/07_pure_x11/02_x11_spec.lisp) | X11 protocol specification. Inspect `put-image-big-req` at lines L428–L457. |
| [`04_widgets_builtin.lisp`](file:///workspace/src/cl-cl-generator/example/07_pure_x11/04_widgets_builtin.lisp) | Builtin widget renderers. Inspect Canvas rendering pixmap creation/free at lines L120–L235. |
| [`05_event_loop.lisp`](file:///workspace/src/cl-cl-generator/example/07_pure_x11/05_event_loop.lisp) | MUV Event Loop & Redraw logic. Inspect `run-gui` event dispatch loop at lines L90–L244. |
| [`generate.lisp`](file:///workspace/src/cl-cl-generator/example/07_pure_x11/generate.lisp) | Code generator orchestrator. Inspect buffering macro definitions `with-buffered-output` and socket packet flushing logic (L135–L217). |
| [`07_tests_template.lisp`](file:///workspace/src/cl-cl-generator/example/07_pure_x11/07_tests_template.lisp) | Test suite template. Use to verify widget and event handling logic non-regressions. |

### Architectural Context (DeepWiki MCP)
Before writing code, query the `deepwiki` MCP tool for corpus `plops/cl-cl-generator` using `ask_question`:
```
Server: deepwiki
Tool: ask_question
Query: "Explain the socket buffering mechanism (with-buffered-output, *packet-buffer*) and how protocol requests are packed and flushed in example/07_pure_x11."
```
```
Server: deepwiki
Tool: ask_question
Query: "How does the MUV event loop and dirty-tracking work in example/07_pure_x11?"
```

---

## 3. Step-by-Step Task Breakdown

### Task 1.1: Fix `put-image-big-req` Socket Buffering Bypass

- **Problem:** [`02_x11_spec.lisp`](file:///workspace/src/cl-cl-generator/example/07_pure_x11/02_x11_spec.lisp#L429-L456) defines `:post` for `put-image-big-req` using direct socket writes (`write-sequence img1 *s*`). If `put-image-big-req` is invoked inside a `with-buffered-output` block, pending byte requests in `*packet-buffer*` are written *after* the raw image data, causing protocol corruptions and out-of-order execution.
- **Solution:**
  1. Inspect `*packet-buffer*` and buffer flushing routines in `generate.lisp` and `02_x11_spec.lisp`.
  2. Modify `:post` of `put-image-big-req` in `02_x11_spec.lisp` so that any pending output in `*packet-buffer*` is explicitly flushed to socket `*s*` before `(write-sequence img1 *s*)` is executed.
  3. Ensure padding bytes and `force-output` happen predictably.
- **Verification:** Run `sbcl --load generate.lisp` and verify generated `source/x11-core.lisp` includes the buffer flush in `put-image-big-req`.

### Task 1.2: Canvas Pixmap Resource Management & Exception Safety

- **Problem:** In [`04_widgets_builtin.lisp`](file:///workspace/src/cl-cl-generator/example/07_pure_x11/04_widgets_builtin.lisp#L126-L234), `create-pixmap` allocates an offscreen X11 pixmap, but `free-pixmap` is called at the end without `unwind-protect`. Any error during canvas shape drawing leaves leaked pixmaps on the X server.
- **Solution:**
  1. Wrap the rendering logic and `copy-area` call within `(unwind-protect (progn ...) (free-pixmap pix))` in `04_widgets_builtin.lisp`.
  2. Optimize pixmap allocation: check if pixmap allocation can be reused or cleanly destroyed across drawing calls.
- **Verification:** Verify that if shape rendering throws an condition or exits early, `free-pixmap` is guaranteed to be executed.

### Task 1.3: Refactor Event Loop (`run-gui`) into Modular Handlers

- **Problem:** [`05_event_loop.lisp`](file:///workspace/src/cl-cl-generator/example/07_pure_x11/05_event_loop.lisp#L125-L241) contains a 15-level deeply nested `cond` statement handling X11 event codes (Expose, ConfigureNotify, MotionNotify, ButtonPress, ButtonRelease, KeyPress) inside a single giant loop.
- **Solution:**
  1. Extract event code logic into dedicated helper functions:
     - `handle-expose-event (layout)`
     - `handle-configure-event (reply layout win-width win-height rebuild-layout-fn)`
     - `handle-motion-event (reply layout)`
     - `handle-button-press-event (reply layout)`
     - `handle-button-release-event (reply layout state update-fn rebuild-layout-fn)`
     - `handle-key-press-event (reply layout state keyboard-map update-fn rebuild-layout-fn)`
  2. Unify duplicate Button and Checkbox release logic (currently separate `cond` branches with identical `(setf state (funcall update-fn state msg))` code).
  3. Simplify `run-gui` event dispatch loop so it delegates to these handler functions.
- **Verification:** Test all interactive widgets (Button, Checkbox, Text Input, Canvas) in the demo app and test suite.

---

## 4. Code Generation & Verification Workflow

After editing any template file (`01_` through `08_`), always execute the generator:

```bash
cd /workspace/src/cl-cl-generator/example/07_pure_x11
sbcl --load generate.lisp
```

### Running Test Suite
Execute the generated tests to ensure no regressions:
```bash
sbcl --load source/tests.lisp
```
Or execute via the test script:
```bash
./run-xvfb-test.sh
```

---

## 5. Commit Standards

All commits must follow **Conventional Commits** specification:

Format:
```
<type>(07_pure_x11): <short description>

<detailed multi-paragraph body explaining what changed, why it changed, and how it was verified>
```

Types: `fix`, `refactor`, `feat`, `test`, `docs`.

Example Commit Message:
```
fix(07_pure_x11): flush packet buffer before put-image-big-req sequence

Ensure that put-image-big-req flushes *packet-buffer* to socket *s* before writing raw image byte sequences. Previously, raw image bytes were written directly to the socket while earlier requests remained buffered in *packet-buffer*, resulting in out-of-order protocol execution when using with-buffered-output.

Also wrapped canvas double-buffering pixmap cleanup in unwind-protect inside 04_widgets_builtin.lisp to prevent X server pixmap resource leaks when rendering conditions occur.

Verified with sbcl --load generate.lisp and ./run-xvfb-test.sh.
```

---

## 6. Post-Implementation Walkthrough Requirement

Upon completion of this plan, the implementing agent **MUST** write a detailed walkthrough report saved to:
`/workspace/src/cl-cl-generator/example/07_pure_x11/plan/20260722_01_review/01_walkthrough.md`

The walkthrough file **MUST** contain:
1. **Summary of Changes:** What was implemented vs planned.
2. **Key Design Decisions:** Rationale for architectural choices.
3. **Verification & Test Results:** Terminal outputs/status of running `sbcl --load generate.lisp` and `./run-xvfb-test.sh`.
4. **Issues & Iterations:** Any unexpected bugs encountered during implementation and how they were resolved.
