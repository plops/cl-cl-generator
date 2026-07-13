import sys
sys.path.append("/workspace/src/cl-cl-generator/example/03_py_meta/example/01_neon/source01")
import jax
import jax.numpy as jnp
import jaxopt

from check_runs import initial_state_energy_reg, final_state_energy_reg
from solver import get_initial_guesses, get_physical_coefficients, safe_I_k

x_1s, x_2s, x_5s, x_2p, x_3p = get_initial_guesses(20.18)
init_params_initial = dict(x_1s=x_1s, x_2s=x_2s, x_2p=x_2p, x_5s=x_5s)

def count_nodes(c, is_s):
    if is_s:
        log_alpha = jnp.linspace(jnp.log(0.01), jnp.log(500.0), 8)
    else:
        log_alpha = jnp.linspace(jnp.log(0.05), jnp.log(100.0), 6)
    alpha = jnp.exp(log_alpha)
    Np = len(alpha)
    C_coeffs = []
    for i in range(Np):
        val = (jax.vmap(lambda a: safe_I_k(2 * 0 + 2, 2.0 * a)))(jnp.array([alpha[i]]))
        C_coeffs.append(1.0 / jnp.sqrt(val[0]))
    
    r = jnp.linspace(0.01, 5.0, 1000)
    P = jnp.zeros_like(r)
    for i in range(Np):
        g_i = C_coeffs[i] * (r ** 1) * jnp.exp(-alpha[i] * (r ** 2))
        P += c[i] * g_i
    
    # Count sign changes in P
    signs = jnp.sign(P)
    sign_changes = jnp.sum(signs[:-1] != signs[1:])
    return sign_changes

for m in [20.0, 21.0, 22.0]:
    solver_initial = jaxopt.LBFGS(fun=initial_state_energy_reg, maxiter=800, tol=1e-10)
    res_initial = solver_initial.run(init_params_initial, m)
    c_1s, c_2s, c_5s, c_2p = get_physical_coefficients(res_initial.params, m, True)
    
    nodes_1s = count_nodes(c_1s, True)
    nodes_2s = count_nodes(c_2s, True)
    nodes_5s = count_nodes(c_5s, True)
    print(f"Mass = {m}: 1s nodes = {nodes_1s}, 2s nodes = {nodes_2s}, 5s nodes = {nodes_5s}, Energy = {res_initial.state.value}")
