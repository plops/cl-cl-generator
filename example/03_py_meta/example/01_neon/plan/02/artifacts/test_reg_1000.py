import sys
sys.path.append("/workspace/src/cl-cl-generator/example/03_py_meta/example/01_neon/source01")
import jax
import jax.numpy as jnp
import jaxopt
from solver import initial_state_energy, get_initial_guesses, compute_matrices

def initial_state_energy_reg(params, nuclear_mass):
    E = initial_state_energy(params, nuclear_mass)
    
    # Extract params
    x_1s = params["x_1s"]
    x_2s = params["x_2s"]
    x_5s = params["x_5s"]
    
    # Overlap matrix
    log_alpha_s = jnp.linspace(jnp.log(0.01), jnp.log(500.0), 8)
    alpha_s = jnp.exp(log_alpha_s)
    M_au = nuclear_mass * 1822.888
    mu = M_au / (1.0 + M_au)
    _, _, S_s_LL, S_s_SS, _, _ = compute_matrices(alpha_s, 0, -1, 10.0, mu=mu)
    S_s = S_s_LL + S_s_SS
    
    # Normalize inputs for regularization
    n_1s = x_1s / jnp.sqrt(jnp.dot(x_1s, jnp.dot(S_s, x_1s)))
    n_2s = x_2s / jnp.sqrt(jnp.dot(x_2s, jnp.dot(S_s, x_2s)))
    n_5s = x_5s / jnp.sqrt(jnp.dot(x_5s, jnp.dot(S_s, x_5s)))
    
    # Penalty for non-orthogonality
    penalty = 1.0 * (
        jnp.dot(n_1s, jnp.dot(S_s, n_2s))**2 +
        jnp.dot(n_1s, jnp.dot(S_s, n_5s))**2 +
        jnp.dot(n_2s, jnp.dot(S_s, n_5s))**2
    )
    return E + penalty

x_1s, x_2s, x_5s, x_2p, x_3p = get_initial_guesses(20.18)
params_initial = dict(x_1s=x_1s, x_2s=x_2s, x_2p=x_2p, x_5s=x_5s)

print("Running regularized LBFGS for 1000 iterations:")
solver = jaxopt.LBFGS(fun=initial_state_energy_reg, maxiter=1000, tol=1e-10)
res = solver.run(params_initial, 20.18)
print(f"Regularized LBFGS 1000: value = {res.state.value}, state.error = {res.state.error}")
