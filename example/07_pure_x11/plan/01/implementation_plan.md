# Implementation Plan - X11 Code Generator Example

Create a new example `07_pure_x11` for `cl-cl-generator` that generates a pure X11 interface in Common Lisp. This example showcases how `cl-cl-generator` reduces boilerplate by defining X11 requests declaratively and generating functions dynamically.

## Proposed Changes

We will create a new directory `/workspace/src/cl-cl-generator/example/07_pure_x11/` containing a generator script `gen.lisp`. 

The generator will output:
1. `package.lisp` - Defines the `:pure-x11-gen` package.
2. `pure-x11-gen.asd` - Defines the ASDF system.
3. `x11-core.lisp` - Core socket communication, binary protocols (`with-packet` / `with-reply`), and generated request APIs.
4. `example.lisp` - A demonstration client demonstrating connection and drawing operations.

---

### [Component: X11 Generator Example]

#### [NEW] [gen.lisp](file:///workspace/src/cl-cl-generator/example/07_pure_x11/gen.lisp)
The Lisp script that defines the X11 request specification and uses `cl-cl-generator` to output the library source code.
It showcases:
- **Code Emitters (`emit-request-function`)**: A Lisp function that takes a declarative request specification (name, params, packet structure, reply structure, etc.) and emits the Lisp function definition.
- **Splicing (`,@(loop ...)`)**: Splicing the generated request functions and constant lookup lists.
- **Dynamic Lookup Table Generator**: Emits helper lookup functions for events and value masks from their lists.

The specification table includes:
- `make-window` (CreateWindow, CreateGC, MapWindow combined)
- `map-window` (MapWindow)
- `clear-area` (ClearArea)
- `draw-window` (PolySegment)
- `query-pointer` (QueryPointer)
- `imagetext8` (ImageText8)
- `query-extension` (QueryExtension)
- `big-requests-enable` (BigRequestsEnable)
- `put-image-big-req` (PutImage with big requests)

---

## Verification Plan

### Automated Tests
1. **Generate Source Files**:
   Run the generator script to verify it executes without errors and outputs all expected files.
   ```bash
   sbcl --load /workspace/src/cl-cl-generator/example/07_pure_x11/gen.lisp
   ```

2. **Verify Load and Compile**:
   Start SBCL, register the generated system, and load it to ensure there are no compilation or read errors in the generated code.
   ```bash
   sbcl --eval '(push "/workspace/src/cl-cl-generator/example/07_pure_x11/source/" asdf:*central-registry*)' \
        --eval '(ql:quickload :pure-x11-gen)' \
        --eval '(quit)'
   ```

### Manual Verification
- Review the generated `x11-core.lisp` file to verify that the pretty printer correctly formatted the comments, function definitions, and macros.
