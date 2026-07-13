import sys
sys.path.append("/workspace/src/cl-cl-generator/example/03_py_meta/example/01_neon/source01")
import jax
import jax.numpy as jnp
import jaxopt
from solver import initial_state_energy, get_initial_guesses

x_1s, x_2s, x_5s, x_2p, x_3p = get_initial_guesses(20.18)
params_initial = dict(x_1s=x_1s, x_2s=x_2s, x_2p=x_2p, x_5s=x_5s)

print("Running jaxopt.LBFGS with maxiter=2000:")
solver = jaxopt.LBFGS(fun=initial_state_energy, maxiter=2000, tol=1e-10)
res = solver.run(params_initial, 20.18)
grad_val = jax.grad(initial_state_energy)(res.params, 20.18)
grad_norm = jnp.sqrt(sum(jnp.sum(g**2) for g in grad_val.values()))
print(f"LBFGS 2000: value = {res.state.value}, state.error = {res.state.error}, computed grad_norm = {grad_norm}")
