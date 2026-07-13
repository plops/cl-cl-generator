from jax import config
config.update("jax_enable_x64", True)

import sys
sys.path.append("/workspace/src/cl-cl-generator/example/03_py_meta/example/01_neon/source01")
import jax
import jax.numpy as jnp
import jaxopt

from check_runs import initial_state_energy_reg, final_state_energy_reg
from solver import get_initial_guesses

# 1. Pre-convergence at module level for mass 20.18
print("Pre-converging initial state...")
x_1s, x_2s, x_5s, x_2p, x_3p = get_initial_guesses(20.18)
init_params_initial = dict(
    x_1s=x_1s.astype(jnp.float64),
    x_2s=x_2s.astype(jnp.float64),
    x_2p=x_2p.astype(jnp.float64),
    x_5s=x_5s.astype(jnp.float64)
)
init_params_final = dict(
    x_1s=x_1s.astype(jnp.float64),
    x_2s=x_2s.astype(jnp.float64),
    x_2p=x_2p.astype(jnp.float64),
    x_3p=x_3p.astype(jnp.float64)
)

pre_solver_initial = jaxopt.LBFGS(fun=initial_state_energy_reg, maxiter=2500, tol=1e-12)
pre_res_initial = pre_solver_initial.run(init_params_initial, 20.18)
print(f"Pre-convergence initial state: energy = {pre_res_initial.state.value:.12f}, error = {pre_res_initial.state.error:.6e}, iterations = {pre_res_initial.state.iter_num}")

print("Pre-converging final state...")
pre_solver_final = jaxopt.LBFGS(fun=final_state_energy_reg, maxiter=2500, tol=1e-12)
pre_res_final = pre_solver_final.run(init_params_final, 20.18)
print(f"Pre-convergence final state: energy = {pre_res_final.state.value:.12f}, error = {pre_res_final.state.error:.6e}, iterations = {pre_res_final.state.iter_num}")

# Save the pre-converged parameters
converged_params_initial = pre_res_initial.params
converged_params_final = pre_res_final.params

def nominal_frequency_wrapper_preconverged(nuclear_mass):
    jax.debug.print("\nEvaluating wrapper at Mass = {}", nuclear_mass)
    
    # Run a small LBFGS starting from the pre-converged parameters
    solver_initial = jaxopt.LBFGS(fun=initial_state_energy_reg, maxiter=100, tol=1e-12)
    res_initial = solver_initial.run(converged_params_initial, nuclear_mass)
    E_initial = initial_state_energy_reg(res_initial.params, nuclear_mass)
    jax.debug.print("  Initial State: energy = {}, error = {}, iterations = {}", E_initial, res_initial.state.error, res_initial.state.iter_num)
    
    solver_final = jaxopt.LBFGS(fun=final_state_energy_reg, maxiter=100, tol=1e-12)
    res_final = solver_final.run(converged_params_final, nuclear_mass)
    E_final = final_state_energy_reg(res_final.params, nuclear_mass)
    jax.debug.print("  Final State: energy = {}, error = {}, iterations = {}", E_final, res_final.state.error, res_final.state.iter_num)
    
    delta_E = E_initial - E_final
    HARTREE_TO_THZ = 6.5796839e6
    return delta_E * HARTREE_TO_THZ

m = 21.0
grad_fn = jax.grad(nominal_frequency_wrapper_preconverged)
print("\n--- Computing jax.grad with Pre-convergence ---")
grad_val = grad_fn(m)
print(f"\njax.grad: {grad_val}")

print("\n--- Computing Finite Differences ---")
nu_plus = nominal_frequency_wrapper_preconverged(22.0)
nu_minus = nominal_frequency_wrapper_preconverged(20.0)
fd = (nu_plus - nu_minus) / 2.0
print(f"\nnu(20.0): {nu_minus} THz")
print(f"nu(22.0): {nu_plus} THz")
print(f"Finite Difference slope: {fd}")
print(f"Difference: {abs(grad_val - fd)}")
print(f"Relative difference: {abs(grad_val - fd) / abs(grad_val)}")

assert jnp.allclose(grad_val, fd, rtol=1e-3, atol=1e-3)
print("SUCCESS: test_isotope_shift_cross_check passed with Pre-convergence!")
