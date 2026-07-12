how to compute the neon 633nm transition from first principles: The transition responsible for the red beam is the Neon \(3s_2 \rightarrow 2p_4\) transition. 

use jax to create an implementation that can be executed on gpu or tpu.

To compute the nominal transition frequency (ν₀) from first principles, you must solve the many-electron relativistic Dirac equation for the excited states of the Neon atom, calculate their energy eigenvalues, and apply the Planck relation:
$$\nu_0 = \frac{E_{\text{initial}} - E_{\text{final}}}{h}$$ 
Because Neon has 10 interacting electrons, an exact analytical solution does not exist. You must implement an ab initio quantum chemistry workflow using the following steps. [1] 
------------------------------
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
You cannot solve all electron interactions simultaneously, so you start with an iterative mean-field approximation: [2] 

* Use the Multi-Configuration Dirac-Fock (MCDF) method.
* Treat the inner 1s² 2s² electrons as a closed, frozen core.
* Optimize the radial wavefunctions for the open 2p⁵ core and the active valence electron (5s or 3p) until the self-consistent field energy converges. [3] 

## 4. Compute Fine Structure (Intermediate Coupling)
Neon sits in an intermediate coupling regime between LS-coupling (Russell-Saunders) and jj-coupling. The electrostatic repulsion ($e^2/r_{ij}$) and the spin-orbit interaction ($\zeta \mathbf{L}\cdot\mathbf{S}$) are of comparable strength.

* Construct a Hamiltonian matrix for the 2p⁵ 5s and 2p⁵ 3p manifolds.
* Diagonalize this matrix to find the exact mixing coefficients of the states.
* This step resolves the specific fine-structure energy levels (3s₂ and 2p₄) out of the broader configuration averages.

## 5. Account for Electron Correlation
The Dirac-Fock method assumes electrons see an "average" cloud of other electrons. To get an exact frequency, you must account for instantaneous electron-electron avoidance (correlation energy):

* Implement Configuration Interaction (CI) or Relativistic Many-Body Perturbation Theory (RMBPT).
* Mix the primary state with thousands of virtual excited states (e.g., 2p⁵ 6s, 2p⁴ 3d²) to adjust the energy eigenvalues.
* Without this step, your calculated wavelength will be off by several nanometers.

## 6. Subtract Energies and Apply Planck's Constant
After extracting the correlated, relativistic energy eigenvalues for both states:

   1. Calculate the difference: Δ E = E(2p⁵ 5s) - E(2p⁵ 3p) ≈ 3.136 × 10⁻¹⁹ Joules.
   2. Divide by Planck's constant (h): $\nu_0 = \frac{\Delta E}{h}$.

This yields the nominal frequency of ≈ 473.6127 THz, which matches the target vacuum wavelength of $\lambda_0 = \frac{c}{\nu_0} \approx 632.991 \text{ nm}$.
------------------------------
If you want to implement this calculation practically, let me know if you would like to:

* See the input structure for a standard atomic structure code like GRASP2K (General Relativistic Atomic Structure Package).
* Understand how to calculate the transition probability (Einstein A coefficient) for this specific line to see how efficient the laser transition is.


