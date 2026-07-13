import sys
sys.path.append("/workspace/src/cl-cl-generator/example/03_py_meta/example/01_neon/source01")
import jax
import jax.numpy as jnp
import jaxopt
from solver import initial_state_energy, final_state_energy, get_initial_guesses

x_1s, x_2s, x_5s, x_2p, x_3p = get_initial_guesses(20.18)
params_initial = dict(x_1s=x_1s, x_2s=x_2s, x_2p=x_2p, x_5s=x_5s)

print("Testing jaxopt.ScipyMinimize(method='L-BFGS-B') for initial state:")
solver = jaxopt.ScipyMinimize(fun=initial_state_energy, method="L-BFGS-B", maxiter=200)
res = solver.run(params_initial, 20.18)
grad_val = jax.grad(initial_state_energy)(res.params, 20.18)
grad_norm = jnp.sqrt(sum(jnp.sum(g**2) for g in grad_val.values()))
print(f"L-BFGS-B: converged = {res.state.success}, fun = {res.state.fun_val}, grad_norm = {grad_norm}, iterations = {res.state.iter_num}")

print("\nTesting jaxopt.ScipyMinimize(method='BFGS') for initial state:")
solver_bfgs = jaxopt.ScipyMinimize(fun=initial_state_energy, method="BFGS", maxiter=200)
res_bfgs = solver_bfgs.run(params_initial, 20.18)
grad_val_bfgs = jax.grad(initial_state_energy)(res_bfgs.params, 20.18)
grad_norm_bfgs = jnp.sqrt(sum(jnp.sum(g**2) for g in grad_val_bfgs.values()))
print(f"BFGS: converged = {res_bfgs.state.success}, fun = {res_bfgs.state.fun_val}, grad_norm = {grad_norm_bfgs}, iterations = {res_bfgs.state.iter_num}")
