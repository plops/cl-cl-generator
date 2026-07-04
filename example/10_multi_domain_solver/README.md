# Multi-Domain Lumped-Element Circuit Compiler

This directory contains a complete, symbolic multi-domain physics compiler built using `cl-cl-generator`. It allows you to model physical systems from different domains (mechanical, thermal, electrical, fluidic) as networks of lumped elements (analogous to SPICE netlists) and compiles them into highly optimized, zero-allocation Common Lisp simulation code.

---

## 1. Physical Foundations: Lumped Element Analogy

In physics and engineering, systems with spatially distributed properties can often be approximated as networks of discrete, localized components called **lumped elements**. By classifying physical quantities into **Across variables** (which are measured as a difference between two points) and **Through variables** (which flow through a component), we can use the same mathematical framework to model diverse domains.

### Mappings across Domains (Mobility / Force-Current Analogy)
This compiler uses the **Mobility Analogy** (Force-Current) for mechanical systems because it preserves the topology: a mass connected to the frame translates directly to a capacitor connected to ground.

| Domain | Across Variable ($x$) | Through Variable ($y$) | Dissipative Element ($R$) | Potential Energy ($L$) | Kinetic / Thermal Capacity ($C$) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Electrical** | Voltage ($V$ [V]) | Current ($I$ [A]) | Resistor ($R$ [$\Omega$]) | Inductor ($L$ [H]) | Capacitor ($C$ [F]) |
| **Mechanical (Translational)** | Velocity ($v$ [m/s]) | Force ($F$ [N]) | Damper ($b$ [N-s/m]) | Spring ($1/k$ [m/N]) | Mass ($m$ [kg]) |
| **Mechanical (Rotational)** | Ang. Velocity ($\omega$ [rad/s]) | Torque ($M$ [N-m]) | Torsional Damper | Torsional Spring ($1/c$) | Moment of Inertia ($J$) |
| **Thermal** | Temp. Difference ($\Delta T$ [K]) | Heat Flow ($\dot{Q}$ [W]) | Thermal Res. ($R_{th}$) | *N/A* | Thermal Capacity ($C_{th}$) |
| **Fluidic / Hydraulic** | Pressure Diff. ($\Delta P$ [Pa]) | Volumetric Flow ($Q$) | Fluid Resistance | Fluid Inertance | Fluid Accumulator |

---

## 2. Mathematical Framework: Modified Nodal Analysis (MNA)

Modified Nodal Analysis is the standard algorithm used by SPICE simulators. The goal is to solve for all node potentials $v_1, \dots, v_N$ and certain branch currents $j_1, \dots, j_M$ (such as currents through voltage sources or inductors).

Let the unknown vector be:
$$\mathbf{x} = \begin{bmatrix} \mathbf{v} \\ \mathbf{j} \end{bmatrix}$$

We set up the linear system at each time step:
$$\mathbf{A} \cdot \mathbf{x} = \mathbf{b}$$

### 1. Kirchhoff's Laws (Conservation of Flow)
At each node $k$ (excluding ground node $0$), the sum of all through-variables (currents/forces/heat flows) entering the node must equal zero:
$$\sum I_{in} = 0$$
This translates to the node rows in $\mathbf{A}$ and $\mathbf{b}$.

### 2. Branch Equations
For elements that restrict potentials (such as independent voltage sources or velocities), we add a row representing the branch equation:
$$v_{n1} - v_{n2} = V_{src}$$
And we add an unknown branch current variable $j_{src}$ to $\mathbf{x}$.

---

## 3. Discretization of Time-Varying Elements (Backward Euler)

For energy-storing elements (capacities and inductances), their branch equations are differential equations. We discretize them in time using the **Backward Euler** method with time step $h = \Delta t$.

### A. Capacities (Masses, Capacitors, Thermal Capacities)
The continuous branch equation is:
$$i_C(t) = C \frac{d v_C(t)}{dt}$$

Discretizing at step $t_k$:
$$i_C(t_k) = C \frac{v_C(t_k) - v_C(t_{k-1})}{h} = \frac{C}{h} v_C(t_k) - \frac{C}{h} v_C(t_{k-1})$$

In the MNA matrix, this is equivalent to:
*   A **conductance** of value $G_{eq} = \frac{C}{h}$ connected between the nodes.
*   A **historical through-source** of value $J_{eq} = \frac{C}{h} v_C(t_{k-1})$ injecting flow into the nodes.

### B. Inductances (Springs, Inductors)
The continuous branch equation is:
$$v_L(t) = L \frac{d i_L(t)}{dt}$$

Discretizing at step $t_k$:
$$v_L(t_k) = L \frac{i_L(t_k) - i_L(t_{k-1})}{h} \implies v_L(t_k) - \frac{L}{h} i_L(t_k) = -\frac{L}{h} i_L(t_{k-1})$$

In our MNA assembler, we treat the inductor current $i_L$ as an unknown branch current in the vector $\mathbf{x}$. We add the branch equation to the matrix:
$$v_{n1} - v_{n2} - \frac{L}{h} i_L(t_k) = -\frac{L}{h} i_L(t_{k-1})$$
And we update the state variable for the next step:
$$i_{L,prev} \leftarrow i_L(t_k)$$

---

## 4. Nonlinear Solver: Newton-Raphson Method

When nonlinear elements (like diodes) are present in the netlist, the equations become nonlinear:
$$\mathbf{F}(\mathbf{x}) = \mathbf{A}_{lin} \mathbf{x} - \mathbf{b}_{lin} + \mathbf{f}_{nl}(\mathbf{x}) = 0$$

To solve this, the compiler generates a Newton-Raphson loop. At each iteration $m$, we calculate the step update $\mathbf{\Delta x}$:
$$\mathbf{J}(\mathbf{x}^{(m)}) \cdot \mathbf{\Delta x} = -\mathbf{F}(\mathbf{x}^{(m)})$$
Where the Jacobian matrix is:
$$\mathbf{J}(\mathbf{x}) = \mathbf{A}_{lin} + \frac{\partial \mathbf{f}_{nl}}{\partial \mathbf{x}}$$

For a diode connected between $n1$ and $n2$ with current $I_D(v_d) = I_S (e^{v_d/V_T} - 1)$, the compiler symbolically computes:
*   The current $I_D$ to add to the residual vector $\mathbf{F}(\mathbf{x})$.
*   The dynamic conductance $g_D = \frac{\partial I_D}{\partial v_d} = \frac{I_S}{V_T} e^{v_d/V_T}$ to add to the Jacobian matrix $\mathbf{J}(\mathbf{x})$.

---

## 5. Quick Start: Running the Mass-Spring-Damper Simulation

### Prerequisites
*   SBCL (Steel Bank Common Lisp)
*   Quicklisp installed and configured
*   An active X11 server (if running the GUI demo)

### Run the X11 Visualizer
Run the helper script directly:
```bash
./example/10_multi_domain_solver/run-gui.sh
```

This compiles the mechanical mass-spring-damper system netlist, generates the Lisp solver [oscillator-solver.lisp](file:///workspace/src/cl-cl-generator/example/10_multi_domain_solver/source01/oscillator-solver.lisp), loads it, and pops open a window showing the physical animation and a real-time oscilloscope rolling trace of the mass displacement $x(t)$.
