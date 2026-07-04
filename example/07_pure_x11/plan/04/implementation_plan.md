# Maintainable X11 Widget Library with Athena-Style Bevels

## Design Review of Current `07_pure_x11`

### What Works Well
- **MUV (Elm) architecture** — clean unidirectional data flow via pure `update` + `view` functions
- **Declarative layout S-expressions** — widget trees expressed as nested lists
- **Code generation via `cl-cl-generator`** — request/event functions are generated from declarative tables, eliminating manual binary serialization boilerplate
- **Single top-level X11 window** — avoids per-widget subwindows, reducing server resource usage
- **Client-side hit testing** — `find-widget-at` resolves clicks locally without server round trips
- **Server-side font rendering** — `ImageText8` sends only a few bytes; the X server renders the glyphs on GPU/display hardware

### Problems to Address

#### 1. Round-Trip Violations
- **`get-keyboard-mapping`** is called during `run-gui` initialization — this is fine (one-time setup), but currently the only sync call
- **`query-pointer`** exists in the API and could tempt users into calling it during the event loop, adding latency. The library should steer users toward extracting coordinates from event payloads instead
- **`big-requests-enable`** calls `query-extension` synchronously on every connect — acceptable for setup, but should be documented clearly

#### 2. Packet Batching / Request Coalescing
Currently, every drawing call (`poly-fill-rectangle`, `poly-rectangle`, `imagetext8`, `draw-line-segment-gc2`) immediately flushes to the socket via `force-output`. Over a network, a single button rendering generates **4-5 separate TCP writes**. This dramatically inflates round-trip overhead.

**Solution**: Buffer all drawing operations during `render-layout`, then issue a single `force-output` at the end. The `with-packet` macro should append to a request buffer instead of flushing immediately, and the event loop should flush explicitly at frame boundaries.

#### 3. Rendering Inefficiency — Full Redraws
Every `MotionNotify` (mouse hover) triggers `clear-area` + full `render-layout`. Over a network, this floods the connection with redundant drawing commands.

**Solution**: Dirty-region tracking — only redraw widgets whose visual state actually changed (hover entered/exited, press/release, value change).

#### 4. Widget Rendering Is a Monolithic `cond` Chain
The `render-layout` function is a single 80-line `cond` that string-compares widget type names. Adding a new widget type means editing deep inside this function.

**Solution**: A widget-type registry — a dispatch table mapping type keywords to render/hit-test/measure functions. New widgets register themselves without modifying existing code.

#### 5. Bevel Drawing Is Incomplete
The current button bevel draws 1px white top/left + 1px black bottom/right. This doesn't match the classic Xaw3d look, which uses **2px bevels** with a light/shadow pair and distinct "raised" vs "sunken" states.

#### 6. Missing GC for Mid-Tone (Shadow)
Athena/Xaw3d uses **three tones**: a light highlight (white or near-white), the widget face color (mid-gray), and a dark shadow (dark gray or black). The current code only has `*gc*` (white foreground) and `*gc2*` (black foreground). A third GC for the shadow tone is needed.

#### 7. No Buffered/Deferred Flush Strategy
The `with-packet` macro calls `write-sequence` + `force-output` on every single request. For network operation, we need:
- **Immediate mode** for interactive queries (setup phase)
- **Buffered mode** for batched rendering (draw phase)

---

## Proposed Changes

### Component 1: Request Buffering Layer

#### [MODIFY] [02_x11_spec.lisp](file:///workspace/src/cl-cl-generator/example/07_pure_x11/02_x11_spec.lisp)

No spec changes needed — the packet specifications remain the same.

#### [MODIFY] [generate.lisp](file:///workspace/src/cl-cl-generator/example/07_pure_x11/generate.lisp)

Modify the `with-packet` macro to support two modes:

1. **When `*buffered-mode*` is nil** (default, for setup/queries): behaves as today — writes directly and flushes
2. **When `*buffered-mode*` is t** (during rendering): appends the byte vector to `*packet-buffer*` without flushing

Add `(flush-packets)` — writes the accumulated buffer to the socket in one `write-sequence` + `force-output` call.

Add `(with-buffered-output &body body)` — binds `*buffered-mode*` to t, executes body, then calls `flush-packets`.

This is a **transparent** change: existing code that doesn't use `with-buffered-output` works identically.

---

### Component 2: Widget Type Registry

#### [MODIFY] [03_widgets_template.lisp](file:///workspace/src/cl-cl-generator/example/07_pure_x11/03_widgets_template.lisp)

Replace the monolithic `cond` chain in `render-layout` with a registry-based dispatch:

```lisp
(defvar *widget-renderers* (make-hash-table :test 'equal))

(defun register-widget (type-name render-fn)
  (setf (gethash type-name *widget-renderers*) render-fn))

(defun render-widget (w-struct focused pressed hovered)
  (let* ((type (widget-type w-struct))
         (type-name (and type (symbolp type) (string-upcase (symbol-name type))))
         (renderer (gethash type-name *widget-renderers*)))
    (when renderer
      (funcall renderer w-struct focused pressed hovered))))
```

