import sys
sys.path.append("/workspace/src/cl-cl-generator/example/03_py_meta/example/01_neon/source01")
import jax
import jax.numpy as jnp
import jaxopt

from solver import (
    initial_state_energy,
    final_state_energy,
    get_initial_guesses,
    compute_matrices
)

def initial_state_energy_reg(params, nuclear_mass):
    E = initial_state_energy(params, nuclear_mass)
    x_1s = params["x_1s"]
    x_2s = params["x_2s"]
    x_5s = params["x_5s"]
    log_alpha_s = jnp.linspace(jnp.log(0.01), jnp.log(500.0), 8)
    alpha_s = jnp.exp(log_alpha_s)
    M_au = nuclear_mass * 1822.888
    mu = M_au / (1.0 + M_au)
    _, _, S_s_LL, S_s_SS, _, _ = compute_matrices(alpha_s, 0, -1, 10.0, mu=mu)
    S_s = S_s_LL + S_s_SS
    n_1s = x_1s / jnp.sqrt(jnp.dot(x_1s, jnp.dot(S_s, x_1s)))
    n_2s = x_2s / jnp.sqrt(jnp.dot(x_2s, jnp.dot(S_s, x_2s)))
    n_5s = x_5s / jnp.sqrt(jnp.dot(x_5s, jnp.dot(S_s, x_5s)))
    penalty = 1.0 * (
        jnp.dot(n_1s, jnp.dot(S_s, n_2s))**2 +
        jnp.dot(n_1s, jnp.dot(S_s, n_5s))**2 +
        jnp.dot(n_2s, jnp.dot(S_s, n_5s))**2
    )
    return E + penalty

def final_state_energy_reg(params, nuclear_mass):
    E = final_state_energy(params, nuclear_mass)
    x_1s = params["x_1s"]
    x_2s = params["x_2s"]
    x_2p = params["x_2p"]
    x_3p = params["x_3p"]
    
    # s-channel
    log_alpha_s = jnp.linspace(jnp.log(0.01), jnp.log(500.0), 8)
    alpha_s = jnp.exp(log_alpha_s)
    M_au = nuclear_mass * 1822.888
    mu = M_au / (1.0 + M_au)
    _, _, S_s_LL, S_s_SS, _, _ = compute_matrices(alpha_s, 0, -1, 10.0, mu=mu)
    S_s = S_s_LL + S_s_SS
    n_1s = x_1s / jnp.sqrt(jnp.dot(x_1s, jnp.dot(S_s, x_1s)))
    n_2s = x_2s / jnp.sqrt(jnp.dot(x_2s, jnp.dot(S_s, x_2s)))
    
    # p-channel
    log_alpha_p = jnp.linspace(jnp.log(0.05), jnp.log(100.0), 6)
    alpha_p = jnp.exp(log_alpha_p)
    _, _, S_p_LL, S_p_SS_1, _, _ = compute_matrices(alpha_p, 1, 1, 10.0, mu=mu)
    _, _, _, S_p_SS_2, _, _ = compute_matrices(alpha_p, 1, -2, 10.0, mu=mu)
    S_p_locked_avg = S_p_LL + (1.0/3.0)*S_p_SS_1 + (2.0/3.0)*S_p_SS_2
    n_2p = x_2p / jnp.sqrt(jnp.dot(x_2p, jnp.dot(S_p_locked_avg, x_2p)))
    n_3p = x_3p / jnp.sqrt(jnp.dot(x_3p, jnp.dot(S_p_locked_avg, x_3p)))
    
    penalty = 1.0 * (
        jnp.dot(n_1s, jnp.dot(S_s, n_2s))**2 +
        jnp.dot(n_2p, jnp.dot(S_p_locked_avg, n_3p))**2
    )
    return E + penalty

x_1s, x_2s, x_5s, x_2p, x_3p = get_initial_guesses(20.18)
init_params_initial = dict(x_1s=x_1s, x_2s=x_2s, x_2p=x_2p, x_5s=x_5s)
init_params_final = dict(x_1s=x_1s, x_2s=x_2s, x_2p=x_2p, x_3p=x_3p)

for m in [20.0, 21.0, 22.0]:
    print(f"\n--- Mass = {m} ---")
    solver_initial = jaxopt.LBFGS(fun=initial_state_energy_reg, maxiter=800, tol=1e-10)
    res_initial = solver_initial.run(init_params_initial, m)
    print(f"Initial State: energy = {res_initial.state.value}, error = {res_initial.state.error}, iterations = {res_initial.state.iter_num}")
    
    solver_final = jaxopt.LBFGS(fun=final_state_energy_reg, maxiter=800, tol=1e-10)
    res_final = solver_final.run(init_params_final, m)
    print(f"Final State: energy = {res_final.state.value}, error = {res_final.state.error}, iterations = {res_final.state.iter_num}")
