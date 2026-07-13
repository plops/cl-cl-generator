# Optimization Bottleneck Breakdown: Variational Collapse & Numerical Ill-Conditioning

This document outlines the findings from our convergence analysis for the ab initio 10-electron Neon transition solver, detailing the physical and mathematical bottlenecks discovered and the design for Option B (First-Principles QR Parameterization).

---

## 1. Physical & Mathematical Bottlenecks Discovered

### A. Variational Collapse of the Excited $5s$ Rydberg State
* **The Symptom**: The final state (occupied $1s^2 2s^2 2p^5 3p^1$) converges to the machine precision tolerance of $10^{-12}$ in fewer than 1000 iterations. In contrast, the initial state (occupied $1s^2 2s^2 2p^5 5s^1$) fails to converge even after 2500 iterations, with the gradient norm stagnating around $10^{-3}$ to $10^{-5}$.
* **The Cause**: The initial state contains the $5s$ excited valence orbital, which resides above the unoccupied (virtual) $3s$ and $4s$ states in energy. When we perform Gram-Schmidt projection, we only orthogonalize $5s$ against the core $1s$ and $2s$ states. Therefore, the energy minimization step pulls the $5s$ orbital parameters variationally down to represent the lower-energy $3s$ state (variational collapse). The optimizer struggles in a highly non-convex, rugged landscape trying to restructure the orbital nodes (from 4 nodes to 2 nodes).

### B. Extreme Basis Ill-Conditioning
* **Exponents**: The required basis exponents range from $0.01$ to $500.0$.
* **Condition Number**: The overlap matrix $\mathbf{S}$ has eigenvalues spanning from $10^{-8}$ to $10^2$, yielding a condition number of $\approx 10^{10}$.
* **Impact**: Differentiating through manual matrix normalization (e.g., dividing by $\sqrt{x^\dagger \mathbf{S} x}$) is extremely sensitive to numerical noise, especially in single-precision float representation, leading to wild gradient oscillations.

### C. Scale Invariance Redundancy
* **Invariance**: The physical energy is completely invariant under the scaling of raw parameters $x \to \alpha x$ due to the normalization inside the sequential Gram-Schmidt projection.
* **Redundancy**: This scale invariance creates flat directions (zero curvature) in the optimization landscape, which makes LBFGS converge extremely slowly.

---

## 2. Option B Design: First-Principles QR Parameterization

To resolve the redundancies and scale invariance of Gram-Schmidt, we parameterize the orthonormalized coefficient matrices directly using a differentiable QR decomposition. This is mathematically identical to sequential Gram-Schmidt but is numerically stable and avoids division by parameter norms.

### Mathematical Formulation
For $s$-channel, we want three orthonormal coefficient vectors $c_{1s}, c_{2s}, c_{5s} \in \mathbb{R}^8$ satisfying:
$$\mathbf{C}_s^\dagger \mathbf{S}_s \mathbf{C}_s = \mathbf{I}_{3 \times 3}$$

1. Compute the eigenvalue decomposition of $\mathbf{S}_s$:
   $$\mathbf{S}_s = \mathbf{V}_s \mathbf{\Lambda}_s \mathbf{V}_s^\dagger$$
2. Construct the symmetric square root matrices:
   $$\mathbf{S}_s^{1/2} = \mathbf{V}_s \mathbf{\Lambda}_s^{1/2} \mathbf{V}_s^\dagger, \quad \mathbf{S}_s^{-1/2} = \mathbf{V}_s \mathbf{\Lambda}_s^{-1/2} \mathbf{V}_s^\dagger$$
3. Let $\mathbf{X}_s \in \mathbb{R}^{8 \times 3}$ be the unconstrained parameter matrix optimized by JAXopt.
4. Orthonormalize the matrix $\mathbf{S}_s^{1/2} \mathbf{X}_s$ using JAX's differentiable QR decomposition:
   $$\mathbf{S}_s^{1/2} \mathbf{X}_s = \mathbf{Q}_s \mathbf{R}_s \implies \mathbf{Q}_s = \text{QR}(\mathbf{S}_s^{1/2} \mathbf{X}_s)$$
   where $\mathbf{Q}_s \in \mathbb{R}^{8 \times 3}$ has orthonormal columns ($\mathbf{Q}_s^\dagger \mathbf{Q}_s = \mathbf{I}_{3 \times 3}$).
5. The physical orthonormalized orbital coefficients are given by:
   $$\mathbf{C}_s = \mathbf{S}_s^{-1/2} \mathbf{Q}_s$$
   Indeed:
   $$\mathbf{C}_s^\dagger \mathbf{S}_s \mathbf{C}_s = \mathbf{Q}_s^\dagger \mathbf{S}_s^{-1/2} \mathbf{S}_s \mathbf{S}_s^{-1/2} \mathbf{Q}_s = \mathbf{Q}_s^\dagger \mathbf{Q}_s = \mathbf{I}_{3 \times 3}$$

This parameterization:
1. Eliminates the scale invariance (since QR handles scaling of columns of $\mathbf{X}_s$ uniquely via $R_s$).
2. Avoids divisions by parameter-dependent norms in the computational graph.
3. Keeps the parameter space well-conditioned and orthonormal at every single step of optimization.
