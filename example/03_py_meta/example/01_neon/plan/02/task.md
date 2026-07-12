# Tasks: Pure First-Principles Relativistic Neon Solver (Plan 02)

---

## Task 1: Update `gen01.lisp` with 10-Electron SOAS Model

Modify `gen01.lisp` to implement the pure first-principles 10-electron energy minimization for Neon.

### Requirements
1. **Basis Exponents**:
   * Change `log_alpha_s` to 8 elements from $0.01$ to $500.0$:
     `(jnp.linspace (jnp.log 0.01) (jnp.log 500.0) 8)`
   * Change `log_alpha_p` to 6 elements from $0.05$ to $100.0$:
     `(jnp.linspace (jnp.log 0.05) (jnp.log 100.0) 6)`
2. **Gram-Schmidt Orthogonalization Function**:
   * Implement a helper function `orthogonalize_gs(vectors, S)` or write it inline:
     - For $s$-channel:
       - $c_{1s}$ is normalized $x_{1s}$.
       - $c_{2s}$ is $x_{2s}$ projected orthogonal to $c_{1s}$ and normalized.
       - $c_{5s}$ is $x_{5s}$ projected orthogonal to $c_{1s}$ and $c_{2s}$ and normalized.
     - For $p$-channel:
       - $c_{2p}$ is normalized $x_{2p}$.
       - $c_{3p}$ is $x_{3p}$ projected orthogonal to $c_{2p}$ and normalized.
3. **10-Electron Hamiltonian (Z=10.0)**:
   - Call `compute_matrices` with `Z=10.0` for all states. No effective nuclear charges are allowed.
4. **Energy Function Expressions**:
   - In `initial_state_energy`, calculate the 10-electron energy:
     `E_elec = 2*E_1s + 2*E_2s + 5*E_2p + E_5s + E_ee`
     where `E_ee` contains all Coulomb ($J$) and Exchange ($K$) terms for the 45 pairs.
   - In `final_state_energy`, calculate the 10-electron energy:
     `E_elec = 2*E_1s + 2*E_2s + 5*E_2p + E_3p + E_ee`
     where `E_ee` contains all Coulomb ($J$) and Exchange ($K$) terms for the 45 pairs.
5. **Initial Parameter Guesses**:
   - `x_1s`, `x_2s`, `x_5s`, `x_2p` must be initialized (e.g. ones).
6. **Correct Frequency Conversion**:
   - Set `HARTREE_TO_THZ = 6.5796839e6` in `nominal_frequency_wrapper`.

---

## Task 2: Re-generate and Verify Code
Execute `gen01.lisp` using SBCL and verify that the Python files are correctly written.

---

## Task 3: Run Verification Suite
Run `./setup01.sh cpu test` to verify that mathematical invariants (normalization, symmetries, decay) are satisfied.

---

## Task 4: Run Solver and Analyze Results
Run `./setup01.sh cpu run`. Verify that:
1. The transition energy $\Delta E = E(2p^5 5s) - E(2p^5 3p)$ is positive.
2. The frequency is positive and matches the physical neon transition ($\approx 473$ THz).
3. The plots of the radial wavefunctions show the physical node structures:
   - $1s$ (0 nodes)
   - $2s$ (1 node)
   - $5s$ (4 nodes)
   - $2p$ (0 nodes in large component amplitude $P$, wait, $P(r) \propto r^{l+1} = r^2$, which has 0 nodes)
   - $3p$ (1 node in large component $P$)
