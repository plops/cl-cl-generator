# Phase 5: 2D Diagram Canvas & Trajectory Animation

This plan outlines how to extend the pure-Lisp socket-based X11 client library to support 2D diagram visualization, a shapes canvas, periodic animation frames, and low-latency network optimization.

---

## 1. Finalized Design Decisions (Resolved via Interview)

| Feature | Decision Choice | Rationale |
| :--- | :--- | :--- |
| **Animation Rate** | 20 FPS (50ms tick interval) | Optimal balance between smooth visual updates and low socket/network traffic. |
| **GUI Controls** | Play/Pause button, Reset button, and Status text | Provides complete user control to start, stop, reset, and monitor the orbit transfer. |
| **Custom Colors** | Allocate 4 new GCs: `*gc-sun*` (yellow), `*gc-earth*` (blue), `*gc-mars*` (red), `*gc-spacecraft*` (green) | Delivers a premium, color-coded visual design rather than relying on shades of gray. |
| **Grid Lines** | Draw a subtle background grid at tick positions | Helps visually align coordinate positions of the planets and the spacecraft. |
| **World Bounds** | X and Y ranges set to `[-1.8, 1.8]` | Comfortably fits Mars' orbit (1.524 AU radius) with a clean visual margin. |

---

## 2. Proposed Changes

### A. Protocol Layer Spec & Package Exports

#### [MODIFY] `02_x11_spec.lisp`
Add the following opcode specifications inside `*x11-requests*` to support drawing outline and filled circles/ellipses:

```lisp
    ;; 9d. PolyArc (opcode 68)
    (:name poly-arc
     :doc "Draw outlines of one or more arcs."
     :params (arcs &key (gc *gc-text*))
     :packet ((card8 68)
              (card8 0)
              (card16 (+ 3 (* 3 (length arcs))))
              (card32 *window*)
              (card32 gc)
              (dolist (a arcs)
                (dolist (v a)
                  (card16 v)))))

    ;; 9e. PolyFillArc (opcode 71)
    (:name poly-fill-arc
     :doc "Draw one or more filled arcs."
     :params (arcs &key (gc *gc-text*))
     :packet ((card8 71)
              (card8 0)
              (card16 (+ 3 (* 3 (length arcs))))
              (card32 *window*)
              (card32 gc)
              (dolist (a arcs)
                (dolist (v a)
                  (card16 v)))))
```

Also, modify `make-window` to allocate and initialize **4 custom color GCs**:
```lisp
      :bindings ((window (logior *resource-id-base* (logand *resource-id-mask* 1)))
                 (gc-light (logior *resource-id-base* (logand *resource-id-mask* 2)))
                 (gc-face (logior *resource-id-base* (logand *resource-id-mask* 3)))
                 (gc-shadow (logior *resource-id-base* (logand *resource-id-mask* 4)))
                 (gc-dark (logior *resource-id-base* (logand *resource-id-mask* 5)))
                 (gc-text (logior *resource-id-base* (logand *resource-id-mask* 6)))
                 (gc-sun (logior *resource-id-base* (logand *resource-id-mask* 7)))
                 (gc-earth (logior *resource-id-base* (logand *resource-id-mask* 8)))
                 (gc-mars (logior *resource-id-base* (logand *resource-id-mask* 9)))
                 (gc-spacecraft (logior *resource-id-base* (logand *resource-id-mask* 10)))
                 ...)
      :post ((defparameter *window* window)
             (defparameter *gc-light* gc-light)
             (defparameter *gc-face* gc-face)
             (defparameter *gc-shadow* gc-shadow)
             (defparameter *gc-dark* gc-dark)
             (defparameter *gc-text* gc-text)
             (defparameter *gc-sun* gc-sun)
             (defparameter *gc-earth* gc-earth)
             (defparameter *gc-mars* gc-mars)
             (defparameter *gc-spacecraft* gc-spacecraft))
```
Add the `create-gc` opcodes for them:
- `gc-sun`: `#x00ffcc00` (Yellow/Orange)
- `gc-earth`: `#x003399ff` (Blue)
- `gc-mars`: `#x00ff3300` (Red)
- `gc-spacecraft`: `#x0033cc33` (Green)

#### [MODIFY] `generate.lisp`
Update the `package.lisp` generation template to export the new GCs and functions:
* `#:poly-arc`
* `#:poly-fill-arc`
* `#:read-reply-timeout`
* `#:*gc-sun*`
* `#:*gc-earth*`
* `#:*gc-mars*`
* `#:*gc-spacecraft*`

And add the timeout-aware socket-reading function to the generated `x11-core.lisp` section:

