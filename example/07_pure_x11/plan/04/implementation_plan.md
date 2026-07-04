# Phase 1: Athena-Style X11 Widget Library

## Design Decisions (Resolved)

| Decision | Choice |
|---|---|
| Primary target | Remote display via SSH X11 forwarding (10-100ms RTT) |
| Bevel width | 2px classic Xaw3d |
| Color palette | Face `#c0c0c0`, light `#ffffff`, shadow `#808080`, dark `#404040` |
| Color allocation | Hardcoded TrueColor pixel values (zero round trips) |
| Text rendering | X11 core fonts only (server-side) |
| Widget dispatch | Hash-table registry with `register-widget` |
| Request buffering | Single byte buffer, one `write-sequence` + `force-output` per frame |
| Dirty tracking | Widget-level dirty flags, partial redraw |
| Layout engine | TeX-style glue (natural/stretch/shrink) with hbox/vbox |
| Scrolling | Server-side clip rectangles via `SetClipRectangles` |
| Popup menus | Overlay rendering in main window (save/restore underneath) |
| Event model | MUV (Elm architecture) retained |
| Code generation | X11 protocol from spec tables, widgets as S-expression templates |
| File organization | Split by concern: core, builtin widgets, event loop |

## Phase 1 Scope

Infrastructure + 5 existing widget types with proper Athena bevels:
- **Panel** (container with beveled border and gray fill)
- **Label** (text drawn with core font)
- **Button** (raised bevel, sunken on press)
- **Checkbox** (beveled indicator box with check mark)
- **Text-input** (sunken field with cursor)

> [!NOTE]
> Future phases will add: scrollbar, radio button, menu bar, list box, separator, viewport, and full TeX glue layout. Phase 1 introduces the hbox/vbox containers and glue solver so the infrastructure is ready.

---

## Proposed Changes

### X11 Protocol Layer

#### [MODIFY] [02_x11_spec.lisp](file:///workspace/src/cl-cl-generator/example/07_pure_x11/02_x11_spec.lisp)

Add these request specifications to `*x11-requests*`:

1. **ChangeGC** (opcode 56) — needed to switch foreground colors on existing GCs for bevel drawing
2. **SetClipRectangles** (opcode 59) — needed for scrollable viewport clipping (infrastructure for Phase 2+)
3. **CreateGC** (standalone, opcode 55) — currently inlined in `make-window`; extract to its own function so we can create the 4 GCs independently

#### [MODIFY] [generate.lisp](file:///workspace/src/cl-cl-generator/example/07_pure_x11/generate.lisp)

**Buffered output infrastructure:**

Replace the `with-packet` macro with a dual-mode version:

```lisp
(defvar *packet-buffer* nil)  ;; when non-nil, accumulate instead of flushing

(defmacro with-packet (&body body)
  ;; Builds byte vector as before, but:
  ;; - If *packet-buffer* is non-nil: push bytes onto it
  ;; - If *packet-buffer* is nil: write directly to *s* and force-output
  ...)

(defun flush-packets ()
  "Write accumulated packet buffer to socket in one write-sequence call."
  (when *packet-buffer*
    (let ((buf (coerce-to-byte-vector (nreverse *packet-buffer*))))
      (write-sequence buf *s*)
      (force-output *s*)
      (setf *packet-buffer* nil))))

(defmacro with-buffered-output (&body body)
  "Execute body with request buffering enabled. Flushes on exit."
  `(let ((*packet-buffer* nil))
     (setf *packet-buffer* (list))
     (unwind-protect (progn ,@body)
       (flush-packets))))
```

**GC creation — 4 GCs:**

Modify the `make-window` request to create 4 GCs:

| GC | Variable | Foreground | Purpose |
|---|---|---|---|
| 1 | `*gc-light*` | `#ffffff` | Bevel highlight (top-left of raised widgets) |
| 2 | `*gc-face*` | `#c0c0c0` | Widget face fill, text background |
| 3 | `*gc-shadow*` | `#808080` | Bevel shadow (bottom-right inner) |
| 4 | `*gc-dark*` | `#404040` | Bevel dark edge (bottom-right outer) |

The old `*gc*` (white) and `*gc2*` (black) are replaced by these 4 named GCs. A 5th GC for black text (`*gc-text*` with foreground `#000000`) is also needed.

Update the package exports accordingly.

---

### Widget Core (New File)

#### [NEW] [03_widgets_core.lisp](file:///workspace/src/cl-cl-generator/example/07_pure_x11/03_widgets_core.lisp)

This file contains the foundational widget infrastructure:

**1. Widget struct and parsing** (moved from current `03_widgets_template.lisp`):
- `defstruct widget` — unchanged
- `parse-node` — unchanged
- `collect-focusable-widgets` — unchanged
- `find-widget-at` — unchanged
- `find-widget-by-name` — unchanged
- `find-nearest-widget` — unchanged
- `translate-keycode` — unchanged

**2. Widget type registry:**

