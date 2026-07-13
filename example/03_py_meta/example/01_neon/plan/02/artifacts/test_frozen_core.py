from jax import config
config.update("jax_enable_x64", True)

import sys
sys.path.append("/workspace/src/cl-cl-generator/example/03_py_meta/example/01_neon/source01")
import jax
import jax.numpy as jnp
import jaxopt

from solver import compute_matrices, compute_G_generic, C_LIGHT, get_initial_guesses

# We define the energy functions under the Frozen Core Approximation
def initial_state_energy_frozen(params, nuclear_mass):
    # Fixed core orbitals are computed from the core Hamiltonian at the given nuclear_mass
    log_alpha_s = jnp.linspace(jnp.log(0.01), jnp.log(500.0), 8)
    log_alpha_p = jnp.linspace(jnp.log(0.05), jnp.log(100.0), 6)
    alpha_s = jnp.exp(log_alpha_s)
    alpha_p = jnp.exp(log_alpha_p)
    M_au = nuclear_mass * 1822.888
    mu = M_au / (1.0 + M_au)
    
    # Core s-channel Hamiltonian
    _, _, S_s_LL, S_s_SS, V_s_LL, V_s_SS = compute_matrices(alpha_s, 0, -1, 10.0, mu=mu)
    S_s = S_s_LL + S_s_SS
    H_s = V_s_LL + V_s_SS + (4.0 - 2.0 * mu) * (C_LIGHT**2) * S_s_SS
    
    S_s_val, S_s_vec = jnp.linalg.eigh(S_s)
    S_s_inv_sqrt = jnp.dot(S_s_vec, jnp.dot(jnp.diag(1.0 / jnp.sqrt(S_s_val)), S_s_vec.T))
    H_s_std = jnp.dot(S_s_inv_sqrt, jnp.dot(H_s, S_s_inv_sqrt))
    _, eigvecs_s = jnp.linalg.eigh(H_s_std)
    c_eig_s = jnp.dot(S_s_inv_sqrt, eigvecs_s)
    
    # Frozen 1s and 2s
    c_1s = c_eig_s[:, 0]
    c_2s = c_eig_s[:, 1]
    
    # Valence s-orbital 5s
    x_5s = params["x_5s"]
    # Gram-Schmidt for 5s against frozen 1s and 2s
    proj_5s = x_5s - jnp.dot(c_1s, jnp.dot(S_s, x_5s)) * c_1s - jnp.dot(c_2s, jnp.dot(S_s, x_5s)) * c_2s
    c_5s = proj_5s / jnp.sqrt(jnp.dot(proj_5s, jnp.dot(S_s, proj_5s)))
    
    # Valence p-orbital 2p
    x_2p = params["x_2p"]
    _, _, S_p_LL, S_p_SS_1, V_p_LL_1, V_p_SS_1 = compute_matrices(alpha_p, 1, 1, 10.0, mu=mu)
    _, _, _, S_p_SS_2, V_p_LL_2, V_p_SS_2 = compute_matrices(alpha_p, 1, -2, 10.0, mu=mu)
    S_p_locked_avg = S_p_LL + (1.0/3.0)*S_p_SS_1 + (2.0/3.0)*S_p_SS_2
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