Each widget type (panel, label, button, checkbox, text-input) becomes a separate `register-widget` call with a self-contained rendering function. Users can add custom widgets by calling `register-widget` without modifying library code.

---

### Component 3: Athena/Xaw3d-Style Bevel Drawing

#### [MODIFY] [generate.lisp](file:///workspace/src/cl-cl-generator/example/07_pure_x11/generate.lisp) — GC creation

Add a **third GC** (`*gc-shadow*`) with a dark-gray foreground (e.g., `#x00808080` or `#x00606060`) to complement:
- `*gc*` — light highlight (white `#x00ffffff`)
- `*gc2*` — widget face / text (black `#x00000000`)
- `*gc-shadow*` — dark shadow

#### [MODIFY] [03_widgets_template.lisp](file:///workspace/src/cl-cl-generator/example/07_pure_x11/03_widgets_template.lisp) — Bevel helpers

Add bevel-drawing primitives:

```lisp
(defun draw-bevel (x y w h &key (style :raised) (width 2))
  "Draw Xaw3d-style 3D bevel around rectangle.
   :raised = light top-left, shadow bottom-right (default button state)
   :sunken = shadow top-left, light bottom-right (pressed button state)"
  ...)
```

The bevel uses 2px width by default:
- **Raised**: outer top/left = white, inner top/left = light-gray; outer bottom/right = black, inner bottom/right = dark-gray
- **Sunken**: reversed

Widget renderers call `draw-bevel` instead of hand-coding line segments.

---

### Component 4: Dirty-Region Rendering

#### [MODIFY] [03_widgets_template.lisp](file:///workspace/src/cl-cl-generator/example/07_pure_x11/03_widgets_template.lisp) — Event loop

Instead of full `clear-area` + `render-layout` on every hover change:

1. Track `*previous-hovered*`, `*previous-pressed*`, `*previous-focused*`
2. On state change, compute the set of widgets whose visual state changed
3. Use `clear-area` with the widget's bounding box, then re-render only that widget
4. Fall back to full redraw for Expose events and layout rebuilds

This reduces network traffic from O(all-widgets) to O(changed-widgets) per interaction.

---

### Component 5: API Documentation & Network Usage Guidance

#### [MODIFY] [README.md](file:///workspace/src/cl-cl-generator/example/07_pure_x11/README.md)

Add a "Network Best Practices" section:
- Document which functions are synchronous (round-trip) vs. asynchronous (one-way)
- Explain that `query-pointer` should NOT be called in the event loop (use MotionNotify event data instead)
- Document the buffered output mode and how to use `with-buffered-output`
- Explain the bevel system and how to register custom widgets

---

## User Review Required

> [!IMPORTANT]
> **GC color choice**: The third GC shadow color needs to be chosen. Xaw3d typically uses a computed 70% brightness of the widget face. Since we're using core X11 allocations (not a TrueColor visual), I propose `#x00808080` (medium gray) for shadow. Does this match your aesthetic intent, or do you want a different value?

> [!IMPORTANT]  
> **Bevel width**: Classic Xaw3d uses 2px bevels. Some variants use 1px. Do you want 2px (chunkier, more recognizable Athena look) or 1px (subtler)?

> [!IMPORTANT]
> **Scope of first iteration**: This plan covers buffering, widget registry, bevel drawing, and dirty-region optimization. Should we implement all four in one pass, or would you prefer to start with just the bevel aesthetics + widget registry and add the buffering/dirty-region optimizations as a follow-up?

## Open Questions

> [!NOTE]
> **Additional widget types**: Beyond the current set (panel, label, button, checkbox, text-input), are there other Athena widgets you want in the initial version? Classic Xaw3d includes: scrollbar, menubar, dialog box, toggle button, radio button, list selector, and viewport (scrollable container).

> [!NOTE]
> **Color allocation strategy**: The current approach uses hardcoded pixel values (`#x00ffffff`, `#x00000000`). For proper Athena-style theming, we could add a small color-allocation function that queries the server's default colormap once at connect time. This adds one round trip at startup but enables proper color matching on non-TrueColor displays. Is this worth doing, or can we assume TrueColor (24-bit) visuals?

---

## Verification Plan

### Automated Tests
- Extend [tests.lisp](file:///workspace/src/cl-cl-generator/example/07_pure_x11/source/tests.lisp) with:
  - Widget registry dispatch tests (register + render-widget)
  - Bevel geometry tests (correct line coordinates for raised/sunken at various sizes)
  - Buffered output tests (verify packet accumulation and flush)
- Run via: `sbcl --load generate.lisp --eval '(ql:quickload :pure-x11-gen)' --eval '(pure-x11-gen/tests:run-all-tests)'`

### Manual Verification
- Run the example GUI under Xvfb and take a screenshot to verify beveled appearance
- Run over SSH X11 forwarding to verify reduced latency (qualitative comparison of responsiveness)