```lisp
(defvar *widget-renderers* (make-hash-table :test 'equal))

(defun register-widget (type-name render-fn)
  "Register a renderer function for a widget type.
   RENDER-FN receives (widget-struct focused-name pressed-name hovered-name)."
  (setf (gethash (string-upcase (string type-name)) *widget-renderers*) render-fn))

(defun render-widget (w-struct focused pressed hovered)
  "Dispatch to the registered renderer for this widget type."
  (let* ((type (widget-type w-struct))
         (type-name (and type (symbolp type) (string-upcase (symbol-name type))))
         (renderer (gethash type-name *widget-renderers*)))
    (if renderer
        (funcall renderer w-struct focused pressed hovered)
        (warn "No renderer registered for widget type ~a" type-name))))

(defun render-layout (layout focused pressed hovered)
  "Walk the layout tree and render each widget via the registry."
  (labels ((render-node (node)
             (when (listp node)
               (let ((w-struct (parse-node node)))
                 (render-widget w-struct focused pressed hovered)
                 (dolist (child (widget-children w-struct))
                   (render-node child))))))
    (render-node layout)))
```

**3. Bevel drawing primitives:**

```lisp
(defun draw-bevel (x y w h &key (style :raised) (bevel-width 2))
  "Draw Xaw3d-style 3D bevel.
   :raised — light on top/left, shadow on bottom/right (normal button)
   :sunken — shadow on top/left, light on bottom/right (pressed button, text field)"
  (let ((top-gc    (if (eq style :raised) *gc-light* *gc-dark*))
        (bottom-gc (if (eq style :raised) *gc-dark*  *gc-light*))
        (top-inner-gc    (if (eq style :raised) *gc-face*   *gc-shadow*))
        (bottom-inner-gc (if (eq style :raised) *gc-shadow* *gc-face*)))
    ;; Outer bevel (first pixel)
    ;; Top edge
    (draw-line x y (+ x w -1) y :gc top-gc)
    ;; Left edge  
    (draw-line x y x (+ y h -1) :gc top-gc)
    ;; Bottom edge
    (draw-line x (+ y h -1) (+ x w -1) (+ y h -1) :gc bottom-gc)
    ;; Right edge
    (draw-line (+ x w -1) y (+ x w -1) (+ y h -1) :gc bottom-gc)
    (when (>= bevel-width 2)
      ;; Inner bevel (second pixel)
      (draw-line (1+ x) (1+ y) (+ x w -2) (1+ y) :gc top-inner-gc)
      (draw-line (1+ x) (1+ y) (1+ x) (+ y h -2) :gc top-inner-gc)
      (draw-line (1+ x) (+ y h -2) (+ x w -2) (+ y h -2) :gc bottom-inner-gc)
      (draw-line (+ x w -2) (1+ y) (+ x w -2) (+ y h -2) :gc bottom-inner-gc))))
```

**4. TeX-style glue layout solver:**

```lisp
(defstruct glue
  natural    ;; natural (preferred) size in pixels
  stretch    ;; stretchability (how much it can grow, 0 = rigid)
  shrink)    ;; shrinkability (how much it can shrink, 0 = rigid)

(defun solve-glue (items available-space)
  "Distribute available-space among a list of glue items.
   Returns a list of computed sizes (one per item).
   Uses TeX's algorithm: compute total natural, distribute excess
   proportional to stretch (or deficit proportional to shrink)."
  (let* ((total-natural (reduce #'+ items :key #'glue-natural))
         (excess (- available-space total-natural)))
    (cond
      ((>= excess 0)
       ;; Stretching: distribute excess proportional to stretch factors
       (let ((total-stretch (reduce #'+ items :key #'glue-stretch)))
         (if (zerop total-stretch)
             (mapcar #'glue-natural items)
             (mapcar (lambda (g)
                       (+ (glue-natural g)
                          (round (* excess (/ (glue-stretch g) total-stretch)))))
                     items))))
      (t
       ;; Shrinking: distribute deficit proportional to shrink factors
       (let ((total-shrink (reduce #'+ items :key #'glue-shrink)))
         (if (zerop total-shrink)
             (mapcar #'glue-natural items)
             (mapcar (lambda (g)
                       (max 0 (+ (glue-natural g)
                                 (round (* excess (/ (glue-shrink g) total-shrink))))))
                     items)))))))
```

Container widgets (`hbox`, `vbox`) will call `solve-glue` on their children's glue specs during layout computation, then assign absolute positions before rendering.

---

### Built-in Widget Renderers (New File)

#### [NEW] [04_widgets_builtin.lisp](file:///workspace/src/cl-cl-generator/example/07_pure_x11/04_widgets_builtin.lisp)

Each widget type is a self-contained `register-widget` call:

**Panel** — fills face-colored rectangle, draws optional raised bevel border, renders children.

**Label** — draws text at position using `*gc-text*`.

**Button** — fills face color, draws 2px raised bevel (sunken when pressed), centers text. On hover, could optionally draw a highlight border (subtle Xaw3d touch).

**Checkbox** — draws a small sunken-beveled square (indicator), fills with face color when unchecked, draws "X" or checkmark when checked. Label text to the right.

