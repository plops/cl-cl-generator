# Pure First-Principles Relativistic Neon Transition Solver: Design & Implementation Plan (Plan 02)

## 1. Context and Target Requirements

The goal is to implement a **pure first-principles (ab initio)** Relativistic Neon Transition Solver. 
* Effective nuclear charges ($Z_{\text{eff}}$), empirical screening constants, or model potentials are **not allowed**.
* All calculations must use the true nuclear charge $Z = 10.0$ for the Neon atom.
* All 10 electrons ($1s^2 2s^2 2p^5 nl$) must be explicitly represented in the wavefunctions and electronic Hamiltonian.
* Variational collapse of the excited valence orbitals ($5s$ and $3p$) must be prevented purely through **explicit Gram-Schmidt orthogonalization** against the core orbitals of the same symmetry ($l$).
* The initial parameter guess for the optimization must be constructed from the eigenvectors of the core (one-electron) Hamiltonian to ensure numerical stability and prevent local minima traps.
* The transition frequency $\nu_0$ must have the correct positive sign and reside in the physical range ($\approx 473$ THz).

---

## 2. File and System Reference
* **Generator File**: [gen01.lisp](file:///workspace/src/cl-cl-generator/example/03_py_meta/example/01_neon/gen01.lisp). All Python files must be generated from this file. **Do not modify Python files directly**.
* **Generated Python Files**:
  - [solver.py](file:///workspace/src/cl-cl-generator/example/03_py_meta/example/01_neon/source01/solver.py)
  - [test_solver.py](file:///workspace/src/cl-cl-generator/example/03_py_meta/example/01_neon/source01/test_solver.py)
  - [plot.py](file:///workspace/src/cl-cl-generator/example/03_py_meta/example/01_neon/source01/plot.py)
* **Loading the Transpiler**:
  To load the new transpiler package, push the path to ASDF's central registry:
  ```lisp
  (push "/workspace/src/cl-cl-generator/example/03_py_meta/" asdf:*central-registry*)
  (ql:quickload :cl-py-generator-example)
  ```
  And use package `:cl-py-generator` with DSL operators: `progn` (replacing `do0`), `body` (replacing `do`), and `dict*` (replacing `dictionary`).

---

## 3. Ab Initio 10-Electron Physical Model

All orbital energies are calculated with the true nuclear charge $Z = 10.0$ using:
$$\mathbf{H}, \mathbf{S} = \text{compute\_matrices}(\alpha, l, \kappa, Z=10.0)$$

### A. Orbital Basis Sizes
To describe the multiple shells, the primitive basis function set must be expanded:
* **$s$-channel ($l=0$)**: $N_s = 8$ GTOs:
  `log_alpha_s = jnp.linspace(jnp.log(0.01), jnp.log(500.0), 8)`
* **$p$-channel ($l=1$)**: $N_p = 6$ GTOs:
  `log_alpha_p = jnp.linspace(jnp.log(0.05), jnp.log(100.0), 6)`

### B. Mutual Gram-Schmidt Orthogonalization
The variational parameters optimized in the JAX pipeline are the unconstrained coefficient vectors $x$. The physical, orthonormalized orbital coefficients $c$ are computed from $x$ via sequential Gram-Schmidt projection:

1. **$s$-channel ($l=0$)**: Orthonormalize $c_{1s}$, $c_{2s}$, and $c_{5s}$ (initial state only) under the overlap matrix $\mathbf{S}_s$ (from $l=0$ matrices):
   * **$1s$**:
     $$c_{1s} = \frac{x_{1s}}{\sqrt{x_{1s}^\dagger \mathbf{S}_s x_{1s}}}$$
   * **$2s$**:
     $$x_{2s}^{\text{proj}} = x_{2s} - \left(c_{1s}^\dagger \mathbf{S}_s x_{2s}\right) c_{1s}$$
     $$c_{2s} = \frac{x_{2s}^{\text{proj}}}{\sqrt{(x_{2s}^{\text{proj}})^\dagger \mathbf{S}_s x_{2s}^{\text{proj}}}}$$
   * **$5s$**:
     $$x_{5s}^{\text{proj}} = x_{5s} - \left(c_{1s}^\dagger \mathbf{S}_s x_{5s}\right) c_{1s} - \left(c_{2s}^\dagger \mathbf{S}_s x_{5s}\right) c_{2s}$$
     $$c_{5s} = \frac{x_{5s}^{\text{proj}}}{\sqrt{(x_{5s}^{\text{proj}})^\dagger \mathbf{S}_s x_{5s}^{\text{proj}}}}$$

2. **$p$-channel ($l=1$)**: Orthonormalize $c_{2p}$ and $c_{3p}$ (final state only) under the overlap matrix $\mathbf{S}_p$ (from $l=1$ locked average overlap):
   * **$2p$**:
     $$c_{2p} = \frac{x_{2p}}{\sqrt{x_{2p}^\dagger \mathbf{S}_p x_{2p}}}$$
   * **$3p$**:
     $$x_{3p}^{\text{proj}} = x_{3p} - \left(c_{2p}^\dagger \mathbf{S}_p x_{3p}\right) c_{2p}$$
     $$c_{3p} = \frac{x_{3p}^{\text{proj}}}{\sqrt{(x_{3p}^{\text{proj}})^\dagger \mathbf{S}_p x_{3p}^{\text{proj}}}}$$

---

## 4. Total Hartree-Fock Energy Expressions

For a 10-electron system, there are 45 pair-wise Coulomb ($J$) and Exchange ($K$) interactions.

### A. Evaluated Integrals
* **$s$-$s$ interactions**:
  Use the GTO tensor for $l=0$:
  `G_s = compute_G_generic(alpha_s, 0, alpha_s, 0, alpha_s, 0, alpha_s, 0)`
  For any $s$-orbitals $A$ and $B$:
  $$J_{A,B} = \text{einsum}("i,j,k,l,ijkl\to", c_A, c_A, c_B, c_B, G_s)$$
  $$K_{A,B} = \text{einsum}("i,j,k,l,ijkl\to", c_A, c_B, c_A, c_B, G_s)$$
* **$p$-$p$ interactions**:
  Use the GTO tensor for $l=1$:
  `G_p = compute_G_generic(alpha_p, 1, alpha_p, 1, alpha_p, 1, alpha_p, 1)`
  For any $p$-orbitals $A$ and $B$:
  $$J_{A,B} = \text{einsum}("i,j,k,l,ijkl\to", c_A, c_A, c_B, c_B, G_p)$$
  $$K_{A,B} = \text{einsum}("i,j,k,l,ijkl\to", c_A, c_B, c_A, c_B, G_p)$$
* **$p$-$s$ interactions**:
  Use cross-tensors computed once for basis sets `alpha_p` and `alpha_s`:
  `G_ps_coul = compute_G_generic(alpha_p, 1, alpha_p, 1, alpha_s, 0, alpha_s, 0)`
  `G_ps_exch = compute_G_generic(alpha_p, 1, alpha_s, 0, alpha_p, 1, alpha_s, 0)`
  For any $p$-orbital $A$ and $s$-orbital $B$:
  $$J_{A,B} = \text{einsum}("i,j,k,l,ijkl\to", c_A, c_A, c_B, c_B, G_{ps\_coul})$$
  $$K_{A,B} = \text{einsum}("i,j,k,l,ijkl\to", c_A, c_B, c_A, c_B, G_{ps\_exch})$$

### B. Energy Formulations
1. **Initial State ($1s^2 2s^2 2p^5 5s$)**:
   $$E_{\text{initial}} = 2 E_{1s} + 2 E_{2s} + 5 E_{2p} + E_{5s} + E_{\text{ee}}^{\text{initial}}$$
   $$\begin{aligned}
   E_{\text{ee}}^{\text{initial}} = & J_{1s,1s} + J_{2s,2s} + 10 J_{2p,2p} - 4 K_{2p,2p} \\
   & + 4 J_{1s,2s} - 2 K_{1s,2s} + 2 J_{1s,5s} - K_{1s,5s} + 2 J_{2s,5s} - K_{2s,5s} \\
   & + 10 J_{2p,1s} - 5 K_{2p,1s} + 10 J_{2p,2s} - 5 K_{2p,2s} + 5 J_{2p,5s} - 2.5 K_{2p,5s}
   \end{aligned}$$

2. **Final State ($1s^2 2s^2 2p^5 3p$)**:
   $$E_{\text{final}} = 2 E_{1s} + 2 E_{2s} + 5 E_{2p} + E_{3p} + E_{\text{ee}}^{\text{final}}$$
   $$\begin{aligned}
   E_{\text{ee}}^{\text{final}} = & J_{1s,1s} + J_{2s,2s} + 10 J_{2p,2p} - 4 K_{2p,2p} \\
   & + 4 J_{1s,2s} - 2 K_{1s,2s} + 2 J_{1s,3p} - K_{1s,3p} + 2 J_{2s,3p} - K_{2s,3p} \\
   & + 10 J_{2p,1s} - 5 K_{2p,1s} + 10 J_{2p,2s} - 5 K_{2p,2s} + 5 J_{2p,3p} - 2.5 K_{2p,3p}
   \end{aligned}$$

---

## 5. Numerical Stability: Initial Guesses via Diagonalization

To guarantee convergence to the global Hartree-Fock ground state and avoid local minima:
1. **$s$-channel initial guesses**:
   - Construct the core $s$-channel Hamiltonian $\mathbf{H}_s^0 = \mathbf{V}_s + \mathbf{T}_s$ and overlap $\mathbf{S}_s$ for $Z=10.0$.
   - Solve the generalized eigenvalue problem $\mathbf{H}_s^0 c = E \mathbf{S}_s c$ using:
     ```python
     S_val, S_vec = jnp.linalg.eigh(S_s)
     S_inv_sqrt = jnp.dot(S_vec, jnp.dot(jnp.diag(1.0 / jnp.sqrt(S_val)), S_vec.T))
     H_std = jnp.dot(S_inv_sqrt, jnp.dot(H_s, S_inv_sqrt))
     _, eigvecs = jnp.linalg.eigh(H_std)
     c_eig = jnp.dot(S_inv_sqrt, eigvecs)
     ```
   - Initialize `x_1s = c_eig[:, 0]`, `x_2s = c_eig[:, 1]`, and `x_5s = c_eig[:, 4]` (or `c_eig[:, 2]`).
2. **$p$-channel initial guesses**:
   - Solve the generalized eigenvalue problem for the core $p$-channel Hamiltonian and overlap.
   - Initialize `x_2p = c_eig_p[:, 0]` and `x_3p = c_eig_p[:, 1]`.