[1] [https://www.feynmanlectures.caltech.edu](https://www.feynmanlectures.caltech.edu/III_19.html)
[2] [https://www.synopsys.com](https://www.synopsys.com/content/dam/synopsys/silicon/newsletters/tcad-news-winter2017-nl.pdf)
[3] [https://www.sciencedirect.com](https://www.sciencedirect.com/science/article/abs/pii/S0969806X25010357)




## What is GRASP2K?
GRASP2K (General Relativistic Atomic Structure Package) is a legacy, world-standard software package written in Fortran for performing ab initio atomic structure calculations. It implements the Multiconfiguration Dirac-Hartree-Fock (MCDHF) method.
To find a transition frequency, a physicist feeds GRASP2K the atomic number (Z=10 for Neon) and the target electron configurations ($2p^5 5s$ and $2p^5 3p$). GRASP2K then numerically solves the radial Dirac equations using a finite-difference grid, performs a Self-Consistent Field (SCF) iteration to handle electron-electron interactions, and outputs the exact relativistic energy levels.
------------------------------
## Can JAX Express and Solve This Optimally?
Yes, absolutely. In fact, replacing legacy Fortran workflows like GRASP2K with JAX changes how atomic structure calculations are solved.
Traditional packages like GRASP2K use the Self-Consistent Field (SCF) method, which solves the problem iteratively by treating one electron at a time in the "average field" of the others. This often suffers from convergence issues.
With JAX, you can bypass the SCF method entirely and treat the problem as a Direct Energy Minimization problem using non-linear optimization. [1] 
Here is how JAX optimizes and solves this specific problem:
## 1. Differentiable Basis Sets (Instead of Rigid Grids)
Instead of GRASP2K’s spatial finite-difference grid, you parameterize the radial electronic wavefunctions using an analytical basis set, such as Gaussian-Type Orbitals (GTOs) or Slater-Type Orbitals (STOs):
$$\left. R(r) = \sum_{i} c_i \cdot \exp(-\alpha_i r^2) \right.$$ 
In JAX, the linear coefficients ($c_i$) and the non-linear orbital exponents ($\alpha_i$) are treated as free parameters in an array.
## 2. Optimization via Exact Hessians (Bypassing SCF)
Instead of guessing a field, calculating a response, and repeating, you write a single JAX function that calculates the total energy of the Neon atom given your wavefunction parameters: total_energy(wavefunction_params).

* Traditional: Fortran codes use fixed, heuristic acceleration techniques to force convergence.
* JAX Approach: You pass your energy function directly into a high-order geometric optimizer like JAXopt.BFGS. Because JAX can compute the exact analytical Hessian matrix via automatic differentiation (jax.hessian), the non-linear optimization routine can converge to the absolute minimum energy state far more robustly than legacy SCF loops.

## 3. Configuration Interaction (CI) as an Eigenvalue Optimization
To get the exact $633\text{ nm}$ frequency, you must mix the base configurations with thousands of virtual states to capture electron correlation. This forms a massive, sparse Hamiltonian matrix.
JAX allows you to use jax.scipy.sparse.linalg.cg or custom Lanczos solvers to find the lowest eigenvalues of this matrix extremely quickly, fully accelerated by modern GPU/TPU hardware.
------------------------------
## A Conceptual JAX Formulation
If you were to write a first-principles Neon solver in JAX, the core architecture would look like this:

import jaximport jax.numpy as jnpimport jaxopt
def electronic_hamiltonian_energy(params, configurations):
    # params contains basis set coefficients (c) and exponents (alpha)
    
    # 1. Compute kinetic energy integrals (Relativistic Dirac terms)
    E_kin = compute_dirac_kinetic_energy(params)
    
    # 2. Compute electron-nuclear attraction
    E_nuc = compute_nuclear_attraction(params, Z=10)
    
    # 3. Compute electron-electron repulsion (4-center integrals)
    # This is traditionally the bottleneck; JAX accelerates this via vmap
    E_rep = compute_electron_repulsion(params)
    
    total_E = E_kin + E_nuc + E_rep
    return total_E
# Use JAXopt to minimize the energy directlyoptimizer = jaxopt.BFGS(fun=electronic_hamiltonian_energy)
# Optimize initial state (3s2 -> 2p5 5s)res_initial = optimizer.run(initial_guess_3s2, configurations=states_3s2)E_initial = res_initial.params
# Optimize final state (2p4 -> 2p5 3p)res_final = optimizer.run(initial_guess_2p4, configurations=states_2p4)E_final = res_final.params
# Calculate Nominal Frequencydelta_E = E_initial - E_finalh = 6.62607015e-34  # J·snominal_frequency = delta_E / h

## The Ultimate Advantage of JAX here
If you use a legacy tool like GRASP2K, computing the Isotope Shift or the Zeeman splitting requires running entirely separate perturbation modules.
With JAX, because the entire energy evaluation is fully differentiable, you can take the gradient of the final energy eigenvalue directly with respect to nuclear mass ($M$) or an external magnetic field ($B$). JAX will output the exact isotope shift automatically via automatic differentiation without you ever having to code the perturbation equations by hand.
------------------------------
Would you like to explore how the 4-electron repulsion integrals are mapped into vectorized JAX arrays, or would you like to see how to handle the spin-orbit coupling matrix in JAX?

[1] [https://arxiv.org](https://arxiv.org/html/2402.09983v1)


To implement a relativistic atomic structure solver in JAX that avoids the fragile convergence loops of legacy Fortran codes, you must transform the physics of the Dirac-Coulomb Hamiltonian into a continuous, unconstrained optimization problem.
The most optimal way to structure this in JAX involves a Direct Energy Minimization strategy paired with an Implicit Differentiation pipeline to extract properties like isotope shifts seamlessly.
------------------------------
## 1. Data Structures: Representing Relativistic Wavefunctions as Pytrees
In relativistic quantum mechanics, wavefunctions are represented as 4-component Dirac spinors. The radial components are split into a Large component $P_{n\kappa}(r)$ and a Small component $Q_{n\kappa}(r)$.
To make this JAX-native, parameterize these radial functions using a basis of Gaussian-Type Orbitals (GTOs). You can group these parameters into a standard Python dictionary, which JAX automatically treats as a Pytree: [1, 2] 

import jaximport jax.numpy as jnpimport jaxopt
# A Pytree representing the orbital parameters for a single state (e.g., 5s)orbital_params = {
    "large_coeffs": jnp.array([0.1, 0.5, -0.2]),       # Linear coefficients (c_i)
    "large_exponents": jnp.array([100.0, 10.0, 1.0]),  # Non-linear exponents (alpha_i)
    "small_coeffs": jnp.array([0.01, 0.05, -0.02]),    # Enforces relativistic kinetic balance
    "small_exponents": jnp.array([105.0, 11.0, 1.1])
}

------------------------------
## 2. The JAX Bottleneck: Vectorizing the 4-Center Electron Repulsion Integrals
The primary computational bottleneck in atomic physics is evaluating the electron-electron Coulomb repulsion. For any pair of electrons, you must evaluate a 4-center integral over the spatial coordinates:
$$\iint \frac{\psi_a^\dagger(\mathbf{r}_1)\psi_b(\mathbf{r}_1)\psi_c^\dagger(\mathbf{r}_2)\psi_d(\mathbf{r}_2)}{\vert{}\mathbf{r}_1 - \mathbf{r}_2\vert{}} d\mathbf{r}_1 d\mathbf{r}_2$$ 
Legacy Fortran loops parse these integrals using deeply nested DO loops. In JAX, you achieve hardware acceleration by expanding the radial distance reciprocal into spherical harmonics (multipole expansion) and vectorizing the evaluation over your GTO arrays using jax.vmap: [3] 

@jax.jitdef primitive_coulomb_integral(alpha_a, alpha_b, alpha_c, alpha_d):
    """Computes a single two-electron integral for four primitive GTO exponents."""
    # Analytical solution for GTO integrations over 1/|r1 - r2|
    # This avoids numerical grids entirely.
    p = alpha_a + alpha_b
    q = alpha_c + alpha_d
    return (2 * jnp.pi**(2.5)) / (p * q * jnp.sqrt(p + q))
# Vectorize across all interacting combinations in the basis setbatch_coulomb = jax.vmap(jax.vmap(jax.vmap(jax.vmap(
    primitive_coulomb_integral, 
    in_axes=(0, None, None, None)),
    in_axes=(None, 0, None, None)),
    in_axes=(None, None, 0, None)),
    in_axes=(None, None, None, 0))

