import sys
sys.path.append("/workspace/src/cl-cl-generator/example/03_py_meta/example/01_neon/source01")
import jax
import jax.numpy as jnp
import jaxopt
from solver import initial_state_energy, final_state_energy, get_initial_guesses

print("Initial state convergence:")
x_1s, x_2s, x_5s, x_2p, x_3p = get_initial_guesses(20.18)
params_initial = dict(x_1s=x_1s, x_2s=x_2s, x_2p=x_2p, x_5s=x_5s)

solver_initial = jaxopt.LBFGS(fun=initial_state_energy, maxiter=1, tol=1e-10)
state_initial = solver_initial.init_state(params_initial, 20.18)
params = params_initial
for i in range(500):
    params, state_initial = solver_initial.update(params, state_initial, 20.18)
    if i % 50 == 0 or i > 450:
        grad_val = jax.grad(initial_state_energy)(params, 20.18)
        grad_norm = jnp.sqrt(sum(jnp.sum(g**2) for g in grad_val.values()))
        print(f"Step {i}: Energy = {state_initial.value}, Grad norm = {grad_norm}")

print("\nFinal state convergence:")
params_final = dict(x_1s=x_1s, x_2s=x_2s, x_2p=x_2p, x_3p=x_3p)
solver_final = jaxopt.LBFGS(fun=final_state_energy, maxiter=1, tol=1e-10)
state_final = solver_final.init_state(params_final, 20.18)
params = params_final
for i in range(500):
    params, state_final = solver_final.update(params, state_final, 20.18)
    if i % 50 == 0 or i > 450:
        grad_val = jax.grad(final_state_energy)(params, 20.18)
        grad_norm = jnp.sqrt(sum(jnp.sum(g**2) for g in grad_val.values()))
        print(f"Step {i}: Energy = {state_final.value}, Grad norm = {grad_norm}")
