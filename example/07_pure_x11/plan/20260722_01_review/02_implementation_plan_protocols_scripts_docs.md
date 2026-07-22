# Implementation Plan 02: ICCCM Window Closing, Portable Scripts & Documentation Alignment

**Target Area:** Pure X11 GUI Toolkit (`example/07_pure_x11`)  
**Date:** 2026-07-22  
**Source Review:** [code_review.md](file:///workspace/src/cl-cl-generator/example/07_pure_x11/plan/20260722_01_review/code_review.md)  
**Corpus/Wiki:** `plops/cl-cl-generator` (DeepWiki MCP)

---

## 1. Overview & Objectives

This implementation plan focuses on **protocol standards compliance, shell script portability, and documentation accuracy**:

1. **ICCCM `WM_DELETE_WINDOW` Protocol Support:** Implement graceful window closing when the user closes the window via the Window Manager close button (X button), preventing socket crash errors.
2. **Portable Shell Scripts & Environment Cleanup:** Remove hardcoded paths, fix duplicate file loading, and add signal traps for headless Xvfb test runners.
3. **Documentation Alignment:** Synchronize `README.md` claims with actual implementation reality (correcting Quadtree / Delaunay claims and script/file names).

---

## 2. Context & Required Files

Autonomous AI agents executing this plan must load and inspect the following files:

### Primary Source Files
| File | Description & Key Line Ranges |
|:---|:---|
| [`01_package.lisp`](file:///workspace/src/cl-cl-generator/example/07_pure_x11/01_package.lisp) | Package & git version helper. Inspect line L25 (`/usr/bin/git` hardcoded path). |
| [`02_x11_spec.lisp`](file:///workspace/src/cl-cl-generator/example/07_pure_x11/02_x11_spec.lisp) | Protocol spec. Check `intern-atom` and `change-property` request definitions and `*x11-events*` (L500–L650). |
| [`05_event_loop.lisp`](file:///workspace/src/cl-cl-generator/example/07_pure_x11/05_event_loop.lisp) | Event loop. Check event dispatcher and exit condition handling (L90–L244). |
| [`run-xvfb-test.sh`](file:///workspace/src/cl-cl-generator/example/07_pure_x11/run-xvfb-test.sh) | Headless test runner. Inspect hardcoded conversation-id paths and `kill -9` behavior. |
| [`run-example.sh`](file:///workspace/src/cl-cl-generator/example/07_pure_x11/run-example.sh) | Example runner script. Check double loading of `example.lisp`. |
| [`README.md`](file:///workspace/src/cl-cl-generator/example/07_pure_x11/README.md) | Project README. Inspect architecture claims and filename references. |

### Architectural Context (DeepWiki MCP)
Query the `deepwiki` MCP tool for corpus `plops/cl-cl-generator` using `ask_question`:
```
Server: deepwiki
Tool: ask_question
Query: "How does the Pure X11 example handle X11 protocol atoms, window properties, and event parsing?"
```

---

## 3. Step-by-Step Task Breakdown

### Task 2.1: Implement ICCCM `WM_DELETE_WINDOW` Protocol Support

- **Problem:** Currently, when a window manager sends `ClientMessage` (opcode 33) to request window closure, the application ignores it or crashes due to closed socket connections.
- **Solution:**
  1. Ensure `intern-atom` request function is available in `02_x11_spec.lisp` to query atom IDs for `"WM_PROTOCOLS"` and `"WM_DELETE_WINDOW"`.
  2. In window setup (in `02_x11_spec.lisp` or `05_event_loop.lisp`), call `change-property` on the created window to set `WM_PROTOCOLS` with `WM_DELETE_WINDOW`.
  3. In `02_x11_spec.lisp`, add a `ClientMessage` (event code 33) parser to `*x11-events*`.
  4. In `05_event_loop.lisp`, add a handler for event code 33: if the client message data matches `WM_DELETE_WINDOW`, break out of the event loop gracefully.
- **Verification:** Verify window close message terminates `run-gui` cleanly without throwing socket read errors.

### Task 2.2: Fix Shell Scripts & Git Executable Path

- **Problem:**
  - `01_package.lisp` hardcodes `(sb-ext:run-program "/usr/bin/git" ...)` which fails on systems where git is in `/usr/local/bin` or Nix/Guix paths.
  - `run-xvfb-test.sh` contains a hardcoded path `/root/.gemini/antigravity-cli/brain/328a165b-e621-47e6-bfb3-cf072764a3e3/scratch/` which fails outside specific agent containers.
  - `run-example.sh` loads `example.lisp` twice (via quickload/asd and `--load`).
- **Solution:**
  1. Update `01_package.lisp`: replace `"/usr/bin/git"` with `"git"` and set `:search t`.
  2. Update `run-xvfb-test.sh`:
     - Replace hardcoded brain directory path with a local `./tmp` or `TMPDIR` path.
     - Add `trap 'kill $XVFB_PID $WM_PID 2>/dev/null || true' EXIT INT TERM` for clean process termination on script exit or error.
  3. Update `run-example.sh`: simplify SBCL command flags to prevent loading `example.lisp` twice.
- **Verification:** Execute `./run-xvfb-test.sh` and `./run-example.sh` and ensure exit codes are 0 and no path errors occur.

### Task 2.3: Align Documentation (`README.md`) with Code Reality

- **Problem:** `README.md` states that hit-testing uses a 2D Quadtree and keyboard navigation uses Delaunay Triangulation. In reality, the codebase implements linear tree traversal (`find-widget-at`) and cone-filtered search (`find-nearest-widget`). It also references `gen.lisp` instead of `generate.lisp`.
- **Solution:**
  1. Update `README.md` section on Hit-Testing to accurately describe linear tree traversal (and state Quadtree indexing as a planned future optimization).
  2. Update `README.md` section on Keyboard Navigation to accurately describe the 45-degree cone search algorithm.
  3. Fix references to `gen.lisp` -> `generate.lisp`.
- **Verification:** Review `README.md` and check for any remaining misleading claims.

---

## 4. Code Generation & Verification Workflow

After making changes:

```bash
cd /workspace/src/cl-cl-generator/example/07_pure_x11
sbcl --load generate.lisp
```

Run test suite and headless test script:
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

Types: `feat`, `fix`, `docs`, `scripts`.

Example Commit Message:
```
feat(07_pure_x11): support ICCCM WM_DELETE_WINDOW graceful shutdown

Add ClientMessage event parsing and WM_PROTOCOLS property setup to allow window manager close requests to cleanly break out of the run-gui event loop.

Fix hardcoded git executable path in 01_package.lisp using PATH search, remove hardcoded brain scratch directory from run-xvfb-test.sh, add shell trap handler for Xvfb cleanup, and update README.md to accurately document hit-testing and keyboard navigation algorithms.

Verified with sbcl --load generate.lisp and ./run-xvfb-test.sh.
```

---

## 6. Post-Implementation Walkthrough Requirement

Upon completion of this plan, the implementing agent **MUST** write a detailed walkthrough report saved to:
`/workspace/src/cl-cl-generator/example/07_pure_x11/plan/20260722_01_review/02_walkthrough.md`

The walkthrough file **MUST** contain:
1. **Summary of Changes:** Features and script updates completed.
2. **Key Design Decisions:** Architectural decisions for ICCCM atom interning and script cleanup.
3. **Verification & Test Results:** Log output from test runs showing clean exit and script execution.
4. **Issues & Iterations:** Problems encountered during implementation and how they were resolved.
