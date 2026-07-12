# Tasks: JAX Relativistic Neon Transition Solver

> [!IMPORTANT]
> **CRITICAL METHODOLOGY REQUIREMENT**:
> All Python implementation files (`solver.py`, `test_solver.py`, `plot.py` inside `source01/`) **must NOT** be written or modified directly.
> You must implement the code generator S-expressions in Common Lisp inside `gen01.lisp`, which uses the `cl-py-generator` transpiler to produce and format the Python files via `write-source`.
> Leverage Lisp macros, helper functions, and loop splices (`,@(loop ...)`) to make the S-expression definitions efficient and clean.

---

## Task 1: Environment & Dependency Installation

### Goal
Initialize the Python environment and install the physical simulation and testing dependencies using `uv`.

### Requirements
1. Use `uv` to install:
   - `jax` and `jaxlib` (CPU version is fine for local verification, but GPU/TPU enabled).
   - `jaxopt` (for unconstrained optimization).
   - `matplotlib` (for visualizations).
   - `pytest` (for verification tests).
   - `ruff` (for formatting).
2. The transpiler `write-source` command in `py.lisp` will automatically call `ruff format` on files written to disk. Ensure the formatting tool runs successfully.
3. Validate the `deps.md` file created in the example directory.

---

## Task 2: Code Generator Script (`gen01.lisp`)

### Goal
Create a Common Lisp generator script `gen01.lisp` that uses the **new transpiler** in `/workspace/src/cl-cl-generator/example/03_py_meta/` to define and transpile Python files into the `source01/` subdirectory.

### Requirements
1. File location: `example/03_py_meta/example/01_neon/gen01.lisp`
2. Structure:
   - Push `/workspace/src/cl-cl-generator/example/03_py_meta/` to `asdf:*central-registry*` to register the new transpiler's ASDF system definition.
   - Load system `:cl-py-generator-example` via `(ql:quickload :cl-py-generator-example)`. Do **NOT** load the old `:cl-py-generator` system.
   - Use the package `:cl-py-generator` which is exported by the new system.
   - Use the new DSL constructs: `progn` (instead of `do0`), `body` (instead of `do`), and `dict*` (instead of `dictionary`).
   - Use `write-source` to output `source01/solver.py`, `source01/test_solver.py`, and `source01/plot.py`.
3. Use S-expression code generation features (like loops or helper macros) to keep the generated code DRY (Don't Repeat Yourself) when defining similar components.

---

## Task 3: Physics Solver Module (`source01/solver.py`)

### Goal
Implement the main physics simulation engine in JAX and JAXopt.

### Requirements
1. **Gaussian Basis Representation**:
   - Parameterize Large component $P_i(r) = \sum c_i r^{l+1} e^{-\alpha_i r^2}$.
   - Enforce kinetic balance to compute Small component $Q_i(r)$.
2. **Integral Math**:
   - Implement the analytical GTO overlap matrix $S$.
   - Implement the nuclear potential attraction matrix $V$ (for $Z=10$).
   - Implement the one-electron Dirac kinetic terms.
   - Implement the vectorized 4-center electron-electron repulsion integrals using `jax.vmap` based on the formula:
     ```python
     def primitive_coulomb_integral(alpha_a, alpha_b, alpha_c, alpha_d):
         p = alpha_a + alpha_b
         q = alpha_c + alpha_d
         return (2 * jnp.pi**(2.5)) / (p * q * jnp.sqrt(p + q))
     ```
3. **Hamiltonian & Solver**:
   - Assemble the core Dirac Hamiltonian and addition of electron-electron repulsion.
   - Build the spin-orbit splitting matrix for intermediate coupling.
   - Run optimization for the initial state (3s2: 5s valence) and final state (2p4: 3p valence) using `jaxopt.LBFGS` or `jaxopt.BFGS` with `implicit_diff=True`.
4. **Isotope Shift**:
   - Define a wrapper function `nominal_frequency_wrapper(nuclear_mass)` that runs the optimizations and outputs the transition frequency $\nu_0 = \Delta E / h$.
   - Apply `jax.grad` to this wrapper to get the analytical gradient of frequency with respect to nuclear mass.

---

## Task 4: Unit Testing Suite (`source01/test_solver.py`)

### Goal
Implement `pytest` unit tests verifying the physical and mathematical correctness of the solver components.

### Requirements
1. **Overlap Normalization Test**: Assert that the overlap matrix $S$ of a normalized GTO wavefunction with itself is exactly $1.0 \pm 10^{-6}$.
2. **Hydrogen Atom Benchmark**: Solve Hydrogen ($Z=1$, 1s state) and verify that the direct optimization converges to the analytical energy of $-0.5$ Hartree (non-relativistic) or the corresponding Dirac energy.
3. **Coulomb Symmetries & Decay**:
   - Assert the permutation symmetries: $(ab|cd) = (ba|cd) = (ab|dc) = (cd|ab)$.
   - Assert the asymptotic decay: As the distance $R$ between two primitives increases, the repulsion decays as $1/R$.
4. **Kinetic Balance Enforcer**: Assert that in the free-particle limit ($Z=0$), the energy eigenvalues cleanly split into positive and negative continuum states separated by $2 m_e c^2 \approx 1.022$ MeV with no spurious states in between.
5. **Isotope Shift Cross-Check**: Compare the analytical gradient from `jax.grad` with a manual central finite difference calculation:
   $$\text{finite\_diff\_slope} = \frac{E(22) - E(20)}{2}$$
   Verify they match within a tolerance of $10^{-5}$.

---

## Task 5: Visualizations (`source01/plot.py`)

### Goal
Create a plotting script that saves matplotlib figures visualizing the converged states and optimization process.

### Requirements
1. **Wavefunction Plot**: Plot the Large component $P(r)$ and Small component $Q(r)$ of the converged radial spinor functions for the initial (5s) and final (3p) states as a function of radius $r$.
2. **Optimization Curve**: Plot the objective energy value at each optimization step to showcase convergence progress.
3. Save the resulting plots as image files in `source01/`.
