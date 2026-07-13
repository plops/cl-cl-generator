from jax import config
config.update("jax_enable_x64", True)

import sys
sys.path.append("/workspace/src/cl-cl-generator/example/03_py_meta/example/01_neon/source01")
import jax
import jax.numpy as jnp
import jaxopt

from check_runs import initial_state_energy_reg, final_state_energy_reg
from solver import get_initial_guesses

x_1s, x_2s, x_5s, x_2p, x_3p = get_initial_guesses(20.18)
init_params_initial = dict(
    x_1s=x_1s.astype(jnp.float64),
    x_2s=x_2s.astype(jnp.float64),
    x_2p=x_2p.astype(jnp.float64),
    x_5s=x_5s.astype(jnp.float64)
)

for m in [20.0, 21.0, 22.0]:
    print(f"\n--- Mass = {m} (history_size=15) ---")
    solver_initial = jaxopt.LBFGS(fun=initial_state_energy_reg, maxiter=1000, tol=1e-10, history_size=15)
    res_initial = solver_initial.run(init_params_initial, m)
    print(f"Initial State: energy = {res_initial.state.value}, error = {res_initial.state.error}, iterations = {res_initial.state.iter_num}")
