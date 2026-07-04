# Phase 1 Implementation Tasks — Athena-Style X11 Widget Library

> **Context for implementers**: This task list implements Phase 1 of a redesign of the pure X11 widget library in [example/07_pure_x11](file:///workspace/src/cl-cl-generator/example/07_pure_x11). The library is generated using the `cl-cl-generator` S-expression code generator. You MUST read the [cl-cl-generator SKILL.md](file:///workspace/src/cl-cl-generator/.agents/skills/cl-cl-generator/SKILL.md) before starting any task — it explains how S-expression templates, `toplevel`, `comment`, `raw`, `,@(loop ...)`, and `write-source` work.
>
> The full design rationale is in [plan/04/implementation_plan.md](file:///workspace/src/cl-cl-generator/example/07_pure_x11/plan/04/implementation_plan.md).
>
> **Key architecture**: This is a Common Lisp project where generator-time code (files `01_*.lisp` through `07_*.lisp` in the project root) produces runtime code (files in `source/`). The generator is run via `sbcl --load generate.lisp`. The generated output is an ASDF system `:pure-x11-gen` in `source/`.

---

## Task 1: Restructure Generator File Loading

- `[x]` completed / `[/]` in progress / `[ ]` not started

### Status: `[ ]`

### What to do

Rename and split the existing template files to match the new organization. Update [generate.lisp](file:///workspace/src/cl-cl-generator/example/07_pure_x11/generate.lisp) to load the new files in order.

### Steps

- `[ ]` **1a.** Rename `04_example_template.lisp` → `06_example_template.lisp`
- `[ ]` **1b.** Rename `05_tests_template.lisp` → `07_tests_template.lisp`
- `[ ]` **1c.** Create empty placeholder files `03_widgets_core.lisp`, `04_widgets_builtin.lisp`, `05_event_loop.lisp` (content will be filled by Tasks 3-5). Each must start with `(in-package :cl-cl-generator/example-x11-gen)` and define a `defparameter` for its template code (e.g., `*widgets-core-template-code*`, `*widgets-builtin-template-code*`, `*event-loop-template-code*`).
- `[ ]` **1d.** Update `generate.lisp` lines 6-10 to load:
  ```lisp
  (load "01_package.lisp")
  (load "02_x11_spec.lisp")
  (load "03_widgets_core.lisp")
  (load "04_widgets_builtin.lisp")
  (load "05_event_loop.lisp")
  (load "06_example_template.lisp")
  (load "07_tests_template.lisp")
  ```
- `[ ]` **1e.** Update `run-generator` in `generate.lisp` to emit the new files. Currently it emits `widgets`, `example`, `tests`. Change to emit:
  - `"widgets-core"` from `*widgets-core-template-code*`
  - `"widgets-builtin"` from `*widgets-builtin-template-code*`
  - `"event-loop"` from `*event-loop-template-code*`
  - `"example"` from `*example-template-code*`
  - `"tests"` from `*tests-template-code*`
- `[ ]` **1f.** Update the `.asd` system definition in `generate.lisp` (lines 68-77) to list the new components in order:
  ```lisp
  :components ((:file "package")
               (:file "x11-core")
               (:file "widgets-core")
               (:file "widgets-builtin")
               (:file "event-loop")
               (:file "example")
               (:file "tests"))
  ```
- `[ ]` **1g.** Delete the old `03_widgets_template.lisp` file once its content has been migrated to the three new files (Tasks 3-5).

### Validation

```bash
cd /workspace/src/cl-cl-generator/example/07_pure_x11
sbcl --load generate.lisp
# Should print "Successfully generated X11 example client codebase in ..."
# Check that source/ contains: package.lisp, x11-core.lisp, widgets-core.lisp,
# widgets-builtin.lisp, event-loop.lisp, example.lisp, tests.lisp
ls source/
```

---

## Task 2: Add GCs and Buffered Output to X11 Core

### Status: `[ ]`

### What to do

Modify the X11 protocol layer to support 5 GCs (instead of 2) and add request buffering. This task modifies [02_x11_spec.lisp](file:///workspace/src/cl-cl-generator/example/07_pure_x11/02_x11_spec.lisp) and [generate.lisp](file:///workspace/src/cl-cl-generator/example/07_pure_x11/generate.lisp).

### Design context

The current code creates 2 GCs inside the `make-window` request: `*gc*` (white foreground) and `*gc2*` (black foreground). We need 5 GCs for Xaw3d-style rendering:

| Variable | Foreground Pixel | Purpose |
|---|---|---|
| `*gc-light*` | `#x00ffffff` (white) | Bevel highlight (top-left of raised widgets) |
| `*gc-face*` | `#x00c0c0c0` (light gray) | Widget face fill |
| `*gc-shadow*` | `#x00808080` (mid gray) | Bevel shadow (bottom-right inner) |
| `*gc-dark*` | `#x00404040` (dark gray) | Bevel dark edge (bottom-right outer) |
| `*gc-text*` | `#x00000000` (black) | Text rendering |

These use hardcoded TrueColor pixel values — no `AllocColor` round trips.

### Steps

- `[ ]` **2a.** In [02_x11_spec.lisp](file:///workspace/src/cl-cl-generator/example/07_pure_x11/02_x11_spec.lisp), modify the `make-window` request spec (lines 71-124). Change the `:bindings` to allocate 5 GC resource IDs instead of 2:
  ```lisp
  :bindings ((window   (logior *resource-id-base* (logand *resource-id-mask* 1)))
             (gc-light (logior *resource-id-base* (logand *resource-id-mask* 2)))
             (gc-face  (logior *resource-id-base* (logand *resource-id-mask* 3)))
             (gc-shadow(logior *resource-id-base* (logand *resource-id-mask* 4)))
             (gc-dark  (logior *resource-id-base* (logand *resource-id-mask* 5)))
             (gc-text  (logior *resource-id-base* (logand *resource-id-mask* 6)))
             ...)
  ```
  Change the `:post` to set 5 `defparameter`s:
  ```lisp
  :post ((defparameter *window* window)
         (defparameter *gc-light* gc-light)
         (defparameter *gc-face* gc-face)
         (defparameter *gc-shadow* gc-shadow)
         (defparameter *gc-dark* gc-dark)
         (defparameter *gc-text* gc-text))
  ```
  Add 3 more CreateGC blocks to the `:packet` section (copy the existing pattern at lines 102-118). Each CreateGC is:
  ```
  (card8 55)          ; opcode
  (card8 0)
  (card16 6)          ; request length = 6 (header + drawable + bitmask + 2 values)
  (card32 <gc-id>)    ; GC resource ID
  (card32 window)     ; drawable
  (card32 #x0c)       ; value-mask: foreground(#x04) + background(#x08) = #x0c
  (card32 <fg-pixel>) ; foreground pixel value
  (card32 <bg-pixel>) ; background pixel value (use 0 for all)
  ```
  The background pixel for all GCs should be `#x00c0c0c0` (face color) except `*gc-light*` which can use `0`.

- `[ ]` **2b.** In [generate.lisp](file:///workspace/src/cl-cl-generator/example/07_pure_x11/generate.lisp), update the `defparameter` declarations (around line 94-97) to declare the 5 GC variables:
  ```lisp
  (defparameter *gc-light* nil)
  (defparameter *gc-face* nil)
  (defparameter *gc-shadow* nil)
  (defparameter *gc-dark* nil)
  (defparameter *gc-text* nil)
  ```
  Remove the old `*gc*` and `*gc2*` declarations.

- `[ ]` **2c.** In [generate.lisp](file:///workspace/src/cl-cl-generator/example/07_pure_x11/generate.lisp), replace the `with-packet` macro (lines 107-131, inside a `(raw "...")` block) with a dual-mode version. The new macro should:
  - Check if `*packet-buffer*` is bound and non-nil
  - If so: append the byte vector to `*packet-buffer*` (a list of byte vectors)
  - If not: write directly to `*s*` and `force-output` as before

  Add these alongside the macro (still inside `(raw "...")` blocks):
  ```lisp
  (defvar *packet-buffer* nil)

  (defun flush-packets ()
    "Write all buffered packets to the socket in one batch."
    (when (and *packet-buffer* *s*)
      (dolist (buf (nreverse *packet-buffer*))
        (write-sequence buf *s*))
      (force-output *s*)
      (setf *packet-buffer* nil)))

  (defmacro with-buffered-output (&body body)
    "Execute body with request buffering. Flushes on exit."
    `(let ((*packet-buffer* (list)))
       (unwind-protect (progn ,@body)
         (flush-packets))))
  ```

  The modified `with-packet`:
  ```lisp
  (defmacro with-packet (&body body)
    `(let* ((l ()))
       (labels ((string8 (a) ...)  ;; same as before
                (card8 (a) ...)
                (card16 (a) ...)
                (card32 (a) ...))
         ,@body
         (let ((buf (make-array (length l)
                                :element-type '(unsigned-byte 8)
                                :initial-contents (nreverse l))))
           (if *packet-buffer*
               (push buf *packet-buffer*)
               (progn
                 (write-sequence buf *s*)
                 (force-output *s*)))))))
  ```

- `[ ]` **2d.** Update the package exports in `generate.lisp` (lines 22-60). Remove `#:*gc*` and `#:*gc2*`. Add:
  ```lisp
  #:*gc-light*
  #:*gc-face*
  #:*gc-shadow*
  #:*gc-dark*
  #:*gc-text*
  #:*packet-buffer*
  #:with-buffered-output
  #:flush-packets
  ```

- `[ ]` **2e.** Add a `draw-line` request to [02_x11_spec.lisp](file:///workspace/src/cl-cl-generator/example/07_pure_x11/02_x11_spec.lisp) `*x11-requests*` — a simpler line-drawing function that takes an explicit `:gc` parameter (the bevel code needs to draw lines with different GCs). This is a thin wrapper around PolySegment (opcode 66):
  ```lisp
  (:name draw-line
   :doc "Draw a single line segment from (x1,y1) to (x2,y2) using specified GC."
   :params (x1 y1 x2 y2 &key (gc *gc-text*))
   :packet ((card8 66)
            (card8 0)
            (card16 5)
            (card32 *window*)
            (card32 gc)
            (card16 x1) (card16 y1) (card16 x2) (card16 y2)))
  ```

### Validation

```bash
sbcl --load generate.lisp
# Should succeed without errors.
# Inspect source/x11-core.lisp — verify it contains:
#   - defparameter for *gc-light*, *gc-face*, *gc-shadow*, *gc-dark*, *gc-text*
#   - defvar *packet-buffer*
#   - with-buffered-output macro
#   - flush-packets function
#   - draw-line function
#   - 5 CreateGC blocks inside make-window
grep -c "gc-light\|gc-face\|gc-shadow\|gc-dark\|gc-text" source/x11-core.lisp
# Should be >= 10 (declarations + usages)
grep "packet-buffer" source/x11-core.lisp
# Should find defvar and references
```

---

## Task 3: Widget Core — Registry, Bevels, Layout Engine

### Status: `[ ]`

### What to do

Create [03_widgets_core.lisp](file:///workspace/src/cl-cl-generator/example/07_pure_x11/03_widgets_core.lisp) containing the widget infrastructure. This file produces `source/widgets-core.lisp`.

### Source material

Migrate the following functions from the OLD [03_widgets_template.lisp](file:///workspace/src/cl-cl-generator/example/07_pure_x11/03_widgets_template.lisp) (lines 5-211). **Read that file carefully** — the functions to migrate are:

- `defstruct widget` (line 10)
- `parse-node` (lines 17-34)
- `collect-focusable-widgets` (lines 36-49)
- `find-widget-at` (lines 51-67)
- `find-widget-by-name` (lines 69-80)
- `find-nearest-widget` (lines 82-112)
- `translate-keycode` (lines 114-133)

### Steps

- `[ ]` **3a.** Create the file `03_widgets_core.lisp` in the project root (same directory as `generate.lisp`). It must:
  - Be in package `:cl-cl-generator/example-x11-gen`
  - Define `*widgets-core-template-code*` as a `defparameter` containing a `(toplevel ...)` S-expression template
  - Include `(in-package :pure-x11-gen)` as the first form inside `toplevel`

- `[ ]` **3b.** Migrate the 7 functions listed above into the template. Keep them exactly as they are — they work correctly.

- `[ ]` **3c.** Add the **widget type registry** to the template:
  ```lisp
  (defvar *widget-renderers* (make-hash-table :test 'equal))

  (defun register-widget (type-name render-fn)
    "Register a render function for widget TYPE-NAME (a string like \"BUTTON\").
     RENDER-FN is called as (funcall render-fn widget-struct focused pressed hovered)."
    (setf (gethash (string-upcase (string type-name)) *widget-renderers*) render-fn))

  (defun render-widget (w-struct focused pressed hovered)
    "Dispatch rendering to the registered handler for this widget's type."
    (let* ((type (widget-type w-struct))
           (type-name (and type (symbolp type) (string-upcase (symbol-name type))))
           (renderer (when type-name (gethash type-name *widget-renderers*))))
      (when renderer
        (funcall renderer w-struct focused pressed hovered))))

  (defun render-layout (layout focused pressed hovered)
    "Walk the layout tree, render each node via the registry, then recurse into children."
    (labels ((render-node (node)
               (when (listp node)
                 (let ((w-struct (parse-node node)))
                   (render-widget w-struct focused pressed hovered)
                   ;; Children are rendered by the widget's renderer if it's a container,
                   ;; or here as fallback for unknown containers
                   ))))
      (render-node layout)))
  ```

  **Important**: Container widgets (panel, hbox, vbox) are responsible for rendering their own children inside their renderer function. The `render-layout` at the top level just kicks off the root node. The actual child traversal happens inside each container's registered renderer. So `render-layout` should call `render-widget` on the root, and each container renderer should call `render-layout-children` (a helper) on its children list:

  ```lisp
  (defun render-layout-children (children focused pressed hovered)
    "Render a list of child layout nodes."
    (dolist (child children)
      (when (listp child)
        (let ((w-struct (parse-node child)))
          (render-widget w-struct focused pressed hovered)))))
  ```

- `[ ]` **3d.** Add the **bevel drawing primitives**. These use the GCs from Task 2 and the `draw-line` function. Since this code will be inside a `(raw "...")` or regular S-expression template, make sure you reference the GC variables correctly (`*gc-light*`, `*gc-face*`, `*gc-shadow*`, `*gc-dark*`):

  ```lisp
  (defun draw-bevel (x y w h &key (style :raised) (bevel-width 2))
    "Draw Xaw3d-style 3D bevel around a rectangle.
     :raised = light top-left, dark bottom-right (normal state)
     :sunken = dark top-left, light bottom-right (pressed/inset state)
     BEVEL-WIDTH is the thickness in pixels (default 2 for classic Xaw3d look)."
    (let ((tl-outer (if (eq style :raised) *gc-light* *gc-dark*))
          (br-outer (if (eq style :raised) *gc-dark*  *gc-light*))
          (tl-inner (if (eq style :raised) *gc-face*  *gc-shadow*))
          (br-inner (if (eq style :raised) *gc-shadow* *gc-face*)))
      ;; Outer bevel
      (draw-line x y (+ x w -2) y :gc tl-outer)             ;; top
      (draw-line x y x (+ y h -2) :gc tl-outer)              ;; left
      (draw-line (+ x w -1) y (+ x w -1) (+ y h -1) :gc br-outer) ;; right
      (draw-line x (+ y h -1) (+ x w -1) (+ y h -1) :gc br-outer) ;; bottom
      (when (>= bevel-width 2)
        ;; Inner bevel
        (draw-line (1+ x) (1+ y) (+ x w -3) (1+ y) :gc tl-inner)       ;; top
        (draw-line (1+ x) (1+ y) (1+ x) (+ y h -3) :gc tl-inner)       ;; left
        (draw-line (+ x w -2) (1+ y) (+ x w -2) (+ y h -2) :gc br-inner) ;; right
        (draw-line (1+ x) (+ y h -2) (+ x w -2) (+ y h -2) :gc br-inner) ;; bottom
        )))
  ```

- `[ ]` **3e.** Add the **TeX-style glue layout solver**:

  ```lisp
  (defstruct glue
    (natural 0)   ;; preferred size in pixels
    (stretch 0)   ;; stretchability factor (0 = rigid)
    (shrink  0))  ;; shrinkability factor (0 = rigid)

  (defun solve-glue (glue-items available-space)
    "Distribute AVAILABLE-SPACE among GLUE-ITEMS (list of glue structs).
     Returns a list of computed sizes (integers), one per item.
     Algorithm: TeX's glue distribution — excess space is distributed
     proportionally to stretch factors; deficit proportionally to shrink factors."
    (let* ((total-natural (loop for g in glue-items sum (glue-natural g)))
           (excess (- available-space total-natural)))
      (cond
        ((>= excess 0)
         (let ((total-stretch (loop for g in glue-items sum (glue-stretch g))))
           (if (zerop total-stretch)
               (mapcar #'glue-natural glue-items)
               (mapcar (lambda (g)
                         (+ (glue-natural g)
                            (round (* excess (/ (glue-stretch g) total-stretch)))))
                       glue-items))))
        (t
         (let ((total-shrink (loop for g in glue-items sum (glue-shrink g))))
           (if (zerop total-shrink)
               (mapcar #'glue-natural glue-items)
               (mapcar (lambda (g)
                         (max 0 (+ (glue-natural g)
                                   (round (* excess (/ (glue-shrink g) total-shrink))))))
                       glue-items)))))))
  ```

- `[ ]` **3f.** Add the **hbox/vbox layout computation** helper. This is called by the hbox/vbox container renderers (Task 4) to compute child positions:

  ```lisp
  (defun compute-box-layout (w-struct axis)
    "Compute absolute positions for children of an hbox (axis=:x) or vbox (axis=:y).
     Reads :glue, :padding, :spacing from widget props and children.
     Returns a list of (child-node x y w h) tuples with resolved positions."
    (let* ((props (widget-props w-struct))
           (padding (or (getf props :padding) 0))
           (spacing (or (getf props :spacing) 0))
           (container-x (widget-x w-struct))
           (container-y (widget-y w-struct))
           (container-w (widget-w w-struct))
           (container-h (widget-h w-struct))
           (children (widget-children w-struct))
           (n (length children))
           (total-spacing (* spacing (max 0 (1- n))))
           (main-available (- (if (eq axis :x) container-w container-h)
                              (* 2 padding) total-spacing))
           ;; Extract glue from each child's :glue property
           (child-glues
             (mapcar (lambda (child)
                       (if (listp child)
                           (let* ((cw (parse-node child))
                                  (g (getf (widget-props cw) :glue)))
                             (if g
                                 (make-glue :natural (or (getf g :natural) 0)
                                            :stretch (or (getf g :stretch) 0)
                                            :shrink  (or (getf g :shrink) 0))
                                 (make-glue :natural (if (eq axis :x)
                                                         (widget-w cw)
                                                         (widget-h cw))
                                            :stretch 0 :shrink 0)))
                           (make-glue)))
                     children))
           (sizes (solve-glue child-glues main-available))
           (result nil)
           (pos (+ (if (eq axis :x) container-x container-y) padding)))
      (loop for child in children
            for size in sizes
            do (let* ((cw (if (listp child) (parse-node child) nil))
                      (cx (if (eq axis :x) pos (+ container-x padding)))
                      (cy (if (eq axis :x) (+ container-y padding) pos))
                      (cw-val (if (eq axis :x) size (- container-w (* 2 padding))))
                      (ch-val (if (eq axis :x) (- container-h (* 2 padding)) size)))
                 (push (list child cx cy cw-val ch-val) result)
                 (incf pos (+ size spacing))))
      (nreverse result)))
  ```

### Validation

```bash
sbcl --load generate.lisp
# Verify source/widgets-core.lisp exists and contains:
grep "register-widget\|draw-bevel\|solve-glue\|compute-box-layout" source/widgets-core.lisp
# Should find all 4 function definitions
```

---

## Task 4: Built-in Widget Renderers

### Status: `[ ]`

### What to do

Create [04_widgets_builtin.lisp](file:///workspace/src/cl-cl-generator/example/07_pure_x11/04_widgets_builtin.lisp) containing renderer registrations for the 5 widget types plus hbox/vbox containers. This file produces `source/widgets-builtin.lisp`.

### Source material

The OLD rendering code is in [03_widgets_template.lisp](file:///workspace/src/cl-cl-generator/example/07_pure_x11/03_widgets_template.lisp) lines 144-211 (the `render-layout` function with its `cond` chain). Refer to this for the current rendering logic of each widget type, then rewrite each as a registered renderer using the new GCs and bevel primitives.

### Design reference — GC usage in renderers

| Drawing operation | GC to use |
|---|---|
| Widget face background fill | `*gc-face*` |
| Text rendering | `*gc-text*` |
| Bevel highlight (top-left, raised) | `*gc-light*` |
| Bevel shadow (bottom-right inner) | `*gc-shadow*` |
| Bevel dark (bottom-right outer) | `*gc-dark*` |
| Text-input field white fill | `*gc-light*` |
| Checkbox check mark | `*gc-text*` |
| Focus indicator rectangle | `*gc-text*` |

### Steps

- `[ ]` **4a.** Create `04_widgets_builtin.lisp` with `(in-package :cl-cl-generator/example-x11-gen)` and `*widgets-builtin-template-code*` defparameter. The template starts with `(in-package :pure-x11-gen)`.

- `[ ]` **4b.** Register **panel** renderer. A panel:
  - Fills its rectangle with `*gc-face*` via `poly-fill-rectangle`
  - Draws a raised bevel via `(draw-bevel x y w h :style :raised)`
  - Renders children via `render-layout-children`

- `[ ]` **4c.** Register **hbox** renderer. An hbox:
  - Calls `(compute-box-layout w-struct :x)` to get child positions
  - For each `(child cx cy cw ch)` in the result, it renders the child with the computed absolute coordinates. Since the child S-expression has its own `:x`/`:y`/`:w`/`:h`, the renderer needs to **override** those values. One approach: rebuild the child node with updated coordinates before passing to `render-widget`.
  - Does NOT draw a background or bevel by default (it's a layout-only container)

- `[ ]` **4d.** Register **vbox** renderer. Same as hbox but with `(compute-box-layout w-struct :y)`.

- `[ ]` **4e.** Register **label** renderer. A label:
  - Draws text at `(x, y)` using `(imagetext8 text :x x :y y)` — note that X11's ImageText8 positions text at the **baseline**, so `y` is the baseline Y coordinate. The current code already handles this correctly.

- `[ ]` **4f.** Register **button** renderer. A button:
  - Fills the rectangle with `*gc-face*` via `poly-fill-rectangle`
  - If pressed (`(eq name pressed)`): draws sunken bevel via `(draw-bevel x y w h :style :sunken)`, draws text offset by +1,+1
  - If not pressed: draws raised bevel via `(draw-bevel x y w h :style :raised)`, draws text centered
  - Text centering: `text-x = x + (w - 6*length) / 2`, `text-y = y + h/2 + 4` (assuming ~6px per character for the default fixed font)

- `[ ]` **4g.** Register **checkbox** renderer. A checkbox:
  - Draws a 14x14 sunken-beveled indicator box at `(x+2, y + (h-14)/2)`:
    - Fill the inside with `*gc-light*` (white) via `poly-fill-rectangle` (inset by bevel width)
    - Draw sunken bevel: `(draw-bevel bx by 14 14 :style :sunken)`
    - If checked: draw "X" text inside the indicator
  - Draws the label text to the right at `(x+22, y + h/2 + 4)`
  - If focused: draw a dotted/solid rectangle around the label text using `*gc-text*`

- `[ ]` **4h.** Register **text-input** renderer. A text-input:
  - Fill the entire rectangle with `*gc-light*` (white background)
  - Draw sunken bevel: `(draw-bevel x y w h :style :sunken)`
  - Draw the text inside at `(x+6, y + h/2 + 4)` using `*gc-text*`
  - If focused: draw a vertical cursor line at `(x + 6 + 6*cursor-pos)` using `*gc-text*`

### Validation

```bash
sbcl --load generate.lisp
grep "register-widget" source/widgets-builtin.lisp
# Should find 7 register-widget calls (panel, hbox, vbox, label, button, checkbox, text-input)
grep "draw-bevel" source/widgets-builtin.lisp
# Should find multiple draw-bevel calls with :raised and :sunken
```

---

## Task 5: Event Loop with Dirty Tracking and Buffered Output

### Status: `[ ]`

### What to do

Create [05_event_loop.lisp](file:///workspace/src/cl-cl-generator/example/07_pure_x11/05_event_loop.lisp) containing the `run-gui` function and event dispatch. This file produces `source/event-loop.lisp`.

### Source material

The OLD event loop code is in [03_widgets_template.lisp](file:///workspace/src/cl-cl-generator/example/07_pure_x11/03_widgets_template.lisp) lines 213-355 (from `defvar *window-width*` through the end). **Read that entire section** — it contains the MUV event loop, keyboard handling, mouse handling, focus management, etc.

### Key changes from the old code

1. **Wrap all rendering in `with-buffered-output`** — so multiple drawing commands are batched into one TCP write
2. **Add dirty tracking** — track `*prev-focused*`, `*prev-pressed*`, `*prev-hovered*` and only redraw changed widgets on mouse/focus events
3. **Use new GC names** — all references to `*gc*` → `*gc-light*` or `*gc-text*`, `*gc2*` → `*gc-text*` or `*gc-dark*`
4. **Remove `draw-line-segment-gc2`** — replaced by `draw-line` from Task 2

### Steps

- `[ ]` **5a.** Create the file with the standard boilerplate. Define `*event-loop-template-code*`.

- `[ ]` **5b.** Migrate the state variables:
  ```lisp
  (defvar *window-width* 400)
  (defvar *window-height* 300)
  (defvar *focused-widget* nil)
  (defvar *pressed-widget* nil)
  (defvar *hovered-widget* nil)
  (defvar *prev-focused* nil)
  (defvar *prev-pressed* nil)
  (defvar *prev-hovered* nil)
  ```

- `[ ]` **5c.** Add dirty widget computation:
  ```lisp
  (defun compute-dirty-widgets ()
    "Return list of widget names whose visual state changed since last render."
    (let ((dirty nil))
      (when (not (eq *focused-widget* *prev-focused*))
        (when *prev-focused* (push *prev-focused* dirty))
        (when *focused-widget* (push *focused-widget* dirty)))
      (when (not (eq *pressed-widget* *prev-pressed*))
        (when *prev-pressed* (push *prev-pressed* dirty))
        (when *pressed-widget* (push *pressed-widget* dirty)))
      (when (not (eq *hovered-widget* *prev-hovered*))
        (when *prev-hovered* (push *prev-hovered* dirty))
        (when *hovered-widget* (push *hovered-widget* dirty)))
      (remove-duplicates dirty)))

  (defun save-visual-state ()
    "Snapshot current visual state for dirty tracking."
    (setf *prev-focused* *focused-widget*
          *prev-pressed* *pressed-widget*
          *prev-hovered* *hovered-widget*))
  ```

- `[ ]` **5d.** Add rendering functions:
  ```lisp
  (defun full-redraw (layout)
    "Full clear and render — used for Expose events and layout rebuilds."
    (with-buffered-output
      (clear-area :w *window-width* :h *window-height*)
      (render-layout layout *focused-widget* *pressed-widget* *hovered-widget*))
    (save-visual-state))

  (defun partial-redraw (layout dirty-names)
    "Re-render only the widgets in DIRTY-NAMES."
    (with-buffered-output
      (dolist (name dirty-names)
        (let ((w (find-widget-by-name layout name)))
          (when w
            (clear-area :x (widget-x w) :y (widget-y w)
                        :w (widget-w w) :h (widget-h w))
            (render-widget w *focused-widget* *pressed-widget* *hovered-widget*)))))
    (save-visual-state))

  (defun smart-redraw (layout)
    "Compute dirty widgets and do a partial redraw, or skip if nothing changed."
    (let ((dirty (compute-dirty-widgets)))
      (when dirty
        (partial-redraw layout dirty))))
  ```

- `[ ]` **5e.** Migrate the `run-gui` function from the old code. The overall structure stays the same (MUV loop), but:
  - On **Expose** (code 12): call `(full-redraw layout)` instead of `(redraw)`
  - On **ConfigureNotify** (code 22): same as before, but call `(full-redraw layout)` after rebuild
  - On **MotionNotify** (code 6): update `*hovered-widget*`, then call `(smart-redraw layout)` instead of `(redraw)`
  - On **ButtonPress** (code 4): update `*pressed-widget*`/`*focused-widget*`, then call `(smart-redraw layout)`
  - On **ButtonRelease** (code 5): dispatch message, rebuild-layout if needed, then `(full-redraw layout)` if layout changed, otherwise `(smart-redraw layout)`
  - On **KeyPress** (code 2): same logic as before, using `(smart-redraw layout)` for focus changes and `(full-redraw layout)` for text edits that rebuild layout

### Validation

```bash
sbcl --load generate.lisp
grep "with-buffered-output\|smart-redraw\|partial-redraw\|full-redraw" source/event-loop.lisp
# Should find all 4
grep "save-visual-state\|compute-dirty" source/event-loop.lisp
# Should find both
```

---

## Task 6: Update Example and Tests

### Status: `[ ]`

### What to do

Update the example app and tests to work with the new API (new GC names, hbox/vbox layout).

### Steps

- `[ ]` **6a.** Update [06_example_template.lisp](file:///workspace/src/cl-cl-generator/example/07_pure_x11/06_example_template.lisp) (renamed from `04_example_template.lisp`). Change the `view` function to use `vbox`/`hbox` containers with `:glue` properties instead of absolute positioning. Refer to the example in [plan/04/implementation_plan.md](file:///workspace/src/cl-cl-generator/example/07_pure_x11/plan/04/implementation_plan.md) under "Example and Tests". The `update` function stays the same since MUV is unchanged.

- `[ ]` **6b.** Update [07_tests_template.lisp](file:///workspace/src/cl-cl-generator/example/07_pure_x11/07_tests_template.lisp) (renamed from `05_tests_template.lisp`). Add these test functions:

  - `test-widget-registry`: Register a mock renderer, call `render-widget`, verify it dispatches correctly
  - `test-glue-solver`: Test `solve-glue` with known inputs:
    - Three items with natural=100, stretch=1: available=300 → each gets 100
    - Three items with natural=100, stretch=1: available=600 → each gets 200
    - Two items, stretch=1 and stretch=2: available=300, natural=100 each → sizes 133 and 167
    - Shrinking case: natural=200 each, shrink=1 each, available=300 → 150 each
  - `test-bevel-coordinates`: This is a code-review test — verify that `draw-bevel` with a known rect doesn't error (can't easily test pixel output without X server)

  Keep ALL existing tests (`test-parse-node`, `test-collect-focusable`, `test-hit-testing`, `test-cone-focus-search`). Update them if any internal function signatures changed.

  Update `run-all-tests` to call the new test functions too.

- `[ ]` **6c.** Update the references in tests from `*gc*`/`*gc2*` if any exist (check the old test code — the current tests don't reference GCs directly, but verify).

### Validation

```bash
sbcl --load generate.lisp
# Run tests (these don't need an X server since they test pure logic):
sbcl --eval '(push "/workspace/src/cl-cl-generator/example/07_pure_x11/source/" asdf:*central-registry*)' \
     --eval '(ql:quickload :pure-x11-gen)' \
     --eval '(pure-x11-gen/tests:run-all-tests)' \
     --eval '(sb-ext:exit)'
# Should print "ALL TESTS PASSED!"
```

---

## Task 7: Final Integration and Cleanup

### Status: `[ ]`

### What to do

Final integration, cleanup, and verification that everything generates and loads correctly.

### Steps

- `[ ]` **7a.** Delete the old `03_widgets_template.lisp` (after confirming all content has been migrated to the three new files).
- `[ ]` **7b.** Run the full generator: `sbcl --load generate.lisp`
- `[ ]` **7c.** Verify all generated files exist in `source/`:
  - `package.lisp`
  - `pure-x11-gen.asd`
  - `x11-core.lisp`
  - `widgets-core.lisp`
  - `widgets-builtin.lisp`
  - `event-loop.lisp`
  - `example.lisp`
  - `tests.lisp`
- `[ ]` **7d.** Verify the ASDF system loads without errors:
  ```bash
  sbcl --eval '(push "source/" asdf:*central-registry*)' \
       --eval '(ql:quickload :pure-x11-gen)' \
       --eval '(format t "LOAD OK~%")' \
       --eval '(sb-ext:exit)'
  ```
- `[ ]` **7e.** Run tests: `(pure-x11-gen/tests:run-all-tests)` — all must pass.
- `[ ]` **7f.** If an X server is available (Xvfb or real), run the example to visually verify beveled widgets:
  ```bash
  Xvfb :99 -screen 0 800x600x24 &
  DISPLAY=:99 sbcl --eval '(push "source/" asdf:*central-registry*)' \
                    --eval '(ql:quickload :pure-x11-gen)' \
                    --eval '(pure-x11-gen/example:run-x11-example)'
  ```
- `[ ]` **7g.** Update [README.md](file:///workspace/src/cl-cl-generator/example/07_pure_x11/README.md) to document:
  - The new GC system (5 GCs, Xaw3d color scheme)
  - The widget registry and how to add custom widgets via `register-widget`
  - The buffered output system (`with-buffered-output`)
  - The TeX-style glue layout model (hbox/vbox + glue structs)
  - Network best practices (avoid synchronous calls in event loop)

### Validation

All previous task validations pass, plus:
```bash
# Full end-to-end:
cd /workspace/src/cl-cl-generator/example/07_pure_x11
sbcl --load generate.lisp
ls -la source/*.lisp | wc -l
# Should be 8 files
sbcl --eval '(push "/workspace/src/cl-cl-generator/example/07_pure_x11/source/" asdf:*central-registry*)' \
     --eval '(ql:quickload :pure-x11-gen)' \
     --eval '(pure-x11-gen/tests:run-all-tests)' \
     --eval '(sb-ext:exit)'
# Must print "ALL TESTS PASSED!"
```
