# Walkthrough: Inside the Multi-Domain Solver Compiler

This walkthrough guides you through the source code of the multi-domain compiler and its interactive GUI demo, explaining how the code-generation pipeline works step-by-step.

---

## 1. The Symbolic Engine: `compiler.lisp`

The file [compiler.lisp](file:///workspace/src/cl-cl-generator/example/10_multi_domain_solver/compiler.lisp) contains the logic to parse the netlist, assemble the equations, solve them symbolically, and emit the Lisp source code.

### A. Symbolic Differentiation & Simplification
To support Newton-Raphson for non-linear elements (like diodes), we need to calculate derivatives. In Lisp, code is data (nested lists), which allows us to write a recursive differentiator (`diff`) and algebraic simplifier (`simplify`) in just a few lines of code:

```lisp
(defun diff (expr var)
  "Recursively differentiate EXPR with respect to VAR."
  (cond
    ((equal expr var) 1)
    ((atom expr) 0)
    (t (case (car expr)
         (+ `(+ ,(diff (second expr) var) ,(diff (third expr) var)))
         (- `(- ,(diff (second expr) var) ,(diff (third expr) var)))
         (* (let ((u (second expr))
                  (v (third expr)))
              `(+ (* ,u ,(diff v var)) (* ,v ,(diff u var)))))
         ...))))
```

The `simplify` function reduces algebraic boilerplate (such as `(+ 0 x)` $\to$ `x`, `(* 1 x)` $\to$ `x`, `(* 0 x)` $\to$ `0`), ensuring that the generated mathematical code is as compact as possible.

### B. Compile-Time Linear Equation Solver
Instead of resolving $\mathbf{A} \mathbf{x} = \mathbf{b}$ at runtime using matrix operations, `solve-symbolic-system` performs **Gaussian Elimination with partial pivoting** on the symbolic expressions at compile-time:

```lisp
(defun solve-symbolic-system (mat-a vec-b vars)
  ;; Forward elimination and partial pivoting ...
  ;; Back substitution ...
  ;; Returns a list of let-bindings (var expression)
  )
```

For a $3\times3$ system, this results in straight-line, flat Lisp expressions for each node voltage or branch current, allowing the Lisp compiler to perform optimal register allocation.

### C. MNA Matrix Assembly
The function `compile-netlist-to-file` processes each component in the netlist and stamps its contribution to the symbolic matrix:
1.  **Conductances** add constant/parameter entries to the linear matrix $\mathbf{A}$.
2.  **Capacities** add transient conductances ($\frac{C}{h}$) to the diagonal of $\mathbf{A}$ and inject the history term into the RHS vector $\mathbf{b}$. They also register a state variable update: `(setf prev-vc (- v1 v2))`.
3.  **Inductances** add branch equations to $\mathbf{A}$ and add their current variable $i_L$ to the unknowns.

---

## 2. The GUI Visualizer: `oscillator-gui.lisp`

The file [oscillator-gui.lisp](file:///workspace/src/cl-cl-generator/example/10_multi_domain_solver/oscillator-gui.lisp) implements the interactive display using the pure Lisp X11 framework.

### A. Elm-style State Loop
The event loop is built around the Elm architecture: `(run-gui #'update-app #'view-app initial-state)`.
*   **`update-app`**: On every tick, it calls `(step-simulation sim-state dt force)`. The spring current `I-K1` is extracted, and the displacement $x$ is computed as:
    $$x = \frac{i_L}{k}$$
    The time and displacement are pushed onto a history list (trimmed to the last 150 points) to draw the rolling plot.
*   **`view-app`**: Returns a virtual tree of widgets, including the `canvas` widget containing the physical drawing.

### B. Drawing the Components
We compute coordinate vectors in the canvas coordinate system:
*   **The Spring**: Drawn as a zigzag line connecting the wall to the mass. `make-spring-points` generates alternating points:
    ```lisp
    (loop for i from 0 below num-turns do
      (push (list (+ x-start (* step (+ 2 (* 2 i)))) (+ y-val width)) points)
      (push (list (+ x-start (* step (+ 3 (* 2 i)))) (- y-val width)) points))
    ```
*   **The Damper**: Drawn as a piston and cylinder block using gray line segments.
*   **The Mass**: Drawn as a blue filled disk (`:disk`) that shifts horizontally based on the displacement $x$.
*   **The Rolling Plot**: Drawn in the bottom half of the canvas by mapping the history list of $(t, x)$ pairs to the coordinates $[-1.8, 1.8] \times [-1.2, -0.4]$ and passing them to X11 as a `:poly-line`.
