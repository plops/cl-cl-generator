# Walkthrough - TUI Cockpit for Linux (Bandwidth Optimized)

We have successfully built and verified the bandwidth-optimized Linux TUI Cockpit generator and compiled the output.

## Codebase Structure

The codebase is located in [example/04_tui_cockpit/](file:///workspace/src/cl-cl-generator/example/04_tui_cockpit/):

1. [plan/requirements_and_implementation.md](file:///workspace/src/cl-cl-generator/example/04_tui_cockpit/plan/requirements_and_implementation.md): Holds requirements, low-bandwidth design choices, and implementation details.
2. [plan/implementation_plan.md](file:///workspace/src/cl-cl-generator/example/04_tui_cockpit/plan/implementation_plan.md): The detailed design plan.
3. [plan/walkthrough.md](file:///workspace/src/cl-cl-generator/example/04_tui_cockpit/plan/walkthrough.md): This walkthrough document documenting outcomes.
4. [gen.lisp](file:///workspace/src/cl-cl-generator/example/04_tui_cockpit/gen.lisp): The Common Lisp code generator. It dynamically builds `/proc/` parsers using generation-time lists, avoiding repeating logic.
5. [package.lisp](file:///workspace/src/cl-cl-generator/example/04_tui_cockpit/package.lisp): The package exports.
6. [cockpit.asd](file:///workspace/src/cl-cl-generator/example/04_tui_cockpit/cockpit.asd): ASDF system definition.
7. [cockpit.lisp](file:///workspace/src/cl-cl-generator/example/04_tui_cockpit/cockpit.lisp): The fully compiled, formatted, and optimized output file.

---

## Verifications Performed

1. **Parentheses Balances:** Checked and verified that `gen.lisp` is perfectly balanced.
2. **Generation:** Ran `gen.lisp` using SBCL, which compiled the generator and outputted the pretty-printed, resolved Lisp code to `cockpit.lisp`.
3. **Compilation:** Loaded the generated `:cockpit` ASDF system in SBCL. It compiled without any errors or warnings.
4. **Live Execution Test:** Ran core parsers on live `/proc` data in SBCL as root. It successfully parsed CPU ticks, network rates, memory pages, IO pressure, and matched the network socket inodes to active PIDs.
5. **Column Alignment:** Adjusted PID format to `~7d`, limited name to 15 chars, and normalized rate units. Verified the resulting console layouts are perfectly aligned.

---

## How to Run the Cockpit

To run the generated cockpit, make sure you are running as **root** (required to read `/proc/<pid>/fd/` and to configure `cgroups` / `tc`), and start SBCL:

```bash
sbcl --eval '(push "/workspace/src/cl-cl-generator/example/04_tui_cockpit/" asdf:*central-registry*)' \
     --eval '(ql:quickload :cockpit)' \
     --eval '(cockpit:run-cockpit)'
```