**Text-input** — draws sunken-beveled rectangle (2px), white fill inside, text rendered with `*gc-text*`, blinking cursor line when focused.

Each renderer only draws its own widget — the `render-layout` walker in core handles tree traversal and child recursion.

---

### Event Loop (New File)

#### [NEW] [05_event_loop.lisp](file:///workspace/src/cl-cl-generator/example/07_pure_x11/05_event_loop.lisp)

Extracted from the current `03_widgets_template.lisp`. Key changes:

**1. Dirty tracking:**

```lisp
(defvar *prev-focused* nil)
(defvar *prev-pressed* nil)
(defvar *prev-hovered* nil)

(defun compute-dirty-widgets (layout)
  "Return list of widget names whose visual state changed."
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
```

**2. Partial redraw:**

```lisp
(defun redraw-dirty (layout dirty-names)
  "Clear and re-render only the widgets in dirty-names."
  (with-buffered-output
    (dolist (name dirty-names)
      (let ((w (find-widget-by-name layout name)))
        (when w
          (clear-area :x (widget-x w) :y (widget-y w)
                      :w (widget-w w) :h (widget-h w))
          (render-widget w *focused-widget* *pressed-widget* *hovered-widget*))))))
```

**3. Full redraw (for Expose / layout rebuild):**

```lisp
(defun full-redraw (layout)
  (with-buffered-output
    (clear-area :w *window-width* :h *window-height*)
    (render-layout layout *focused-widget* *pressed-widget* *hovered-widget*)))
```

**4. Event loop** — same structure as current, but uses `redraw-dirty` for hover/press/focus changes and `full-redraw` for Expose/resize.

---

### Example and Tests (Renumbered)

#### [MODIFY] [06_example_template.lisp](file:///workspace/src/cl-cl-generator/example/07_pure_x11/06_example_template.lisp) (was 04)

Update the example to use `hbox`/`vbox` layout containers instead of absolute coordinates:

```lisp
(defun view (w h state)
  `(vbox :name :root :x 0 :y 0 :w ,w :h ,h :padding 10
     (label :name :title :text "Athena-Style GUI Demo"
            :glue (:natural 20 :stretch 0 :shrink 0))
     (hbox :name :buttons :glue (:natural 30 :stretch 0 :shrink 0) :spacing 10
       (button :name :btn-inc :text "Increment" :msg (:increment)
               :glue (:natural 120 :stretch 1 :shrink 0))
       (button :name :btn-dec :text "Decrement" :msg (:decrement)
               :glue (:natural 120 :stretch 1 :shrink 0)))
     (text-input :name :txt :text ,(app-state-input-buffer state)
                 :cursor-pos ,(app-state-cursor-pos state)
                 :msg-change (:text-change)
                 :glue (:natural 30 :stretch 1 :shrink 0))
     (checkbox :name :chk :label "Enable Action Mode"
               :checked-p ,(app-state-checkbox-val state)
               :msg (:toggle-checkbox)
               :glue (:natural 24 :stretch 0 :shrink 0))))
```

#### [MODIFY] [07_tests_template.lisp](file:///workspace/src/cl-cl-generator/example/07_pure_x11/07_tests_template.lisp) (was 05)

Add tests for:
- Widget registry dispatch (register + render)
- Bevel coordinate geometry (raised and sunken at different sizes)
- TeX glue solver (stretching, shrinking, rigid items)
- Dirty widget computation (state transitions)
- Existing tests preserved

---

### Generator Orchestrator

#### [MODIFY] [generate.lisp](file:///workspace/src/cl-cl-generator/example/07_pure_x11/generate.lisp)

Update to load and emit the new file structure:

```lisp
(load "01_package.lisp")
(load "02_x11_spec.lisp")
(load "03_widgets_core.lisp")
(load "04_widgets_builtin.lisp")
(load "05_event_loop.lisp")
(load "06_example_template.lisp")
(load "07_tests_template.lisp")
```

Update `package.lisp` exports to include:
- `*gc-light*`, `*gc-face*`, `*gc-shadow*`, `*gc-dark*`, `*gc-text*`
- `register-widget`, `draw-bevel`
- `with-buffered-output`, `flush-packets`
- `make-glue`, `solve-glue`
- `hbox`, `vbox` container types

---

## Verification Plan

### Automated Tests
```bash
cd /workspace/src/cl-cl-generator/example/07_pure_x11
sbcl --load generate.lisp
# Then in a separate SBCL:
sbcl --eval '(push "/workspace/src/cl-cl-generator/example/07_pure_x11/source/" asdf:*central-registry*)' \
     --eval '(ql:quickload :pure-x11-gen)' \
     --eval '(pure-x11-gen/tests:run-all-tests)' \
     --eval '(sb-ext:exit)'
```

### Visual Verification
```bash
# Run under Xvfb and take screenshot
./run-xvfb-test.sh
```

### Network Verification
- Run example over SSH X11 forwarding
- Compare responsiveness vs. current implementation (qualitative)
