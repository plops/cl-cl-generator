# Task List: Soft-Constraints, General Constraints & Physics Guide

- [x] Implement soft-constraints parsing and dimension setting (`ns`) in `make-mpc-solver` inside `gen02.lisp`
- [x] Implement `idxs`, `Zl`, `Zu`, `zl`, `zu`, `lls`, `lus` setter logic in `make-mpc-solver`
- [x] Implement general constraints setters `set-general-constraints` and `set-solver-general-constraints` in `hpipm-high` generator template inside `gen02.lisp`
- [x] Update `solve-mpc` inside `hpipm-high` generator template to retrieve and return optimal slack trajectories `sl` and `su`
- [x] Create `mpc-soft-demo.lisp` generator template in `gen02.lisp` to demonstrate soft-constraints
- [x] Update `package.lisp` and `hpipm.asd` generators in `gen02.lisp` to include `set-general-constraints`, `set-solver-general-constraints`, and `mpc-soft-demo`
- [x] Run `gen02.lisp` and verify creation of all files in `source01/`
- [x] Verify compilation and loading of the updated `:hpipm` system via ASDF
- [x] Write `solver_guide_physics.md` documenting the high-level API for physicists
