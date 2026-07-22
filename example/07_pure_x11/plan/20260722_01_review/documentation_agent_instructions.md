# Instructions for Documentation Agent: Pure X11 GUI Toolkit

## Your Mission

You are an autonomous documentation agent. Your task is to produce comprehensive, high-quality developer documentation for the **Pure X11 GUI Toolkit** (`example/07_pure_x11`) in the `plops/cl-cl-generator` repository. The documentation targets a Common Lisp developer who wants to understand, extend, or debug this codebase.

---

## Step 0: Gather Context via DeepWiki MCP

Before reading any files, query DeepWiki to get architectural context. Use the `ask_question` tool on the `deepwiki` MCP server.

**Required DeepWiki queries** (repo: `plops/cl-cl-generator`):

1. `"Describe the architecture and design decisions of the Pure X11 GUI toolkit in example/07_pure_x11. How does the code generator produce the X11 client library?"`
2. `"How does cl-cl-generator's emit-cl and write-source work? What are DSL keywords like toplevel, comment, raw?"`
3. `"Explain the widget system and layout engine in the Pure X11 example. How does the TeX glue solver work?"`
4. `"How does the event loop and MUV (Model-Update-View) architecture work in the Pure X11 toolkit?"`

These queries will give you design rationale that is NOT in the source code itself.

---

## Step 1: File Inventory

All files are under `/workspace/src/cl-cl-generator/example/07_pure_x11/`. Read them in the order listed below. Each file has a short description so you can prioritize.

### Generator Templates (the "source of truth" — read these FIRST)

| # | File | Size | Purpose |
|---|------|------|---------|
| 1 | `01_package.lisp` | 1.5 KB | Package definition, Quicklisp setup, output directory, git version stamp, `make-header-comments` helper |
| 2 | `02_x11_spec.lisp` | 24 KB | **Core**: Declarative specs for 19 X11 requests (`*x11-requests*`), 6 event parsers (`*x11-events*`), flag/mask lookup tables, and code-emission functions (`emit-request-function`, `emit-event-parser`, `generate-lookup-function`) |
| 3 | `03_widgets_core.lisp` | 14 KB | Widget struct definition, `parse-node`, `resolve-layout` (recursive layout resolver), `compute-box-layout` (hbox/vbox), TeX `glue` struct + `solve-glue`, `find-widget-at` (hit testing), `find-nearest-widget` (keyboard navigation via cone search), `translate-keycode`, widget renderer registry |
| 4 | `04_widgets_builtin.lisp` | 12 KB | Built-in widget renderers: PANEL, HBOX, VBOX, LABEL, BUTTON, CHECKBOX, TEXT-INPUT, CANVAS (with world-coordinate transform, grid, axes, shapes, offscreen pixmap double-buffering) |
| 5 | `05_event_loop.lisp` | 15 KB | MUV event loop (`run-gui`), dirty tracking (`compute-dirty-widgets`), `full-redraw` (pixmap double-buffered), `partial-redraw`, `smart-redraw`, tick-based animation support |
| 6 | `06_example_template.lisp` | 3 KB | Demo app: `app-state` struct, `update` function, `view` function (returns virtual DOM), `run-x11-example` |
| 7 | `07_tests_template.lisp` | 9 KB | 9 test suites: parse-node, focusable collection, hit-testing, cone-focus, widget registry, glue solver, bevel coordinates, dirty widgets, X11 opcodes |
| 8 | `08_orbit_demo_template.lisp` | 4 KB | Hohmann transfer orbit animation using Canvas widget, custom GCs for planet colors, tick-driven animation |

### Orchestrator

| # | File | Size | Purpose |
|---|------|------|---------|
| 9 | `generate.lisp` | 27 KB | **Main entry point**: Loads all templates, emits generated code to `source/`. Contains the x11-core code inline (connection, auth, packet I/O macros via `raw` blocks, `parse-initial-reply`, `connect` function). Calls `write-source` and `emit-cl` for each output file. |

### Generated Output (read selectively for verification)