def final_state_energy_frozen(params, nuclear_mass):
    log_alpha_s = jnp.linspace(jnp.log(0.01), jnp.log(500.0), 8)
    log_alpha_p = jnp.linspace(jnp.log(0.05), jnp.log(100.0), 6)
    alpha_s = jnp.exp(log_alpha_s)
    alpha_p = jnp.exp(log_alpha_p)
    M_au = nuclear_mass * 1822.888
    mu = M_au / (1.0 + M_au)
    
    # Core s-channel Hamiltonian
    _, _, S_s_LL, S_s_SS, V_s_LL, V_s_SS = compute_matrices(alpha_s, 0, -1, 10.0, mu=mu)
    S_s = S_s_LL + S_s_SS
    H_s = V_s_LL + V_s_SS + (4.0 - 2.0 * mu) * (C_LIGHT**2) * S_s_SS
    
    S_s_val, S_s_vec = jnp.linalg.eigh(S_s)
    S_s_inv_sqrt = jnp.dot(S_s_vec, jnp.dot(jnp.diag(1.0 / jnp.sqrt(S_s_val)), S_s_vec.T))
    H_s_std = jnp.dot(S_s_inv_sqrt, jnp.dot(H_s, S_s_inv_sqrt))
    _, eigvecs_s = jnp.linalg.eigh(H_s_std)
    c_eig_s = jnp.dot(S_s_inv_sqrt, eigvecs_s)
    
    # Frozen 1s and 2s
    c_1s = c_eig_s[:, 0]
    c_2s = c_eig_s[:, 1]
    
    # Valence p-orbitals 2p and 3p
    x_2p = params["x_2p"]
    x_3p = params["x_3p"]
    
    _, _, S_p_LL, S_p_SS_1, V_p_LL_1, V_p_SS_1 = compute_matrices(alpha_p, 1, 1, 10.0, mu=mu)
    _, _, _, S_p_SS_2, V_p_LL_2, V_p_SS_2 = compute_matrices(alpha_p, 1, -2, 10.0, mu=mu)
    S_p_locked_avg = S_p_LL + (1.0/3.0)*S_p_SS_1 + (2.0/3.0)*S_p_SS_2
    
    c_2p = x_2p / jnp.sqrt(jnp.dot(x_2p, jnp.dot(S_p_locked_avg, x_2p)))
    proj_3p = x_3p - jnp.dot(c_2p, jnp.dot(S_p_locked_avg, x_3p)) * c_2p
    c_3p = proj_3p / jnp.sqrt(jnp.dot(proj_3p, jnp.dot(S_p_locked_avg, proj_3p)))
    
    # Energies
    E_1s = jnp.dot(c_1s, jnp.dot(H_s, c_1s))
    E_2s = jnp.dot(c_2s, jnp.dot(H_s, c_2s))
    
    H_locked_1 = V_p_LL_1 + V_p_SS_1 + (4.0 - 2.0 * mu) * C_LIGHT**2 * S_p_SS_1
    S_locked_1 = S_p_LL + S_p_SS_1
    E_2p_1 = jnp.dot(c_2p, jnp.dot(H_locked_1, c_2p)) / jnp.dot(c_2p, jnp.dot(S_locked_1, c_2p))
    E_3p_1 = jnp.dot(c_3p, jnp.dot(H_locked_1, c_3p)) / jnp.dot(c_3p, jnp.dot(S_locked_1, c_3p))
    
    H_locked_2 = V_p_LL_2 + V_p_SS_2 + (4.0 - 2.0 * mu) * C_LIGHT**2 * S_p_SS_2
    S_locked_2 = S_p_LL + S_p_SS_2
    E_2p_2 = jnp.dot(c_2p, jnp.dot(H_locked_2, c_2p)) / jnp.dot(c_2p, jnp.dot(S_locked_2, c_2p))
    E_3p_2 = jnp.dot(c_3p, jnp.dot(H_locked_2, c_3p)) / jnp.dot(c_3p, jnp.dot(S_locked_2, c_3p))
    
    E_2p = (1.0/3.0)*E_2p_1 + (2.0/3.0)*E_2p_2
    E_3p = (1.0/3.0)*E_3p_1 + (2.0/3.0)*E_3p_2
    zeta_2p = (2.0/3.0)*(E_2p_2 - E_2p_1)
    zeta_3p = (2.0/3.0)*(E_3p_2 - E_3p_1)
    
    # Integrals
    G_s = compute_G_generic(alpha_s, 0, alpha_s, 0, alpha_s, 0, alpha_s, 0)
    G_p = compute_G_generic(alpha_p, 1, alpha_p, 1, alpha_p, 1, alpha_p, 1)
    G_ps_coul = compute_G_generic(alpha_p, 1, alpha_p, 1, alpha_s, 0, alpha_s, 0)
    G_ps_exch = compute_G_generic(alpha_p, 1, alpha_s, 0, alpha_p, 1, alpha_s, 0)
    
    J_1s_1s = jnp.einsum("i,j,k,l,ijkl->", c_1s, c_1s, c_1s, c_1s, G_s)
    J_2s_2s = jnp.einsum("i,j,k,l,ijkl->", c_2s, c_2s, c_2s, c_2s, G_s)
    J_1s_2s = jnp.einsum("i,j,k,l,ijkl->", c_1s, c_1s, c_2s, c_2s, G_s)
    K_1s_2s = jnp.einsum("i,j,k,l,ijkl->", c_1s, c_2s, c_1s, c_2s, G_s)
    
    J_2p_2p = jnp.einsum("i,j,k,l,ijkl->", c_2p, c_2p, c_2p, c_2p, G_p)
    K_2p_2p = J_2p_2p
    J_3p_3p = jnp.einsum("i,j,k,l,ijkl->", c_3p, c_3p, c_3p, c_3p, G_p)
    K_3p_3p = J_3p_3p
    J_2p_3p = jnp.einsum("i,j,k,l,ijkl->", c_2p, c_2p, c_3p, c_3p, G_p)
    K_2p_3p = jnp.einsum("i,j,k,l,ijkl->", c_2p, c_3p, c_2p, c_3p, G_p)
    
    J_2p_1s = jnp.einsum("i,j,k,l,ijkl->", c_2p, c_2p, c_1s, c_1s, G_ps_coul)
    K_2p_1s = jnp.einsum("i,j,k,l,ijkl->", c_2p, c_1s, c_2p, c_1s, G_ps_exch)
    J_2p_2s = jnp.einsum("i,j,k,l,ijkl->", c_2p, c_2p, c_2s, c_2s, G_ps_coul)
    K_2p_2s = jnp.einsum("i,j,k,l,ijkl->", c_2p, c_2s, c_2p, c_2s, G_ps_exch)
    
    J_3p_1s = jnp.einsum("i,j,k,l,ijkl->", c_3p, c_3p, c_1s, c_1s, G_ps_coul)
    K_3p_1s = jnp.einsum("i,j,k,l,ijkl->", c_3p, c_1s, c_3p, c_1s, G_ps_exch)
    J_3p_2s = jnp.einsum("i,j,k,l,ijkl->", c_3p, c_3p, c_2s, c_2s, G_ps_coul)
    K_3p_2s = jnp.einsum("i,j,k,l,ijkl->", c_3p, c_2s, c_3p, c_2s, G_ps_exch)
    
    E_ee = (J_1s_1s + J_2s_2s + 10.0*J_2p_2p - 4.0*K_2p_2p + J_3p_3p +
            4.0*J_1s_2s - 2.0*K_1s_2s +
            10.0*J_2p_1s - 5.0*K_2p_1s + 10.0*J_2p_2s - 5.0*K_2p_2s +
            2.0*J_3p_1s - K_3p_1s + 2.0*J_3p_2s - K_3p_2s +
            10.0*J_2p_3p - 5.0*K_2p_3p)
    
    E_elec = 2.0*E_1s + 2.0*E_2s + 5.0*E_2p + E_3p + E_ee
    # J=0 final state: no spin-orbit split since we diagonalize or just take the eigenvalues
    # The plan says for J=0: delta_E = E_initial - E_final, and E_final is just E_elec.
    return E_elec