```lisp
(defun read-reply-timeout (timeout-sec)
  "Wait up to TIMEOUT-SEC seconds for input on *s*. Returns the packet buffer if read, or NIL on timeout."
  (when *s*
    (let ((fd (sb-sys:fd-stream-fd *s*)))
      (if (sb-sys:wait-until-fd-usable fd :input timeout-sec)
          (read-reply-wait)
          nil))))
```

---

### B. Canvas Widget Registration

#### [MODIFY] `04_widgets_builtin.lisp`
Add the grid and shapes drawing code under `"CANVAS"` widget:

```lisp
     (defun power-of-ten-nice-spacing (val)
       "Find a nice tick spacing close to val (e.g. 0.1, 0.2, 0.5, 1.0, 2.0, 5.0...)."
       (if (<= val 0)
           1.0
           (let* ((pow (floor (log val 10)))
                  (base (expt 10.0 pow))
                  (ratio (/ val base)))
             (cond
               ((< ratio 1.5) base)
               ((< ratio 3.0) (* 2.0 base))
               ((< ratio 7.5) (* 5.0 base))
               (t (* 10.0 base))))))

     (register-widget "CANVAS"
       (lambda (w-struct focused pressed hovered)
         (let ((x (widget-x w-struct))
               (y (widget-y w-struct))
               (w (widget-w w-struct))
               (h (widget-h w-struct))
               (props (widget-props w-struct)))
           ;; Draw background and sunken frame
           (poly-fill-rectangle (list (list x y w h)) :gc *gc-light*)
           (draw-bevel x y w h :style :sunken)
           
           (let ((xmin (getf props :xmin -1.8))
                 (xmax (getf props :xmax 1.8))
                 (ymin (getf props :ymin -1.8))
                 (ymax (getf props :ymax 1.8))
                 (shapes (getf props :shapes nil))
                 (draw-axes-p (getf props :draw-axes-p t)))
             (labels ((to-screen-x (wx)
                        (+ x (round (* w (/ (- wx xmin) (- xmax xmin))))))
                      (to-screen-y (wy)
                        (+ y h -1 (round (* (- h) (/ (- wy ymin) (- ymax ymin))))))
                      (draw-world-line (x1 y1 x2 y2 &key (gc *gc-text*))
                        (draw-line (to-screen-x x1) (to-screen-y y1)
                                   (to-screen-x x2) (to-screen-y y2)
                                   :gc gc))
                      (draw-world-circle (cx cy r &key (gc *gc-text*) fill-p)
                        (let* ((sx1 (to-screen-x (- cx r)))
                               (sy1 (to-screen-y (+ cy r)))
                               (sx2 (to-screen-x (+ cx r)))
                               (sy2 (to-screen-y (- cy r)))
                               (sw (- sx2 sx1))
                               (sh (- sy2 sy1)))
                          (if fill-p
                              (poly-fill-arc (list (list sx1 sy1 sw h-val 0 23040)) :gc gc) ; sw=sh for circle
                              (poly-arc (list (list sx1 sy1 sw sh 0 23040)) :gc gc)))))
               (declare (ignorable #'draw-world-line #'draw-world-circle))
               
               (let ((x-axis-y (if (<= ymin 0 ymax) 0.0 ymin))
                     (y-axis-x (if (<= xmin 0 xmax) 0.0 xmin)))
                 ;; 1. Draw Grid Lines (subtle crosshairs)
                 (let* ((x-range (- xmax xmin))
                        (x-spacing (power-of-ten-nice-spacing (/ x-range 8)))
                        (start-x-tick (* (ceiling (/ xmin x-spacing)) x-spacing)))
                   (loop for tx = start-x-tick then (+ tx x-spacing)
                         while (<= tx xmax) do
                         (let ((tsx (to-screen-x tx)))
                           (draw-line tsx (+ y 2) tsx (+ y h -2) :gc *gc-face*)))) ; subtle vertical grid line
                 
                 (let* ((y-range (- ymax ymin))
                        (y-spacing (power-of-ten-nice-spacing (/ y-range 8)))
                        (start-y-tick (* (ceiling (/ ymin y-spacing)) y-spacing)))
                   (loop for ty = start-y-tick then (+ ty y-spacing)
                         while (<= ty ymax) do
                         (let ((tsy (to-screen-y ty)))
                           (draw-line (+ x 2) tsy (+ x w -2) tsy :gc *gc-face*)))) ; subtle horizontal grid line
                 
                 ;; 2. Draw Solid Axes & Ticks
                 (when draw-axes-p
                   ;; Draw Axes
                   (draw-world-line xmin x-axis-y xmax x-axis-y :gc *gc-shadow*)
                   (draw-world-line y-axis-x ymin y-axis-x ymax :gc *gc-shadow*)
                   
                   ;; X-Axis Ticks
                   (let* ((x-range (- xmax xmin))
                          (tick-spacing (power-of-ten-nice-spacing (/ x-range 8)))
                          (start-tick (* (ceiling (/ xmin tick-spacing)) tick-spacing)))
                     (loop for tx = start-tick then (+ tx tick-spacing)
                           while (<= tx xmax) do
                           (let ((tsx (to-screen-x tx))
                                 (tsy (to-screen-y x-axis-y)))
                             (draw-line tsx (- tsy 4) tsx (+ tsy 4) :gc *gc-dark*)
                             (let ((lbl (format nil "~,2f" tx)))
                               (imagetext8 lbl :x (- tsx (* 3 (length lbl))) :y (+ tsy 14) :gc *gc-text*)))))
                   
                   ;; Y-Axis Ticks
                   (let* ((y-range (- ymax ymin))
                          (tick-spacing (power-of-ten-nice-spacing (/ y-range 8)))
                          (start-tick (* (ceiling (/ ymin tick-spacing)) tick-spacing)))
                     (loop for ty = start-tick then (+ ty tick-spacing)
                           while (<= ty ymax) do
                           (unless (= 0 (round ty))
                             (let ((tsx (to-screen-x y-axis-x))
                                   (tsy (to-screen-y ty)))
                               (draw-line (- tsx 4) tsy (+ tsx 4) tsy :gc *gc-dark*)
                               (let ((lbl (format nil "~,2f" ty)))
                                 (imagetext8 lbl :x (- tsx (* 6 (length lbl)) 6) :y (+ tsy 4) :gc *gc-text*)))))))))
               
               ;; 3. Draw Shapes
               (dolist (shape shapes)
                 (let ((type (car shape))
                       (args (cdr shape)))
                   (case type
                     (:line
                      (destructuring-bind (lx1 ly1 lx2 ly2 &key (color *gc-text*)) args
                        (draw-world-line lx1 ly1 lx2 ly2 :gc color)))
                     (:circle
                      (destructuring-bind (cx cy r &key (color *gc-text*)) args
                        (draw-world-circle cx cy r :gc color :fill-p nil)))
                     (:disk
                      (destructuring-bind (cx cy r &key (color *gc-text*)) args
                        (draw-world-circle cx cy r :gc color :fill-p t)))
                     (:text
                      (destructuring-bind (str tx ty &key (color *gc-text*)) args
                        (imagetext8 str :x (to-screen-x tx) :y (to-screen-y ty) :gc color)))
                     (:poly-line
                      (destructuring-bind (points &key (color *gc-text*)) args
                        (loop for (p1 p2) on points by #'cdr
                              while p2
                              do (draw-world-line (car p1) (cadr p1) (car p2) (cadr p2) :gc color)))))))))))))
```

