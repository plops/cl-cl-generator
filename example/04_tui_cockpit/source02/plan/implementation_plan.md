# Implementation Plan - Interactive TUI Cockpit (cl-tuition)

This plan outlines the design and implementation of the second cockpit variant (`gen02.lisp`) which generates a fully interactive terminal cockpit using the `cl-tuition` framework (based on the Elm Architecture) and testing via `Rove`.

## User Review Required

> [!IMPORTANT]
> Because per-process network sockets are parsed from `/proc/<pid>/fd/` and throttling utilizes `cgroups v2` and Traffic Control (`tc`), running the generated cockpit requires **root/sudo** privileges.

## Proposed Changes

We will introduce a new generator `gen02.lisp` in the example folder. Running this generator will output all implementation and test files into the `source02/` subdirectory.

---

### [Component] TUI Cockpit Generator (Version 2)

#### [NEW] [gen02.lisp](file:///workspace/src/cl-cl-generator/example/04_tui_cockpit/gen02.lisp)
This generator will write the following files to `example/04_tui_cockpit/source02/`:

1. **[package.lisp](file:///workspace/src/cl-cl-generator/example/04_tui_cockpit/source02/package.lisp)**
   - Exports the main interface package `cockpit-tui` and its entry function `run-cockpit`.
2. **[cockpit.asd](file:///workspace/src/cl-cl-generator/example/04_tui_cockpit/source02/cockpit.asd)**
   - Defines the `cockpit-tui` system.
   - Depends on: `"alexandria"`, `"uiop"`, `"cl-tuition"`.
   - Defines a `cockpit-tui/tests` test system.
   - Depends on: `"cockpit-tui"`, `"rove"`.
3. **[cockpit.lisp](file:///workspace/src/cl-cl-generator/example/04_tui_cockpit/source02/cockpit.lisp)**
   - Implements the `/proc` parsing backend.
   - Defines `cockpit-model` CLOS class to hold application state:
     - Global CPU, Swap, IO pressure, and Network stats history.
     - Process-level states: `pid-net-accumulators` (hash table mapping PIDs to cumulative downloaded bytes) and `pid-net-histories` (hash table mapping PIDs to lists of recent rates).
     - Selection state: `selected-index` for navigating the active list.
     - Settings: `interval-sec` and `show-help-p`.
   - Implements `tui:init`, `tui:update-message`, and `tui:view`:
     - **Keybindings**:
       - `q` / `Esc`: Exits the cockpit.
       - `h` / `F1`: Toggles help screen overlay.
       - `Up` / `Down` arrows: Changes `selected-index` in the process list.
       - `t` / `Enter`: Throttles the selected process.
       - `+` / `-`: Increases/decreases refresh intervals.
     - **Layout**: Uses `cl-tuition` formatting, colors, and layout joins to produce a premium dashboard, including process list entries showing current rates, sparkline history, and total accumulated data.
4. **[tests.lisp](file:///workspace/src/cl-cl-generator/example/04_tui_cockpit/source02/tests.lisp)**
   - Implements unit tests using `Rove`.
   - Tests:
     - **State updates**: Verifies `tui:update-message` on keypresses (`+`, `-`, `Down`, `h`).
     - **Rendering checks**: Verifies `tui:view` outputs correct strings (like cursor symbols `->` and help overlay text).
     - **Parser checks**: Verifies `/proc` parsers work correctly on mock files.
5. **[run-cockpit.sh](file:///workspace/src/cl-cl-generator/example/04_tui_cockpit/source02/run-cockpit.sh)**
   - Startup script that runs the new `cl-tuition`-based cockpit.
6. **[README.md](file:///workspace/src/cl-cl-generator/example/04_tui_cockpit/source02/README.md)**
   - Details how to run the interactive version and its key combinations.

---

## Verification Plan

### Automated Tests
We will verify the implementation by running Rove tests:
```bash
sbcl --eval '(push "/workspace/src/cl-cl-generator/example/04_tui_cockpit/source02/" asdf:*central-registry*)' \
     --eval '(asdf:test-system :cockpit-tui/tests)' \
     --quit
```

### Manual Verification
1. Run `sbcl --load example/04_tui_cockpit/gen02.lisp --quit` to generate all files.
2. Execute `./run-cockpit.sh` inside `source02/` (as root) to launch the interactive cockpit.
3. Test key presses (`Up`/`Down` arrows, `+`/`-`, `h` for help, and `q` to quit) to verify reactive changes.