------------------------------
## 3. Intermediate Coupling & Fine Structure Diagonalization
Because Neon sits squarely between $LS$ and $jj$ coupling, your JAX code must explicitly build the Hamiltonian Matrix ($H_{ij}$) for the mixing configurations.

* For the initial state ($3s_2$), you build the matrix for the $2p^5 5s$ manifold.
* For the final state ($2p_4$), you build it for the $2p^5 3p$ manifold.

Instead of writing a custom linear algebra loop, use JAX's differentiably traced matrix solvers to extract the lowest fine-structure energy eigenvalue:

def compute_total_energy(params, nuclear_mass):
    """The core objective function."""
    # 1. Compute Relativistic Kinetic Energy and Nuclear Attraction Matrix
    H_core = compute_dirac_core_hamiltonian(params, nuclear_mass)
    
    # 2. Compute Electron-Electron Interactions via vectorized integrals
    G_matrix = compute_electron_interaction_matrix(params)
    
    # Full Hamiltonian for the configuration manifold
    H_total = H_core + G_matrix
    
    # 3. Extract the targeted atomic energy level (Eigenvalue)
    # Using jnp.linalg.eigh allows gradients to pass cleanly through eigenvalues
    eigenvalues, eigenvectors = jnp.linalg.eigh(H_total)
    
    # Return a specific state index mapping to the fine structure level
    return eigenvalues[0] 