| # | File | Size | Purpose |
|---|------|------|---------|
| 10 | `source/package.lisp` | 1.7 KB | Generated package definition |
| 11 | `source/pure-x11-gen.asd` | 0.5 KB | Generated ASDF system definition |
| 12 | `source/x11-core.lisp` | 33 KB | Generated X11 protocol layer (largest generated file) |
| 13 | `source/widgets-core.lisp` | 13 KB | Generated widget system |
| 14 | `source/widgets-builtin.lisp` | 10 KB | Generated widget renderers |
| 15 | `source/event-loop.lisp` | 17 KB | Generated event loop |
| 16 | `source/example.lisp` | 3 KB | Generated demo app |
| 17 | `source/orbit-demo.lisp` | 4 KB | Generated orbit demo |
| 18 | `source/tests.lisp` | 8 KB | Generated tests |

### Support Files

| # | File | Size | Purpose |
|---|------|------|---------|
| 19 | `README.md` | 9 KB | Existing README with API reference and walkthrough (use as reference, but your docs will be more comprehensive) |
| 20 | `run-example.sh` | 0.8 KB | Shell script to launch the demo app |
| 21 | `run-orbit-demo.sh` | 0.8 KB | Shell script to launch the orbit demo |
| 22 | `run-xvfb-test.sh` | 0.9 KB | Headless test runner using Xvfb + xdotool |
| 23 | `run-xvfb-orbit-demo.sh` | 0.8 KB | Headless orbit demo runner |
| 24 | `screenshot.png` | 1.8 KB | Screenshot of the demo app |

### Context Files (read if needed for deeper understanding)

| # | File | Purpose |
|---|------|---------|
| 25 | `plan/05/implementation_plan.md` | Phase 5 implementation plan (Canvas + orbit demo) — shows design decisions |
| 26 | `plan/20260722_01_review/code_review.md` | Recent code review with detailed findings |

---

## Step 2: Documentation Output Structure

Write all documentation files to: `/workspace/src/cl-cl-generator/example/07_pure_x11/doc/`

Create the directory if it doesn't exist. Use the following numbered markdown files:

### 01_overview.md — Project Overview & Design Philosophy
**Relevant files to read:** `README.md`, DeepWiki query 1, `generate.lisp` (lines 1–14)
**Content:**
- What is this project? (Pure Lisp X11 client, no C dependencies)
- Design philosophy (RTT minimization, MUV architecture, TeX glue layout)
- Two-stage architecture: generator-time vs. runtime
- Comparison with traditional approaches (Xlib, XCB, CLX)
- Dependencies (SBCL, sb-bsd-sockets, cl-cl-generator)

### 02_code_generation.md — Code Generation Architecture
**Relevant files to read:** `01_package.lisp`, `generate.lisp`, DeepWiki query 2
**Content:**
- How `cl-cl-generator` works (`emit-cl`, `write-source`, `sxhash` dedup)
- DSL keywords: `toplevel`, `comment`, `comments`, `raw`
- Generator-time loops: `,@(loop for req in *x11-requests* ...)`
- The `raw` block workaround for nested quasiquoting in macros
- File numbering convention (`01_`–`08_`) and load order
- How to re-run the generator

### 03_x11_protocol.md — X11 Protocol Layer
**Relevant files to read:** `02_x11_spec.lisp`, `generate.lisp` (lines 112–541)
**Content:**
- X11 protocol basics (requests, replies, events, 4-byte alignment)
- Connection handshake (`connect`, `read-connection-response`, `parse-initial-reply`)
- XAuthority cookie authentication (`get-xauth-cookie`, `read-xauthority`)
- Packet I/O macros (`with-packet`, `with-reply`, `with-buffered-output`)
- Resource ID allocation (`next-resource-id`)
- Event queuing (`*pending-events*`, `read-reply-packet`)
- Declarative request specification format (`:name`, `:params`, `:bindings`, `:packet`, `:reply`, `:returns`, `:post`)
- Complete API reference table for all 19 requests
- Declarative event specification format
- Complete table for all 6 event parsers
- Flag/mask lookup tables (`*set-of-value-mask*`, `*set-of-event*`, `*set-of-key-button*`)
- BigRequests extension support