---

### C. Timer Support in Event Loop

#### [MODIFY] `05_event_loop.lisp`
Modify the `run-gui` signature and inner loop to accept an optional `:tick-interval` parameter. 

If set, the event loop will wait up to `tick-interval` seconds. If no event arrives on the socket, it triggers the callback handler with the tick message.

```lisp
     (defun run-gui (update-fn view-fn initial-state &key (tick-interval nil) (tick-msg '(:tick)))
       ...
       (let ((state initial-state)
             (layout nil)
             ...)
         (labels ((rebuild-layout ()
                    (let ((raw-layout (funcall view-fn *window-width* *window-height* state)))
                      (setf layout (resolve-layout raw-layout 0 0 *window-width* *window-height*)))
                    ...))
           (rebuild-layout)
           (map-window win)
           (full-redraw layout)
           
           (let ((last-tick-time (get-internal-real-time)))
             (loop
               (let* ((reply nil)
                      (timed-out-p nil))
                 (cond
                   (*pending-events*
                    (setf reply (pop *pending-events*)))
                   (tick-interval
                    (let* ((now (get-internal-real-time))
                           (elapsed (/ (- now last-tick-time) internal-time-units-per-second))
                           (remaining (- tick-interval elapsed)))
                      (if (<= remaining 0)
                          (setf timed-out-p t)
                          (let ((buf (read-reply-timeout remaining)))
                            (if buf
                                (setf reply buf)
                                (setf timed-out-p t))))))
                   (t
                    (setf reply (read-reply-wait))))
                 
                 (cond
                   (timed-out-p
                    (setf last-tick-time (get-internal-real-time))
                    (setf state (funcall update-fn state tick-msg))
                    (rebuild-layout)
                    (full-redraw layout))
                   (reply
                    (let ((code (logand (aref reply 0) #x7f)))
                      (cond
                        ((= code 12) (full-redraw layout))
                        ;; ... handle other events as usual ...
                        )))))))))))
```

---

### D. Orbit & Transfer Trajectory Demo

