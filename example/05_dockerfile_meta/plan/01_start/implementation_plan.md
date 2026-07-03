# Implementation Plan: cl-dockerfile-generator

This plan outlines the steps to build the `cl-dockerfile-generator` transpiler. We will use a meta-generator `gen.lisp` to generate the transpiler file `dock.lisp` to minimize duplication and boilerplates.

## Proposed Changes

### [Component Name] cl-dockerfile-generator

We will create the following files in the workspace:

#### [NEW] [gen.lisp](file:///workspace/src/cl-cl-generator/example/05_dockerfile_meta/gen.lisp)
- A generator script using `cl-cl-generator` to dynamically construct and write the code for `source01/dock.lisp`.
- Defines builder functions/helpers at generation time to generate the case-inversion setup, dispatch tables, unified argument emitters, and command formatters without repetitive code.
- Defines the raw string reader macro `#r` so it's registered for parsing template code.
- Generates the test inputs and expected outputs as part of the generator run.

#### [NEW] [dock.lisp](file:///workspace/src/cl-cl-generator/example/05_dockerfile_meta/source01/dock.lisp) (Generated)
- The transpiler package definition (`cl-dockerfile-generator`).
- Contains the `readtable` case-inversion settings.
- Contains the implementation of the raw-string reader macro `#r`.
- Contains the `emit-df` pretty-printing dispatcher table that converts Lisp forms to Dockerfile string lines.
- Exposes `emit-df` and `write-df` (using sxhash file hashing to preserve mtime).

#### [NEW] [run_tests.lisp](file:///workspace/src/cl-cl-generator/example/05_dockerfile_meta/source01/run_tests.lisp)
- Load/require `dock.lisp`.
- Run automated unit tests using `assert` for:
  - Symbols case sensitivity (e.g. `DEBIAN_FRONTEND` vs `noninteractive`).
  - Vertical bar symbols (`|apt-get update|`).
  - Raw string reader macro `#r` with different delimiters.
  - Multi-line commands with `and` and `seq` formats.
  - Correct Dockerfile output generation for complex scenarios.

#### [NEW] [Dockerfile](file:///workspace/src/cl-cl-generator/example/05_dockerfile_meta/source01/examples/01_gentoo/Dockerfile) (Generated)
- Emitted Gentoo build stage Dockerfile, matching the example:
  `/workspace/src/cl-py-generator/example/110_gentoo/openrc/Dockerfile`

#### [NEW] [Dockerfile](file:///workspace/src/cl-cl-generator/example/05_dockerfile_meta/source01/examples/02_agy_env/Dockerfile) (Generated)
- Emitted Antigravity runtime runner Dockerfile, matching the example:
  `/workspace/src/cl-py-generator/example/172_docker_agy_env/Dockerfile`

---

## Verification Plan

### Automated Tests
We will run a script to compile the meta-generator, generate `dock.lisp` and the examples, and execute the test suite:
```bash
# Run generator to build source01/dock.lisp and output Dockerfiles
sbcl --load example/05_dockerfile_meta/gen.lisp --eval "(quit)"

# Run unit tests
sbcl --load example/05_dockerfile_meta/source01/run_tests.lisp --eval "(quit)"
```

### Manual Verification
- We will diff the generated Dockerfiles under `source01/examples/01_gentoo/Dockerfile` and `source01/examples/02_agy_env/Dockerfile` with the original files in `cl-py-generator` to ensure semantic parity and correctness.
