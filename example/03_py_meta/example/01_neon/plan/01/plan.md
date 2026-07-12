# Relativistic Neon Transition Solver in JAX

How to compute the neon 633nm transition from first principles: The transition responsible for the red beam is the Neon \(3s_2 \rightarrow 2p_4\) transition. 

Use jax to create an implementation that can be executed on gpu or tpu.

To compute the nominal transition frequency (ν₀) from first principles, you must solve the many-electron relativistic Dirac equation for the excited states of the Neon atom, calculate their energy eigenvalues, and apply the Planck relation:
$$\nu_0 = \frac{E_{\text{initial}} - E_{\text{final}}}{h}$$ 
Because Neon has 10 interacting electrons, an exact analytical solution does not exist. You must implement an ab initio quantum chemistry workflow using the following steps.

---

## 1. Map the Configuration (Bypassing Paschen Notation)
Spectral lines in gas lasers typically use Paschen notation, which numbers states sequentially rather than by quantum numbers. To perform a first-principles calculation, you must first map these to their actual Racah (jK) coupling configurations:

* Initial State (3s₂ in Paschen): This corresponds to a 2p⁵ 5s electron configuration. Specifically, it is the $2p^5(^2P^{\circ}_{1/2})5s \, [1/2]^{\circ}_1$ state.
* Final State (2p₄ in Paschen): This corresponds to a 2p⁵ 3p electron configuration. Specifically, it is the $2p^5(^2P^{\circ}_{3/2})3p \, [3/2]_2$ state.

## 2. Set Up the Relativistic Hamiltonian
Because the excited states depend heavily on spin-orbit splitting, a non-relativistic Hamiltonian is insufficient. You must use the Dirac-Coulomb-Breit Hamiltonian (Ĥ):
$$\hat{H} = \sum_{i=1}^{10} \left( c \boldsymbol{\alpha}_i \cdot \mathbf{p}_i + \beta_i m_e c^2 - \frac{Ze^2}{4\pi\epsilon_0 r_i} \right) + \sum_{i<j}^{10} \left( \frac{e^2}{4\pi\epsilon_0 r_{ij}} + \hat{H}_{\text{Breit}, ij} \right)$$ 

* The first summation handles the relativistic kinetic energy and nuclear Coulomb potential (Z=10).
* The second summation handles the electron-electron Coulomb repulsion.
* $\hat{H}_{\text{Breit}}$ accounts for magnetic interactions between electron spins and retardation effects.

## 3. Solve the Dirac-Fock Mean Field
You cannot solve all electron interactions simultaneously, so you start with an iterative mean-field approximation:

* Treat the inner 1s² 2s² electrons as a closed, frozen core.
* Optimize the radial wavefunctions for the open 2p⁵ core and the active valence electron (5s or 3p) until the self-consistent field energy converges.

## 4. Compute Fine Structure (Intermediate Coupling)
Neon sits in an intermediate coupling regime between LS-coupling (Russell-Saunders) and jj-coupling. The electrostatic repulsion ($e^2/r_{ij}$) and the spin-orbit interaction ($\zeta \mathbf{L}\cdot\mathbf{S}$) are of comparable strength.

* Construct a Hamiltonian matrix for the 2p⁵ 5s and 2p⁵ 3p manifolds.
* Diagonalize this matrix to find the exact mixing coefficients of the states.
* This step resolves the specific fine-structure energy levels (3s₂ and 2p₄) out of the broader configuration averages.

## 5. Account for Electron Correlation
The Dirac-Fock method assumes electrons see an "average" cloud of other electrons. To get an exact frequency, you must account for instantaneous electron-electron avoidance (correlation energy):

* Mix the primary state with virtual excited states (e.g., 2p⁵ 6s, 2p⁴ 3d²) to adjust the energy eigenvalues.
* Without this step, your calculated wavelength will be off by several nanometers.

## 6. Subtract Energies and Apply Planck's Constant
After extracting the correlated, relativistic energy eigenvalues for both states:

1. Calculate the difference: Δ E = E(2p⁵ 5s) - E(2p⁵ 3p) ≈ 3.136 × 10⁻¹⁹ Joules.
2. Divide by Planck's constant (h): $\nu_0 = \frac{\Delta E}{h}$.

