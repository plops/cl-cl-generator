import sys
sys.path.append("/workspace/src/cl-cl-generator/example/03_py_meta/example/01_neon/source01")
import jax.numpy as jnp
from solver import compute_matrices

for m in [20.0, 21.0, 22.0]:
    M_au = m * 1822.888
    mu = M_au / (1.0 + M_au)
    log_alpha_s = jnp.linspace(jnp.log(0.01), jnp.log(500.0), 8)
    alpha_s = jnp.exp(log_alpha_s)
    
    _, _, S_s_LL, S_s_SS, V_s_LL, V_s_SS = compute_matrices(alpha_s, 0, -1, 10.0, mu=mu)
    S_s = S_s_LL + S_s_SS
    C_LIGHT = 137.035999
    H_s = V_s_LL + V_s_SS + (4.0 - 2.0 * mu) * (C_LIGHT**2) * S_s_SS
    
    S_s_val, S_s_vec = jnp.linalg.eigh(S_s)
    S_s_inv_sqrt = jnp.dot(S_s_vec, jnp.dot(jnp.diag(1.0 / jnp.sqrt(S_s_val)), S_s_vec.T))
    H_s_std = jnp.dot(S_s_inv_sqrt, jnp.dot(H_s, S_s_inv_sqrt))
    eigvals, _ = jnp.linalg.eigh(H_s_std)
    print(f"Mass = {m}: core s-channel eigenvalues = {eigvals}")
