import sys
sys.path.append("/workspace/src/cl-cl-generator/example/03_py_meta/example/01_neon/source01")
import numpy as np
import scipy.linalg
import jax
import jax.numpy as jnp
from solver import compute_matrices, safe_I_k

def get_scipy_initial_guesses(nuclear_mass):
    log_alpha_s = np.linspace(np.log(0.01), np.log(500.0), 8)
    log_alpha_p = np.linspace(np.log(0.05), np.log(100.0), 6)
    alpha_s = np.exp(log_alpha_s)
    alpha_p = np.exp(log_alpha_p)
    M_au = nuclear_mass * 1822.888
    mu = M_au / (1.0 + M_au)
    C_LIGHT = 137.035999
    
    # s-channel
    _, _, S_s_LL, S_s_SS, V_s_LL, V_s_SS = compute_matrices(alpha_s, 0, -1, 10.0, mu=mu)
    S_s = np.array(S_s_LL + S_s_SS)
    H_s = np.array(V_s_LL + V_s_SS + (4.0 - 2.0 * mu) * (C_LIGHT**2) * S_s_SS)
    
    # Solve generalized eigenvalue problem
    eigvals_s, eigvecs_s = scipy.linalg.eigh(H_s, S_s)
    
    x_1s = eigvecs_s[:, 0]
    x_2s = eigvecs_s[:, 1]
    x_5s = eigvecs_s[:, 4]
    
    # p-channel
    _, _, S_p_LL, S_p_SS_1, V_p_LL_1, V_p_SS_1 = compute_matrices(alpha_p, 1, 1, 10.0, mu=mu)
    _, _, _, S_p_SS_2, V_p_LL_2, V_p_SS_2 = compute_matrices(alpha_p, 1, -2, 10.0, mu=mu)
    S_p = np.array(S_p_LL + (1.0/3.0)*S_p_SS_1 + (2.0/3.0)*S_p_SS_2)
    
    H_p_1 = V_p_LL_1 + V_p_SS_1 + (4.0 - 2.0 * mu) * C_LIGHT**2 * S_p_SS_1
    H_p_2 = V_p_LL_2 + V_p_SS_2 + (4.0 - 2.0 * mu) * C_LIGHT**2 * S_p_SS_2
    H_p = np.array((1.0/3.0)*H_p_1 + (2.0/3.0)*H_p_2)
    
    eigvals_p, eigvecs_p = scipy.linalg.eigh(H_p, S_p)
    
    x_2p = eigvecs_p[:, 0]
    x_3p = eigvecs_p[:, 1]
    
    return x_1s, x_2s, x_5s, x_2p, x_3p

def count_nodes(c, is_s):
    if is_s:
        log_alpha = jnp.linspace(jnp.log(0.01), jnp.log(500.0), 8)
        l = 0
    else:
        log_alpha = jnp.linspace(jnp.log(0.05), jnp.log(100.0), 6)
        l = 1
    alpha = jnp.exp(log_alpha)
    Np = len(alpha)
    C_coeffs = []
    for i in range(Np):
        val = (jax.vmap(lambda a: safe_I_k(2 * l + 2, 2.0 * a)))(jnp.array([alpha[i]]))
        C_coeffs.append(1.0 / jnp.sqrt(val[0]))
    
    r = jnp.linspace(0.01, 5.0, 1000)
    P = jnp.zeros_like(r)
    for i in range(Np):
        g_i = C_coeffs[i] * (r ** (l + 1)) * jnp.exp(-alpha[i] * (r ** 2))
        P += c[i] * g_i
    
    signs = jnp.sign(P)
    sign_changes = jnp.sum(signs[:-1] != signs[1:])
    return sign_changes

x_1s, x_2s, x_5s, x_2p, x_3p = get_scipy_initial_guesses(20.18)
print("SciPy initial guess node counts:")
print(f"1s nodes = {count_nodes(x_1s, True)}")
print(f"2s nodes = {count_nodes(x_2s, True)}")
print(f"5s nodes = {count_nodes(x_5s, True)}")
print(f"2p nodes = {count_nodes(x_2p, False)}")
print(f"3p nodes = {count_nodes(x_3p, False)}")