------------------------------
## 4. Bypassing SCF: Choosing the Right JAX Optimizer
Traditional Self-Consistent Field (SCF) iterations alternate between updating the electron density and recalculating the potential field. If your initial guess is poor, the loop oscillates and fails to converge.
By shifting this to Direct Energy Minimization, you update both the linear coefficients and the non-linear exponents simultaneously.

* Do not use standard gradient descent (Adam/SGD): Quantum mechanical energy landscapes are incredibly steep and poorly scaled. First-order optimizers will stall out.
* Use quasi-Newton methods: jaxopt.BFGS or jaxopt.LBFGS are highly ideal. Because JAX provides exact analytical gradients at every step, BFGS can construct an accurate local model of the energy surface.

# Initialize the L-BFGS optimizer targeting our direct energy functionoptimizer = jaxopt.LBFGS(fun=compute_total_energy, maxiter=1000, tol=1e-8)
# Run optimization for the initial state configurationres_initial = optimizer.run(initial_guess_params_3s2, nuclear_mass=19.9924)E_initial = res_initial.params
# Run optimization for the final state configurationres_final = optimizer.run(initial_guess_params_2p4, nuclear_mass=19.9924)E_final = res_final.params

------------------------------
## 5. Best Practice: Exploiting Implicit Differentiation
Once your optimization solver functions smoothly, you do not need to rewrite your math code to extract secondary physical phenomena. You can use Implicit Differentiation (jax.grad or jax.jacobian) to compute physical shifts directly from the converged optimization state. [4] 
To find the exact Isotope Shift between $^{20}\text{Ne}$ and $^{22}\text{Ne}$ automatically, you simply take the derivative of the optimized energy function directly with respect to the nuclear_mass parameter:

def nominal_frequency_wrapper(nuclear_mass):
    """Helper that runs the optimizations and outputs the raw scalar frequency."""
    # 1. Optimize states at the current nuclear mass
    opt_3s2 = optimizer.run(initial_guess_params_3s2, nuclear_mass=nuclear_mass).params
    opt_2p4 = optimizer.run(initial_guess_params_2p4, nuclear_mass=nuclear_mass).params
    
    # 2. Compute final energy difference
    delta_E = compute_total_energy(opt_3s2, nuclear_mass) - compute_total_energy(opt_2p4, nuclear_mass)
    h = 6.62607015e-34
    return delta_E / h
# Compute the analytical mass sensitivity of the 633nm line from first principlesmass_sensitivity_derivative = jax.grad(nominal_frequency_wrapper)
# Evaluate the exact gradient at the baseline Neon massfrequency_gradient = mass_sensitivity_derivative(19.9924)