def nominal_frequency_wrapper_frozen(nuclear_mass):
    x_1s_init, x_2s_init, x_5s_init, x_2p_init, x_3p_init = get_initial_guesses(20.18)
    init_params_initial = dict(
        x_2p=x_2p_init.astype(jnp.float64),
        x_5s=x_5s_init.astype(jnp.float64)
    )
    init_params_final = dict(
        x_2p=x_2p_init.astype(jnp.float64),
        x_3p=x_3p_init.astype(jnp.float64)
    )
    
    solver_initial = jaxopt.LBFGS(fun=initial_state_energy_frozen, maxiter=200, tol=1e-10, implicit_diff=True)
    res_initial = solver_initial.run(init_params_initial, nuclear_mass)
    E_initial = initial_state_energy_frozen(res_initial.params, nuclear_mass)
    jax.debug.print("  Initial State: energy = {}, error = {}, iterations = {}", E_initial, res_initial.state.error, res_initial.state.iter_num)
    
    solver_final = jaxopt.LBFGS(fun=final_state_energy_frozen, maxiter=200, tol=1e-10, implicit_diff=True)
    res_final = solver_final.run(init_params_final, nuclear_mass)
    E_final = final_state_energy_frozen(res_final.params, nuclear_mass)
    jax.debug.print("  Final State: energy = {}, error = {}, iterations = {}", E_final, res_final.state.error, res_final.state.iter_num)
    
    delta_E = E_initial - E_final
    HARTREE_TO_THZ = 6.5796839e6
    return delta_E * HARTREE_TO_THZ

m = 21.0
grad_fn = jax.grad(nominal_frequency_wrapper_frozen)
print("--- Computing jax.grad with Frozen Core ---")
grad_val = grad_fn(m)
print(f"\njax.grad: {grad_val}")

print("\n--- Computing Finite Differences ---")
nu_plus = nominal_frequency_wrapper_frozen(22.0)
nu_minus = nominal_frequency_wrapper_frozen(20.0)
fd = (nu_plus - nu_minus) / 2.0
print(f"\nnu(20.0): {nu_minus} THz")
print(f"nu(22.0): {nu_plus} THz")
print(f"Finite Difference slope: {fd}")
print(f"Difference: {abs(grad_val - fd)}")
print(f"Relative difference: {abs(grad_val - fd) / abs(grad_val)}")

assert jnp.allclose(grad_val, fd, rtol=1e-3, atol=1e-3)
print("SUCCESS: test_isotope_shift_cross_check passed with Frozen Core!")