This yields the nominal frequency of ≈ 473.6127 THz, which matches the target vacuum wavelength of $\lambda_0 = \frac{c}{\nu_0} \approx 632.991 \text{ nm}$.

---

## 7. How JAX Solves This Optimally
Traditional packages like GRASP2K use the Self-Consistent Field (SCF) method, which solves the problem iteratively by treating one electron at a time in the "average field" of the others. This often suffers from convergence issues.

With JAX, we bypass the SCF method entirely and treat the problem as a Direct Energy Minimization problem using non-linear optimization.

### 7.1 Differentiable Basis Sets (Instead of Rigid Grids)
Instead of a spatial finite-difference grid, parameterize the radial electronic wavefunctions using Gaussian-Type Orbitals (GTOs):
$$R(r) = \sum_{i} c_i \cdot \exp(-\alpha_i r^2)$$
Linear coefficients ($c_i$) and non-linear orbital exponents ($\alpha_i$) are optimized variables.

### 7.2 Relativistic Wavefunctions as PyTrees
In relativistic quantum mechanics, radial spinors are split into a Large component $P_{n\kappa}(r)$ and a Small component $Q_{n\kappa}(r)$.
To enforce kinetic balance and avoid variational collapse:
$$Q(r) \approx \frac{1}{2c} \left( \frac{d}{dr} + \frac{\kappa}{r} \right) P(r)$$
A JAX-native Pytree representing the orbital parameters:
```python
orbital_params = {
    "large_coeffs": jnp.array([0.1, 0.5, -0.2]),       # c_i
    "large_exponents": jnp.array([100.0, 10.0, 1.0]),  # alpha_i
    "small_coeffs": jnp.array([0.01, 0.05, -0.02]),
    "small_exponents": jnp.array([105.0, 11.0, 1.1])
}
```

### 7.3 Vectorizing the 4-Center Electron Repulsion Integrals
We vectorize the analytical GTO integrations over the basis set combinations using `jax.vmap`:
```python
@jax.jit
def primitive_coulomb_integral(alpha_a, alpha_b, alpha_c, alpha_d):
    """Computes a single two-electron integral for four primitive GTO exponents."""
    p = alpha_a + alpha_b
    q = alpha_c + alpha_d
    return (2 * jnp.pi**(2.5)) / (p * q * jnp.sqrt(p + q))

batch_coulomb = jax.vmap(jax.vmap(jax.vmap(jax.vmap(
    primitive_coulomb_integral, 
    in_axes=(0, None, None, None)),
    in_axes=(None, 0, None, None)),
    in_axes=(None, None, 0, None)),
    in_axes=(None, None, None, 0))
```

### 7.4 Optimization via Exact Hessians (Bypassing SCF)
We pass the objective function directly into a high-order geometric optimizer like `jaxopt.LBFGS` or `jaxopt.BFGS`. Using `implicit_diff=True` allows gradients to pass through the solver.

---

## 8. Development Methodology: Transpiler-Driven Development (TDD)
> [!IMPORTANT]
> **Implementation Note for AI Agents**:
> - All Python files must **NOT** be written directly. Instead, you must write S-expression templates in Common Lisp inside `gen01.lisp` and use the **new transpiler** (`cl-py-generator-example`) defined in the current repository at `/workspace/src/cl-cl-generator/example/03_py_meta/` to transpile and format the target Python files.
> - **Do NOT load the old `:cl-py-generator` system.** Register the path `/workspace/src/cl-cl-generator/example/03_py_meta/` in `asdf:*central-registry*` and load `:cl-py-generator-example` to load the new transpiler.
> - Ensure you use the updated DSL constructs of the new transpiler: `progn` (replacing `do0`), `body` (replacing `do`), and `dict*` (replacing `dictionary`).
> - Leverage Lisp helper functions or macro-like splices `,@(loop ...)` to generate Python code efficiently and reduce boilerplate.

