import sys
sys.path.append("/workspace/src/cl-cl-generator/example/03_py_meta/example/01_neon/source01")
import jax
import jax.numpy as jnp
import jaxopt
from solver import initial_state_energy, get_initial_guesses

x_1s, x_2s, x_5s, x_2p, x_3p = get_initial_guesses(20.18)
params_initial = dict(x_1s=x_1s, x_2s=x_2s, x_2p=x_2p, x_5s=x_5s)

solver = jaxopt.LBFGS(fun=initial_state_energy, maxiter=1, tol=1e-10)
state = solver.init_state(params_initial, 20.18)
params = params_initial
for i in range(300):
    params, state = solver.update(params, state, 20.18)
    if i % 10 == 0:
        print(f"Step {i}: Energy = {state.value}, Error = {state.error}")