By leveraging jax.grad over the output of your non-linear solver, JAX automatically calculates the exact Normal Mass Shift (NMS) and Specific Mass Shift (SMS) terms derived from the kinetic energy operator without forcing you to write separate code modules. [5] 
------------------------------
If you begin structuring this codebase, let me know if you would like to clarify:

* How to enforce Relativistic Kinetic Balance between the large and small components to avoid variational collapse.
* The exact analytical formulas for Relativistic Gaussian core integrals to populate your baseline matrices.


[1] [https://docs.jax.dev](https://docs.jax.dev/en/latest/key-concepts.html)
[2] [https://apxml.com](https://apxml.com/courses/advanced-jax/chapter-6-large-scale-model-training-jax/introduction-jax-ecosystem-libraries)
[3] [https://www.nature.com](https://www.nature.com/articles/s41524-025-01528-2)
[4] [https://kambale.dev](https://kambale.dev/build-cnn-in-jax)
[5] [https://www.businessinsider.com](https://www.businessinsider.com/facebook-pytorch-beat-google-tensorflow-jax-meta-ai-2022-6)

To successfully use an AI agent to build this relativistic atomic solver, you must treat the implementation like a high-precision engineering project. Because quantum mechanics code can easily suffer from "silent bugs" (where the code runs without crashing but outputs the wrong physics), you must enforce strict, independent validation steps. [1, 2] 
The absolute best way to validate code of this nature is through a combination of Analytical Benchmarking (comparing to known mathematical formulas for simple cases) and Method of Manufactured Solutions.
Here is how you should structure the prompt pipeline and validation steps for your AI agent.
------------------------------
## Phase 1: Core Primitive & Integral Validation
Before trying to solve Neon ($Z=10$), the agent must prove it can calculate basic spatial integrals correctly.
## Step 1: Overlap and Kinetic Energy Integrals

* Agent Task: Implement the functions that construct the one-electron non-relativistic Kinetic Energy matrix and the Overlap matrix using Gaussian-Type Orbitals (GTOs).
* How to Validate:
* Analytical Test: Have the agent run the code for a single isolated Hydrogen atom ($Z=1$) using a standard, well-documented basis set like STO-3G.
   * Pass Criteria: The overlap matrix of a normalized orbital with itself must equal exactly $1.0$. The kinetic energy value must match the exact analytical value listed in standard quantum chemistry benchmarks (like the Szabo & Ostlund textbooks) to 6 decimal places.

## Step 2: The Two-Electron Coulomb Integrals

* Agent Task: Implement the vectorized 4-center electron repulsion integrals using jax.vmap.
* How to Validate:
* Symmetry Test: The Coulomb integrals possess deep permutation symmetries: $(ab\vert{}cd) = (ba\vert{}cd) = (ab\vert{}dc) = (cd\vert{}ab)$. Generate random orbital parameters and assert that swapping indices yields identical values.
   * Asymptotic Test: Push two primitive Gaussians far apart spatially. The repulsion integral between them must asymptotically decay exactly as $1/R$, where $R$ is the distance between their centers.

------------------------------
## Phase 2: Relativistic Physics Validation
Relativistic Dirac-Coulomb solvers fail easily due to "variational collapse," where the energy plunges to negative infinity because the small component of the wavefunction isn't balanced.
## Step 3: Kinetic Balance Enforcer

* Agent Task: Implement the rule that locks the Small component coefficients to the Large component coefficients via the relativistic relation:
$$Q(r) \approx \frac{1}{2c} \left( \frac{d}{dr} + \frac{\kappa}{r} \right) P(r)$$ 
* How to Validate:
* The Free-Particle Limit: Set the nuclear potential ($Z$) to exactly $0$. Calculate the energy eigenvalues.
   * Pass Criteria: The eigenvalues must cleanly split into positive and negative continuum states separated by exactly $2m_e c^2$. If the kinetic balance is wrong, spurious unphysical states will appear inside this energy gap.

------------------------------
## Phase 3: Matrix & Coupling Validation
Neon requires mixing configurations to handle its intermediate coupling regime.
## Step 4: Fine Structure Angular Momentum Matrices

* Agent Task: Implement the Spin-Orbit coupling matrices ($\zeta \mathbf{L} \cdot \mathbf{S}$) and the matrix diagonalization via jnp.linalg.eigh.
* How to Validate:
* Degeneracy Test: Turn off the spin-orbit interaction parameter ($\zeta = 0$). The eigenvalues of a $p$-orbital ($L=1$) matrix must show a perfect 6-fold degeneracy (3 spatial orbitals $\times$ 2 spin states).
   * Landé Interval Rule Test: Turn on spin-orbit coupling for a simple configuration. The energy spacing between levels with total angular momentum $J$ and $J-1$ must be exactly proportional to $J$.

------------------------------
## Phase 4: Optimization Validation
This step verifies that jaxopt is actually navigating the energy landscape to find the true physical minimum.
## Step 5: Direct Energy Minimization Solver

* Agent Task: Wrap the physics engines into an objective function and optimize it using jaxopt.LBFGS.
* How to Validate:
* The Hydrogen Benchmark: Run the entire pipeline on a Hydrogen-like ion (e.g., $He^+$, $Z=2$, with only 1 electron active).
   * Pass Criteria: The converged energy must match the exact analytical Dirac energy formula for a single electron in a Coulomb field:
   $$E = m_e c^2 \left[ 1 + \left( \frac{Z\alpha}{n - \vert{}\kappa\vert{} + \sqrt{\kappa^2 - Z^2\alpha^2}} \right)^2 \right]^{-1/2}$$ 
   If your solver cannot hit the exact analytic Dirac energy for $He^+$, it will fail on Neon.

------------------------------
## Phase 5: Complete Pipeline Validation## Step 6: The Isotope Shift Gradient

* Agent Task: Implement the jax.grad wrapper over the final solver to pull out the mass derivative (Isotope shift).
* How to Validate:
* Finite Difference Cross-Check: Do not trust the automatic gradient immediately. Run the entire optimization twice manually: once with a mass of $M = 20.0$ and once with $M = 22.0$. Calculate the slope manually via central finite differences:
   $$\frac{E(22) - E(20)}{2}$$ 
   * Pass Criteria: The exact scalar value returned by your jax.grad(nominal_frequency_wrapper) function must match this finite-difference calculation to within a very tight tolerance (e.g., $10^{-5}$).

------------------------------
## 🤖 Suggested Strategy for the AI Agent Prompting
Instruct the agent to work in an isolated Test-Driven Development (TDD) manner. Use a master prompt structure like this: [3, 4, 5] 

"You are an expert in computational atomic physics and JAX. Write Step 1 (Overlap and Kinetic Matrix). Along with the implementation, you must write a standalone pytest file that evaluates a single Hydrogen atom against the analytical benchmark values provided in Szabo. Do not proceed to Step 2 until the test suite passes with a strict tolerance of $10^{-6}$."

This modular pipeline prevents the agent from creating a giant, interconnected block of code where errors in the raw integrals hide beneath compensation errors in the optimization step.
------------------------------
Would you like the exact numerical benchmark values for a specific basis set (like STO-3G or cc-pVDZ) for Hydrogen or Helium to give directly to your AI agent as its test criteria?

[1] [https://dev.to](https://dev.to/luffyfanonepiece/ai-agents-dont-crash-they-fail-silently-heres-how-to-catch-it-in-claude-code-13nh)
[2] [https://thenewstack.io](https://thenewstack.io/vibe-then-verify-turning-ai-risk-into-enterprise-reward/)
[3] [https://elite-ai-assisted-coding.dev](https://elite-ai-assisted-coding.dev/p/how-should-you-guide-ai-agents-through)
[4] [https://tweag.github.io](https://tweag.github.io/agentic-coding-handbook/WORKFLOW_TDD/)
[5] [https://www.prodjex.com](https://www.prodjex.com/2025/11/mastering-system-prompts-for-ai-agents/)