#### [MODIFY] `06_example_template.lisp`
Change the application example template to simulate a Hohmann transfer trajectory from Earth to Mars.

1. **State:**
   * `time` (ticks elapsed)
   * `is-animating` (boolean indicating if the simulation is currently active)
2. **Physics Simulation details:**
   * Sun is at origin `(0, 0)`.
   * Earth Orbit: circular at radius $R_E = 1.0$ AU, period = 1 year.
   * Mars Orbit: circular at radius $R_M = 1.524$ AU, period = 1.88 years.
   * Spacecraft Transfer Orbit: elliptic transfer orbit (Hohmann ellipse) starting at Earth ($r_{peri} = 1.0$ AU) and ending at Mars ($r_{ap} = 1.524$ AU).
     * Semi-major axis $a = (1.0 + 1.524) / 2 = 1.262$ AU.
     * Eccentricity $e = 0.208$.
     * Focus is at $(0, 0)$.
     * Polar orbit curve: $r(\theta) = a(1 - e^2) / (1 + e \cos(\theta))$.
3. **MUV Components:**

```lisp
      (defstruct app-state
        (time 0.0)
        (animating-p t))

      (defun update (state msg)
        (case (car msg)
          (:tick
           (if (app-state-animating-p state)
               (let ((new-time (+ (app-state-time state) 0.02)))
                 ;; Reset loop at end of transfer trajectory (approx t = pi)
                 (if (> new-time 3.14159)
                     (make-app-state :time 0.0 :animating-p t)
                     (make-app-state :time new-time :animating-p t)))
               state))
          (:toggle-animation
           (make-app-state :time (app-state-time state)
                           :animating-p (not (app-state-animating-p state))))
          (:reset-animation
           (make-app-state :time 0.0
                           :animating-p t))
          (t state)))
```

The rendering `view` function returns:
* A `VBOX` containing title label, the control buttons, and the `CANVAS` widget showing the Sun, Earth, Mars, spacecraft, and orbits.

```lisp
      (defun get-planetary-shapes (t-val)
        "Calculate shapes at parameter t-val (Hohmann parameter)."
        (let* ((omega-e 1.0)
               (omega-m (/ 1.0 1.88))
               ;; Hohmann travel duration is pi. During this, Mars moves by omega-m * pi.
               ;; Launch phase-angle condition: Mars must be at angle (pi - omega-m * pi)
               ;; when Earth is at 0.
               (mars-launch-phase (- 3.14159 (* omega-m 3.14159)))
               
               ;; Positions
               (ex (cos (* omega-e t-val)))
               (ey (sin (* omega-e t-val)))
               (mx (cos (+ mars-launch-phase (* omega-m t-val))))
               (my (sin (+ mars-launch-phase (* omega-m t-val))))
               
               ;; Spacecraft transfer coordinates
               (a 1.262)
               (ecc 0.208)
               (r-space (/ (* a (- 1 (* ecc ecc))) (+ 1 (* ecc (cos t-val)))))
               (sx (* r-space (cos t-val)))
               (sy (* r-space (sin t-val)))
               
               ;; Generate trace points for the spacecraft path
               (trace-points (loop for theta from 0.0 to t-val by 0.1
                                   collect (let ((r (/ (* a (- 1 (* ecc ecc))) (+ 1 (* ecc (cos theta))))))
                                             (list (* r (cos theta)) (* r (sin theta)))))))
          (list
            ;; Sun
            `(:disk 0.0 0.0 0.12 :color ,*gc-sun*) ; Yellow Sun
            ;; Orbits
            `(:circle 0.0 0.0 1.0 :color ,*gc-shadow*)  ; Earth Orbit
            `(:circle 0.0 0.0 1.524 :color ,*gc-shadow*) ; Mars Orbit
            
            ;; Earth
            `(:disk ,ex ,ey 0.06 :color ,*gc-earth*) ; Blue Earth
            ;; Mars
            `(:disk ,mx ,my 0.05 :color ,*gc-mars*) ; Red Mars
            
            ;; Spacecraft transfer line / trajectory
            (if trace-points
                `(:poly-line ,trace-points :color ,*gc-shadow*)
                nil)
            ;; Spacecraft
            `(:disk ,sx ,sy 0.03 :color ,*gc-spacecraft*))))
```

---

## 3. Timeline & Execution

1. **Write specs and code templates** (`02_x11_spec.lisp`, `generate.lisp`, `04_widgets_builtin.lisp`, `05_event_loop.lisp`, `06_example_template.lisp`).
2. **Execute generator** inside SBCL to write updated library files to `source/`.
3. **Compile and run** the demo application in a graphical environment to verify coordinate ticks, axes, circle drawing correctness, and smooth Hohmann transfer animation.
