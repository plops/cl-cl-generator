# Implementation Plan: Relativistic Neon Transition Solver in JAX

This document outlines the implementation plan for building a relativistic atomic structure solver in JAX, generated from Common Lisp using the `cl-py-generator` transpiler.

## 1. Project Directory and File Structure

The project files will be structured inside the `example/01_neon/` folder:

- [plan/01/plan.md](file:///workspace/src/cl-cl-generator/example/03_py_meta/example/01_neon/plan/01/plan.md): This file. Detailed implementation plan including the physics formulas, optimization approach, and file descriptions.
- [plan/01/task.md](file:///workspace/src/cl-cl-generator/example/03_py_meta/example/01_neon/plan/01/task.md): Detailed tasks for the agent, providing sufficient physical and technical context for each task.
- [deps.md](file:///workspace/src/cl-cl-generator/example/03_py_meta/example/01_neon/deps.md): Markdown file listing all project dependencies and their respective GitHub repository URLs.
- [gen01.lisp](file:///workspace/src/cl-cl-generator/example/03_py_meta/example/01_neon/gen01.lisp): Common Lisp generator script that imports `cl-py-generator` and contains the S-expressions representing the python code.
- [source01/solver.py](file:///workspace/src/cl-cl-generator/example/03_py_meta/example/01_neon/source01/solver.py): The main JAX-based solver module containing physics models, GTO integral calculations, direct energy minimization via JAXopt, and implicit differentiation.
- [source01/test_solver.py](file:///workspace/src/cl-cl-generator/example/03_py_meta/example/01_neon/source01/test_solver.py): Unit tests using `pytest` to validate core components (overlap, kinetic energy, kinetic balance, spin-orbit, and gradient).
- [source01/plot.py](file:///workspace/src/cl-cl-generator/example/03_py_meta/example/01_neon/source01/plot.py): Script to generate matplotlib plots visualizing the converged radial wavefunctions (large/small components) and optimization energy decay.

---

## 2. Relativistic Dirac-Coulomb Physics Model

To compute the $3s_2 \rightarrow 2p_4$ transition (vacuum wavelength $\lambda_0 \approx 632.991$ nm, frequency $\nu_0 \approx 473.6127$ THz) from first principles, we model the 10-electron Neon atom.

### 2.1 Wavefunctions as Relativistic GTOs
A relativistic orbital is represented as a 4-component Dirac spinor. The radial wavefunction consists of a Large component $P(r)$ and a Small component $Q(r)$:
$$P(r) = \sum_{i} c_i r^{l+1} \exp(-\alpha_i r^2)$$
To prevent variational collapse, the Small component $Q(r)$ coefficients are locked to $P(r)$ via the **Relativistic Kinetic Balance** condition:
$$Q(r) = \frac{1}{2c} \left( \frac{d}{dr} + \frac{\kappa}{r} \right) P(r)$$
where $\kappa$ is the relativistic angular momentum quantum number:
- For $s_{1/2}$: $l=0, j=1/2 \implies \kappa = -1$
- For $p_{1/2}$: $l=1, j=1/2 \implies \kappa = 1$
- For $p_{3/2}$: $l=1, j=3/2 \implies \kappa = -2$

### 2.2 Analytical One-Electron Integrals
We use the radial basis primitives $g_i(r) = r^{k_i} \exp(-\alpha_i r^2)$ where $k_i = l_i + 1$:
1. **Overlap Matrix**:
   $$S_{ij} = \int_0^\infty g_i(r) g_j(r) dr = \frac{1}{2} (\alpha_i + \alpha_j)^{-\frac{k_i + k_j + 1}{2}} \Gamma\left(\frac{k_i + k_j + 1}{2}\right)$$
2. **Nuclear Coulomb Potential**:
   $$V_{ij} = -Z \int_0^\infty g_i(r) \frac{1}{r} g_j(r) dr = -Z \cdot \frac{1}{2} (\alpha_i + \alpha_j)^{-\frac{k_i + k_j}{2}} \Gamma\left(\frac{k_i + k_j}{2}\right)$$
3. **Kinetic Energy Terms**:
   We evaluate derivatives and inner products of $P(r)$ and $Q(r)$ to compute the core Dirac Hamiltonian matrix elements.

### 2.3 Vectorized 4-Center Electron Repulsion
The electron-electron Coulomb repulsion is evaluated via:
$$\iint \frac{\rho_1(\mathbf{r}_1)\rho_2(\mathbf{r}_2)}{|\mathbf{r}_1 - \mathbf{r}_2|} d\mathbf{r}_1 d\mathbf{r}_2$$
We vectorize the analytical GTO integrations over the basis set combinations using `jax.vmap` to achieve GPU/TPU-friendly execution.

### 2.4 Spin-Orbit Splitting and Intermediate Coupling
For intermediate coupling (between LS and jj regimes), we build a Hamiltonian matrix including electrostatic repulsion and spin-orbit splitting $\zeta \mathbf{L} \cdot \mathbf{S}$, diagonalizing it via `jnp.linalg.eigh` to find the exact fine-structure energy levels.

---

## 3. Direct Energy Minimization & Differentiation

1. **Direct Energy Minimization**: We optimize both the GTO linear coefficients ($c_i$) and exponents ($\alpha_i$) directly using `jaxopt.LBFGS` or `jaxopt.BFGS`. This bypasses the convergence instabilities of legacy Self-Consistent Field (SCF) loops.
2. **Implicit Differentiation**: Setting `implicit_diff=True` in JAXopt allows `jax.grad` to propagate gradients through the converged optimizer state. We calculate the mass sensitivity derivative (isotope shift) via:
   $$\frac{d\nu_0}{dM} = \text{jax.grad}(\nu_{\text{solver}})(M)$$