### 04_widget_system.md — Widget System & Layout Engine
**Relevant files to read:** `03_widgets_core.lisp`, `04_widgets_builtin.lisp`, DeepWiki query 3
**Content:**
- Widget struct fields (`type`, `name`, `x`, `y`, `w`, `h`, `props`, `children`)
- Virtual DOM concept: S-expression layout specification
- `parse-node`: How raw S-expressions become widget structs
- `resolve-layout`: Recursive coordinate resolution
- TeX glue system: `glue` struct (`natural`, `stretch`, `shrink`), `solve-glue` algorithm
- `compute-box-layout`: hbox/vbox layout with padding and spacing
- Widget renderer registry (`register-widget`, `render-widget`)
- Hit testing (`find-widget-at`)
- Keyboard navigation (`find-nearest-widget`, cone-based direction search)
- Keycode translation (`translate-keycode`)
- Built-in widget reference:
  - PANEL (container with raised bevel)
  - HBOX / VBOX (layout containers)
  - LABEL (text display)
  - BUTTON (clickable with pressed state)
  - CHECKBOX (toggle with checkmark)
  - TEXT-INPUT (editable text field with cursor)
  - CANVAS (2D diagram with world coordinates, grid, axes, shapes)
- Bevel drawing (`draw-bevel`: raised/sunken Xaw3d-style)

### 05_event_loop.md — Event Loop & MUV Architecture
**Relevant files to read:** `05_event_loop.lisp`, DeepWiki query 4
**Content:**
- Model-Update-View (MUV / Elm Architecture) pattern
- `run-gui` function signature and parameters
- Event dispatch: how X11 event codes map to handlers
- State management: immutable state, `update-fn` produces new state, `view-fn` produces virtual DOM
- Dirty tracking: `compute-dirty-widgets`, `save-visual-state`
- Rendering strategies:
  - `full-redraw`: window-wide pixmap double buffering
  - `partial-redraw`: targeted widget re-rendering
  - `smart-redraw`: automatic dirty detection
- Tick-based animation: `tick-interval`, `tick-msg`
- Mouse interaction: hover tracking, click-to-focus, button press/release
- Keyboard interaction: directional focus navigation, text input handling
- Window resize handling via ConfigureNotify
- The `init-fn` callback for custom initialization

### 06_examples.md — Example Applications
**Relevant files to read:** `06_example_template.lisp`, `08_orbit_demo_template.lisp`, `run-example.sh`, `run-orbit-demo.sh`
**Content:**
- Demo App walkthrough:
  - `app-state` struct
  - `update` function (message dispatch)
  - `view` function (virtual DOM generation)
  - How to run it
- Orbit Demo walkthrough:
  - Hohmann transfer physics
  - Custom GC colors
  - Tick-driven animation
  - Canvas shapes API
  - How to run it
- How to write your own MUV application (step-by-step guide)

### 07_testing.md — Testing
**Relevant files to read:** `07_tests_template.lisp`, `run-xvfb-test.sh`, `run-xvfb-orbit-demo.sh`
**Content:**
- Test framework (`assert-test` macro, `*test-failures*` counter)
- Test suite reference (all 9 suites with what they verify)
- How to run tests headless (Xvfb setup)
- How to run tests locally
- How to add new tests

### 08_api_reference.md — Complete API Reference
**Relevant files to read:** `02_x11_spec.lisp`, `03_widgets_core.lisp`, `04_widgets_builtin.lisp`, `05_event_loop.lisp`, `generate.lisp`
**Content:**
- Organized by module:
  - **Connection**: `connect`, `big-requests-enable`
  - **Window/GC management**: `make-window`, `map-window`, `destroy-window`, `create-gc`, `free-gc`, `change-window-attributes`, `configure-window`
  - **Drawing**: `draw-line`, `draw-window`, `clear-area`, `imagetext8`, `poly-rectangle`, `poly-fill-rectangle`, `poly-arc`, `poly-fill-arc`, `copy-area`
  - **Images**: `create-pixmap`, `free-pixmap`, `put-image-big-req`
  - **Input**: `query-pointer`, `grab-pointer`, `ungrab-pointer`, `get-keyboard-mapping`
  - **Fonts/Cursors**: `open-font`, `close-font`, `create-cursor`
  - **Extensions**: `query-extension`
  - **Widgets**: all public widget functions
  - **Event Loop**: `run-gui`, redraw functions
