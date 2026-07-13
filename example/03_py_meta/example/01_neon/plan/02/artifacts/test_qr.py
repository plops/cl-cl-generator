import sys
sys.path.append("/workspace/src/cl-cl-generator/example/03_py_meta/example/01_neon/source01")
import jax
import jax.numpy as jnp
import jaxopt
from solver import compute_matrices, compute_G_generic, C_LIGHT

def solve_qr_initial(params, nuclear_mass):
    log_alpha_s = jnp.linspace(jnp.log(0.01), jnp.log(500.0), 8)
    log_alpha_p = jnp.linspace(jnp.log(0.05), jnp.log(100.0), 6)
    alpha_s = jnp.exp(log_alpha_s)
    alpha_p = jnp.exp(log_alpha_p)
    M_au = nuclear_mass * 1822.888
    mu = M_au / (1.0 + M_au)
    
    # s-channel
    _, _, S_s_LL, S_s_SS, V_s_LL, V_s_SS = compute_matrices(alpha_s, 0, -1, 10.0, mu=mu)
    S_s = S_s_LL + S_s_SS
    H_s = V_s_LL + V_s_SS + (4.0 - 2.0 * mu) * (C_LIGHT**2) * S_s_SS
    
    # QR for s-channel: stack x_1s, x_2s, x_5s
    # In params, we store them as a single 8x3 matrix X_s
    X_s = params["X_s"]
    # We want C_s^T S_s C_s = I
    # Let S_s = L L^T (or we can use eigh to find S_s^{1/2})
    # Since S_s is symmetric positive definite, eigh is stable:
    vals, vecs = jnp.linalg.eigh(S_s)
    S_sqrt = jnp.dot(vecs, jnp.dot(jnp.diag(jnp.sqrt(vals)), vecs.T))
    S_inv_sqrt = jnp.dot(vecs, jnp.dot(jnp.diag(1.0 / jnp.sqrt(vals)), vecs.T))
    
    # Orthonormalize S_sqrt X_s using QR
    Q_s, _ = jnp.linalg.qr(jnp.dot(S_sqrt, X_s))
    C_s = jnp.dot(S_inv_sqrt, Q_s)
    c_1s = C_s[:, 0]
    c_2s = C_s[:, 1]
    c_5s = C_s[:, 2]
    
    # p-channel (only 2p occupied)
    _, _, S_p_LL, S_p_SS_1, V_p_LL_1, V_p_SS_1 = compute_matrices(alpha_p, 1, 1, 10.0, mu=mu)
    _, _, _, S_p_SS_2, V_p_LL_2, V_p_SS_2 = compute_matrices(alpha_p, 1, -2, 10.0, mu=mu)
    S_p_locked_avg = S_p_LL + (1.0/3.0)*S_p_SS_1 + (2.0/3.0)*S_p_SS_2
    
    # Normalize c_2p
    x_2p = params["x_2p"]
    c_2p = x_2p / jnp.sqrt(jnp.dot(x_2p, jnp.dot(S_p_locked_avg, x_2p)))
    
    # Energies
    E_1s = jnp.dot(c_1s, jnp.dot(H_s, c_1s))
    E_2s = jnp.dot(c_2s, jnp.dot(H_s, c_2s))
    E_5s = jnp.dot(c_5s, jnp.dot(H_s, c_5s))
    
    H_locked_1 = V_p_LL_1 + V_p_SS_1 + (4.0 - 2.0 * mu) * C_LIGHT**2 * S_p_SS_1
    S_locked_1 = S_p_LL + S_p_SS_1
    E_2p_1 = jnp.dot(c_2p, jnp.dot(H_locked_1, c_2p)) / jnp.dot(c_2p, jnp.dot(S_locked_1, c_2p))
    
    H_locked_2 = V_p_LL_2 + V_p_SS_2 + (4.0 - 2.0 * mu) * C_LIGHT**2 * S_p_SS_2
    S_locked_2 = S_p_LL + S_p_SS_2
    E_2p_2 = jnp.dot(c_2p, jnp.dot(H_locked_2, c_2p)) / jnp.dot(c_2p, jnp.dot(S_locked_2, c_2p))
    
    E_2p = (1.0/3.0)*E_2p_1 + (2.0/3.0)*E_2p_2
    zeta_2p = (2.0/3.0)*(E_2p_2 - E_2p_1)
    
    # Integrals
    G_s = compute_G_generic(alpha_s, 0, alpha_s, 0, alpha_s, 0, alpha_s, 0)
    G_p = compute_G_generic(alpha_p, 1, alpha_p, 1, alpha_p, 1, alpha_p, 1)
    G_ps_coul = compute_G_generic(alpha_p, 1, alpha_p, 1, alpha_s, 0, alpha_s, 0)
    G_ps_exch = compute_G_generic(alpha_p, 1, alpha_s, 0, alpha_p, 1, alpha_s, 0)
    
    J_1s_1s = jnp.einsum("i,j,k,l,ijkl->", c_1s, c_1s, c_1s, c_1s, G_s)
    J_2s_2s = jnp.einsum("i,j,k,l,ijkl->", c_2s, c_2s, c_2s, c_2s, G_s)
    J_1s_2s = jnp.einsum("i,j,k,l,ijkl->", c_1s, c_1s, c_2s, c_2s, G_s)
    K_1s_2s = jnp.einsum("i,j,k,l,ijkl->", c_1s, c_2s, c_1s, c_2s, G_s)
    J_1s_5s = jnp.einsum("i,j,k,l,ijkl->", c_1s, c_1s, c_5s, c_5s, G_s)
    K_1s_5s = jnp.einsum("i,j,k,l,ijkl->", c_1s, c_5s, c_1s, c_5s, G_s)
    J_2s_5s = jnp.einsum("i,j,k,l,ijkl->", c_2s, c_2s, c_5s, c_5s, G_s)
    K_2s_5s = jnp.einsum("i,j,k,l,ijkl->", c_2s, c_5s, c_2s, c_5s, G_s)
    
    J_2p_2p = jnp.einsum("i,j,k,l,ijkl->", c_2p, c_2p, c_2p, c_2p, G_p)
    K_2p_2p = J_2p_2p
    
    J_2p_1s = jnp.einsum("i,j,k,l,ijkl->", c_2p, c_2p, c_1s, c_1s, G_ps_coul)
    K_2p_1s = jnp.einsum("i,j,k,l,ijkl->", c_2p, c_1s, c_2p, c_1s, G_ps_exch)
    J_2p_2s = jnp.einsum("i,j,k,l,ijkl->", c_2p, c_2p, c_2s, c_2s, G_ps_coul)
    K_2p_2s = jnp.einsum("i,j,k,l,ijkl->", c_2p, c_2s, c_2p, c_2s, G_ps_exch)
    J_2p_5s = jnp.einsum("i,j,k,l,ijkl->", c_2p, c_2p, c_5s, c_5s, G_ps_coul)
    K_2p_5s = jnp.einsum("i,j,k,l,ijkl->", c_2p, c_5s, c_2p, c_5s, G_ps_exch)
    
    E_ee = (J_1s_1s + J_2s_2s + 10.0*J_2p_2p - 4.0*K_2p_2p + 
            4.0*J_1s_2s - 2.0*K_1s_2s + 2.0*J_1s_5s - K_1s_5s + 2.0*J_2s_5s - K_2s_5s +
            10.0*J_2p_1s - 5.0*K_2p_1s + 10.0*J_2p_2s - 5.0*K_2p_2s + 5.0*J_2p_5s - 2.5*K_2p_5s)
    
    E_elec = 2.0*E_1s + 2.0*E_2s + 5.0*E_2p + E_5s + E_ee
    H_SO = jnp.array([[E_elec - 0.5 * zeta_2p, (1.0/jnp.sqrt(2.0)) * zeta_2p],
                      [(1.0/jnp.sqrt(2.0)) * zeta_2p, E_elec]])
    eigvals = jnp.linalg.eigh(H_SO)
    return eigvals[0][0]

from solver import get_initial_guesses
x_1s, x_2s, x_5s, x_2p, x_3p = get_initial_guesses(20.18)
X_s = jnp.stack([x_1s, x_2s, x_5s], axis=1)
params = {"X_s": X_s, "x_2p": x_2p}

print("Running QR-based LBFGS:")
solver = jaxopt.LBFGS(fun=solve_qr_initial, maxiter=200, tol=1e-10)
res = solver.run(params, 20.18)
print(f"QR LBFGS: value = {res.state.value}, error = {res.state.error}")