### Project Files to be Created/Modified:
- [plan/01/plan.md](file:///workspace/src/cl-cl-generator/example/03_py_meta/example/01_neon/plan/01/plan.md): This plan. Complete description of equations, file mappings, and validation procedures.
- [plan/01/task.md](file:///workspace/src/cl-cl-generator/example/03_py_meta/example/01_neon/plan/01/task.md): Task list defining implementation milestones with context for the agent.
- [deps.md](file:///workspace/src/cl-cl-generator/example/03_py_meta/example/01_neon/deps.md): Lists project dependencies (JAX, JAXopt, Matplotlib, NumPy) and their GitHub repositories.
- [gen01.lisp](file:///workspace/src/cl-cl-generator/example/03_py_meta/example/01_neon/gen01.lisp): Common Lisp generator script containing S-expressions that represent the solver, test, and plot modules.
- [source01/solver.py](file:///workspace/src/cl-cl-generator/example/03_py_meta/example/01_neon/source01/solver.py): Main solver library containing GTO integral calculations, direct energy minimizer, and implicit differentiation of the isotope shift.
- [source01/test_solver.py](file:///workspace/src/cl-cl-generator/example/03_py_meta/example/01_neon/source01/test_solver.py): Formatted Python pytest code defining physical and analytical verification tests.
- [source01/plot.py](file:///workspace/src/cl-cl-generator/example/03_py_meta/example/01_neon/source01/plot.py): Plotting scripts to visualize radial wavefunctions and energy convergence.

---

## 9. Validation Plan

To ensure correctness and avoid silent physics bugs, the solver implementation must pass the following validation checks.

### Phase 1: Core Primitive & Integral Validation
* **Step 1: Overlap and Kinetic Energy Integrals**
  - **Task**: Implement GTO overlap $S_{ij}$ and non-relativistic kinetic matrices.
  - **Validation**: Calculate the overlap matrix for a single isolated Hydrogen atom ($Z=1$) using a standard basis (e.g. STO-3G). The overlap of a normalized orbital with itself must equal exactly $1.0$. Kinetic energy must match analytical values to 6 decimal places.
* **Step 2: Two-Electron Coulomb Integrals**
  - **Task**: Implement vectorized 4-center electron repulsion integrals.
  - **Validation**: Assert permutation symmetries: $(ab|cd) = (ba|cd) = (ab|dc) = (cd|ab)$. Verify asymptotic decay: when primitive Gaussians are moved far apart spatially, the repulsion decays exactly as $1/R$.

### Phase 2: Relativistic Physics Validation
* **Step 3: Kinetic Balance Enforcer**
  - **Task**: Lock Small component to Large component coefficients via kinetic balance.
  - **Validation**: Set nuclear potential $Z=0$ (free-particle limit) and check eigenvalues. They must cleanly split into positive and negative energy manifolds separated by exactly $2 m_e c^2 \approx 1.022$ MeV with no spurious states in between.

### Phase 3: Matrix & Coupling Validation
* **Step 4: Fine Structure Angular Momentum Matrices**
  - **Task**: Implement Spin-Orbit coupling matrices ($\zeta \mathbf{L} \cdot \mathbf{S}$) and diagonalize via `jnp.linalg.eigh`.
  - **Validation**: Turn off spin-orbit ($\zeta=0$); p-orbital eigenvalues must show a perfect 6-fold degeneracy. Turn on spin-orbit; energy spacing must follow the Landé interval rule.

### Phase 4: Optimization Validation
* **Step 5: Direct Energy Minimization Solver**
  - **Task**: Minimize energy via `jaxopt.LBFGS` or `jaxopt.BFGS`.
  - **Validation**: Run the pipeline on a Hydrogen-like ion ($He^+$, $Z=2$, 1 electron). The converged energy must match the analytical Dirac energy formula:
    $$E = m_e c^2 \left[ 1 + \left( \frac{Z\alpha}{n - |\kappa| + \sqrt{\kappa^2 - Z^2\alpha^2}} \right)^2 \right]^{-1/2}$$

### Phase 5: Complete Pipeline Validation
* **Step 6: The Isotope Shift Gradient**
  - **Task**: Implement the `jax.grad` wrapper over the final solver to pull out the mass derivative.
  - **Validation**: Compare `jax.grad` output with manual finite difference calculation:
    $$\frac{E(22) - E(20)}{2}$$
    Verify they match within a tolerance of $10^{-5}$.