- For each function: signature, docstring, parameters, return values, example usage
- Global variables reference (`*s*`, `*root*`, `*window*`, `*gc-*`, etc.)
- Exported symbols list (from package.lisp in generate.lisp lines 24–83)

### walkthrough.md — End-to-End Walkthrough
**Relevant files to read:** All of the above (synthesize)
**Content:**
- A narrative walkthrough from "I just cloned the repo" to "I have a running GUI app"
- Step 1: Prerequisites (SBCL, Quicklisp, X11 display)
- Step 2: Running the generator (`sbcl --load generate.lisp`)
- Step 3: Understanding what was generated
- Step 4: Running the demo app
- Step 5: Running the orbit demo
- Step 6: Running the test suite
- Step 7: Creating your own widget
- Step 8: Creating your own MUV application
- Step 9: Extending the X11 protocol layer (adding a new request)
- Include code snippets for each step
- Include expected output/behavior

---

## Step 3: Writing Guidelines

1. **Language:** Write in English.
2. **Audience:** Intermediate Common Lisp developer who may not know X11.
3. **Style:**
   - Use clear section headers with `##` and `###`
   - Include code examples from the actual source (use fenced code blocks with `lisp` language)
   - Use tables for API references
   - Use mermaid diagrams for architecture and data flow where helpful
   - Cross-reference other doc files with relative markdown links (e.g., `[Widget System](04_widget_system.md)`)
4. **Accuracy:** Always verify claims against the actual source code. Do NOT copy claims from README or DeepWiki without checking. For example, the README mentions "Quadtree" and "Delaunay Triangulation" but neither is actually implemented — the code uses linear search and cone filtering.
5. **File links:** When referencing source files, use relative paths from the doc/ directory (e.g., `../02_x11_spec.lisp`).
6. **Each file should start with:**
   ```markdown
   # [Title]
   
   > Part of the [Pure X11 GUI Toolkit](../README.md) documentation.
   > Generated: YYYY-MM-DD
   ```

---

## Step 4: Execution Order

Execute in this exact order:

1. Run DeepWiki queries (Step 0) — all 4 queries in parallel
2. Read generator template files (`01_`–`08_`) — all 8 in parallel
3. Read `generate.lisp` and `README.md`
4. Read `run-example.sh`, `run-xvfb-test.sh` (support files)
5. Optionally read `plan/20260722_01_review/code_review.md` for known issues
6. Create `/workspace/src/cl-cl-generator/example/07_pure_x11/doc/` directory
7. Write documentation files in order: `01_overview.md` through `08_api_reference.md`
8. Write `walkthrough.md` last (it synthesizes everything)
9. Commit all files

---

## Step 5: Git Commit

After ALL documentation files are written and verified, commit with:

```bash
cd /workspace/src/cl-cl-generator
git add example/07_pure_x11/doc/
git commit -m "docs(07_pure_x11): add comprehensive developer documentation

Add 9 documentation files for the Pure X11 GUI Toolkit:

- 01_overview.md: Project overview and design philosophy
- 02_code_generation.md: Code generation architecture and cl-cl-generator DSL
- 03_x11_protocol.md: X11 protocol layer with complete request/event reference
- 04_widget_system.md: Widget system, TeX glue layout engine, and built-in widgets
- 05_event_loop.md: MUV event loop, dirty tracking, and rendering strategies
- 06_examples.md: Demo app and orbit demo walkthroughs with how-to guide
- 07_testing.md: Test framework, suite reference, and headless testing setup
- 08_api_reference.md: Complete API reference organized by module
- walkthrough.md: End-to-end narrative from setup to custom application

Documentation generated from source analysis and DeepWiki context.
Covers architecture, protocol details, widget system, and extension guides."
```

---

## Quality Checklist

Before committing, verify:

- [ ] All 9 files exist in `doc/`
- [ ] No broken relative links between doc files
- [ ] Code examples are syntactically valid Lisp
- [ ] API reference covers all 19 X11 requests and 6 event parsers
- [ ] All 8 built-in widget types are documented
- [ ] `run-gui` signature and all parameters are documented
- [ ] walkthrough.md has runnable commands
- [ ] No placeholder text like "TODO" or "TBD" remains
- [ ] Mermaid diagrams render correctly (test by checking syntax)
- [ ] Cross-references between docs use correct relative paths
