# Implementation Plan 03: Code Quality, Keycode Expansion, UI State & Performance Optimizations

**Target Area:** Pure X11 GUI Toolkit (`example/07_pure_x11`)  
**Date:** 2026-07-22  
**Source Review:** [code_review.md](file:///workspace/src/cl-cl-generator/example/07_pure_x11/plan/20260722_01_review/code_review.md)  
**Corpus/Wiki:** `plops/cl-cl-generator` (DeepWiki MCP)

---

## 1. Overview & Objectives

This implementation plan covers **code quality, feature completeness, performance optimizations, and state cleanups**:

1. **Keycode Translation Expansion:** Support additional navigation and control keys (Tab, Escape, Delete, Home, End, PageUp, PageDown, F1–F12).
2. **Lisp Metaprogramming & Code Quality Cleanups:** Remove runtime `defparameter` side-effects, optimize layout type checking, replace hardcoded math constants with `pi`, and optimize orbit demo frame allocations.
3. **Double-Buffered Partial Redraw & UI State Encapsulation:** Eliminate partial redraw flicker using offscreen pixmap buffering and clean up global UI state special variables.

---

## 2. Context & Required Files

Autonomous AI agents executing this plan must load and inspect the following files:

### Primary Source Files
| File | Description & Key Line Ranges |
|:---|:---|
| [`03_widgets_core.lisp`](file:///workspace/src/cl-cl-generator/example/07_pure_x11/03_widgets_core.lisp) | Core widget logic & layout engine. Inspect string comparison in layout solver (L45–L56) and `translate-keycode` (L141–L160). |
| [`05_event_loop.lisp`](file:///workspace/src/cl-cl-generator/example/07_pure_x11/05_event_loop.lisp) | Event loop & Redraw strategies. Inspect `partial-redraw` (L49–L60) and global UI variables (`*focused-widget*`, `*pressed-widget*`, `*hovered-widget*`). |
| [`08_orbit_demo_template.lisp`](file:///workspace/src/cl-cl-generator/example/07_pure_x11/08_orbit_demo_template.lisp) | Orbit demo app. Inspect hardcoded `3.14159` math constants and tick frame allocation (L36, L51, L61–L63, L92). |
| [`generate.lisp`](file:///workspace/src/cl-cl-generator/example/07_pure_x11/generate.lisp) | Orchestrator. Inspect runtime `defparameter` calls inside `parse-initial-reply` (L328–L329, L357–L358). |

### Architectural Context (DeepWiki MCP)
Query the `deepwiki` MCP tool for corpus `plops/cl-cl-generator` using `ask_question`:
```
Server: deepwiki
Tool: ask_question
Query: "How does cl-cl-generator code generation handle macro templates and symbol equality in example/07_pure_x11?"
```

---

## 3. Step-by-Step Task Breakdown

### Task 3.1: Expand Keycode Translation (`translate-keycode`)

- **Problem:** [`03_widgets_core.lisp`](file:///workspace/src/cl-cl-generator/example/07_pure_x11/03_widgets_core.lisp#L141-L160) currently translates basic ASCII 32–126, Backspace, Return, and 4 Arrow keys. Useful UI keys such as Tab, Escape, Delete, Home, End, PageUp, PageDown, and Function keys return `nil` or raw keysyms.
- **Solution:**
  1. Inspect X11 keysym mappings for keycodes in `03_widgets_core.lisp`.
  2. Add keysym mappings for:
     - Tab (`#xff09` -> `:tab`)
     - Escape (`#xff1b` -> `:escape`)
     - Delete (`#xffff` -> `:delete`)
     - Home (`#xff50` -> `:home`)
     - End (`#xff57` -> `:end`)
     - PageUp (`#xff55` -> `:page-up`)
     - PageDown (`#xff56` -> `:page-down`)
     - Function keys F1–F12 (`#xffbe` through `#xffc9` -> `:f1` through `:f12`).
  3. Ensure `run-gui` key handler can process these keywords (e.g. Tab for focus navigation).
- **Verification:** Run test suite in `07_tests_template.lisp` and add unit tests verifying keycode translation for new keys.

### Task 3.2: Code Quality & Metaprogramming Cleanups

- **Problem:**
  1. `generate.lisp` (L328–L329, L357–L358) executes `defparameter` inside `parse-initial-reply` function body, creating runtime re-definitions.
  2. `03_widgets_core.lisp` (L45–L56) performs repeated `(string= type-name "HBOX")` string allocations during layout resolution.
  3. `08_orbit_demo_template.lisp` (L36, L51, L92) uses hardcoded `3.14159` instead of standard `pi`.
  4. `08_orbit_demo_template.lisp` (L61–L63) allocates new list structures on every tick frame inside the animation loop.
- **Solution:**
  1. Move `defparameter` declarations to top-level in `generate.lisp` and use `setf` inside `parse-initial-reply`.
  2. Change layout container type comparisons in `03_widgets_core.lisp` to `eq` on canonical symbols (e.g. `:hbox`, `:vbox`, `:panel`).
  3. Replace `3.14159` with standard Lisp `pi` in `08_orbit_demo_template.lisp`.
  4. Preallocate or reuse trace point buffer array/list in `08_orbit_demo_template.lisp` to reduce GC pressure at 20+ FPS.
- **Verification:** Generate codebase and verify clean execution of orbit demo and tests.

### Task 3.3: Double-Buffered Partial Redraw & UI State Encapsulation

- **Problem:**
  1. `partial-redraw` in `05_event_loop.lisp` (L49–L60) calls `clear-area` and `render-widget` directly on the main window without an offscreen buffer, creating flicker during rapid input or hover events.
  2. UI interaction state (`*focused-widget*`, `*pressed-widget*`, `*hovered-widget*`) relies on global special variables.
- **Solution:**
  1. Update `partial-redraw` to use offscreen pixmap double-buffering for the widget bounding rectangle, or perform clip-rect pixmap copy.
  2. Refactor UI interaction state into a structured binding or local state object managed inside `run-gui`.
- **Verification:** Run demo app, trigger hover and text input actions, and check for flicker-free visual output.

---

## 4. Code Generation & Verification Workflow

After editing any template file (`01_` through `08_`):

```bash
cd /workspace/src/cl-cl-generator/example/07_pure_x11
sbcl --load generate.lisp
```

Run test suite:
```bash
sbcl --load source/tests.lisp
```
And headless tests:
```bash
./run-xvfb-test.sh
```

---

## 5. Commit Standards

All commits must follow **Conventional Commits** specification:

Format:
```
<type>(07_pure_x11): <short description>

<detailed description of changes>
```

Types: `feat`, `fix`, `refactor`, `perf`, `test`.

Example Commit Message:
```
refactor(07_pure_x11): expand keycode translation, optimize layout symbols & fix defparameter side-effects

Expand translate-keycode in 03_widgets_core.lisp to support Tab, Escape, Delete, Home, End, PageUp, PageDown, and F1-F12 keys.

Clean up runtime defparameter calls inside parse-initial-reply in generate.lisp by declaring special variables at top-level and using setf. Replace string= layout comparisons with symbol eq, replace hardcoded 3.14159 with pi in orbit demo, and optimize frame trace point allocations.

Add double-buffered partial redraw in 05_event_loop.lisp to eliminate visual flicker.

Verified with sbcl --load generate.lisp and ./run-xvfb-test.sh.
```

---

## 6. Post-Implementation Walkthrough Requirement

Upon completion of this plan, the implementing agent **MUST** write a detailed walkthrough report saved to:
`/workspace/src/cl-cl-generator/example/07_pure_x11/plan/20260722_01_review/03_walkthrough.md`

The walkthrough file **MUST** contain:
1. **Summary of Changes:** Features, optimizations, and keycode mappings added.
2. **Key Design Decisions:** Rationale for symbol equality, state encapsulation, and pixmap clipping.
3. **Verification & Test Results:** Benchmark/test results and terminal log output.
4. **Issues & Iterations:** Problems encountered during implementation and how they were resolved.
