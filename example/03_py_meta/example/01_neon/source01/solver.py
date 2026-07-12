import jax
import jax.numpy as jnp
import jax.scipy.special as jsp
import jaxopt

C_LIGHT = 137.036


def safe_I_k(k, a):
    k_safe = jnp.where(k > -1.0, k, 1.0)
    val = (
        0.5
        * jnp.power(a, -0.5 * (k_safe + 1.0))
        * jnp.exp(jsp.gammaln(0.5 * (k_safe + 1.0)))
    )
    return jnp.where(k > -1.0, val, 0.0)


def compute_matrices(exponents, l, kappa, Z, c=C_LIGHT, mu=1.0):
    N = len(exponents)
    alpha = jnp.array(exponents)
    I_norm = (jax.vmap(lambda a: safe_I_k(2 * l + 2, 2.0 * a)))((alpha))
    C = 1.0 / jnp.sqrt(I_norm)
    alpha_grid = alpha[:, None] + alpha[None, :]
    I_grid = (jax.vmap(jax.vmap(lambda a: safe_I_k(2 * l + 2, a))))((alpha_grid))
    S_LL = C[:, None] * C[None, :] * I_grid
    A = l + 1 + kappa
    B = -2.0 * alpha
    I_2l = (jax.vmap(jax.vmap(lambda a: safe_I_k(2 * l, a))))((alpha_grid))
    I_2l2 = (jax.vmap(jax.vmap(lambda a: safe_I_k(2 * l + 2, a))))((alpha_grid))
    I_2l4 = (jax.vmap(jax.vmap(lambda a: safe_I_k(2 * l + 4, a))))((alpha_grid))
    term1 = A * A * I_2l
    term2 = A * (B[:, None] + B[None, :]) * I_2l2
    term3 = B[:, None] * B[None, :] * I_2l4
    S_SS = C[:, None] * C[None, :] / (4.0 * c**2) * (term1 + term2 + term3)
    I_2l1 = (jax.vmap(jax.vmap(lambda a: safe_I_k(2 * l + 1, a))))((alpha_grid))
    V_LL = -1.0 * Z * C[:, None] * C[None, :] * I_2l1
    I_2l_minus_1 = (jax.vmap(jax.vmap(lambda a: safe_I_k(2 * l - 1, a))))((alpha_grid))
    I_2l3 = (jax.vmap(jax.vmap(lambda a: safe_I_k(2 * l + 3, a))))((alpha_grid))
    term_v1 = A * A * I_2l_minus_1
    term_v2 = A * (B[:, None] + B[None, :]) * I_2l1
    term_v3 = B[:, None] * B[None, :] * I_2l3
    V_SS = (
        -1.0
        * Z
        * (C[:, None] * C[None, :] / (4.0 * c**2))
        * (term_v1 + term_v2 + term_v3)
    )
    H = jnp.block(
        [
            [V_LL + mu * c**2 * S_LL, 2.0 * c**2 * S_SS],
            [2.0 * c**2 * S_SS, V_SS - mu * c**2 * S_SS],
        ]
    )
    S_overlap = jnp.block(
        [
            [
                S_LL,
                jnp.zeros(
                    (
                        N,
                        N,
                    )
                ),
            ],
            [
                jnp.zeros(
                    (
                        N,
                        N,
                    )
                ),
                S_SS,
            ],
        ]
    )
    return (
        H,
        S_overlap,
        S_LL,
        S_SS,
        V_LL,
        V_SS,
    )


def compute_G_generic(alpha_a, l_a, alpha_b, l_b, alpha_c, l_c, alpha_d, l_d):
    C_a = 1.0 / jnp.sqrt(
        (jax.vmap(lambda a: safe_I_k(2 * l_a + 2, 2.0 * a)))((alpha_a))
    )
    C_b = 1.0 / jnp.sqrt(
        (jax.vmap(lambda a: safe_I_k(2 * l_b + 2, 2.0 * a)))((alpha_b))
    )
    C_c = 1.0 / jnp.sqrt(
        (jax.vmap(lambda a: safe_I_k(2 * l_c + 2, 2.0 * a)))((alpha_c))
    )
    C_d = 1.0 / jnp.sqrt(
        (jax.vmap(lambda a: safe_I_k(2 * l_d + 2, 2.0 * a)))((alpha_d))
    )
    a_grid = alpha_a[:, None, None, None]
    b_grid = alpha_b[None, :, None, None]
    c_grid = alpha_c[None, None, :, None]
    d_grid = alpha_d[None, None, None, :]
    p = a_grid + b_grid
    q = c_grid + d_grid
    prim = 2.0 * jnp.pi**2.5 / (p * q * jnp.sqrt(p + q))
    G = (
        C_a[:, None, None, None]
        * C_b[None, :, None, None]
        * C_c[None, None, :, None]
        * C_d[None, None, None, :]
        * (1.0 / (1.6e1 * jnp.pi**2))
        * prim
    )
    return G


def initial_state_energy(params, nuclear_mass):
    log_alpha_s = jnp.linspace(jnp.log(0.1), jnp.log(1.0e2), 4)
    log_alpha_p = jnp.linspace(jnp.log(0.1), jnp.log(5.0e1), 4)
    x_2p = params["x_2p"]
    x_5s = params["x_5s"]
    alpha_s = jnp.exp(log_alpha_s)
    alpha_p = jnp.exp(log_alpha_p)
    M_au = nuclear_mass * 1822.888
    mu = M_au / (1.0 + M_au)
    _, _, S_LL, S_SS_1, V_LL_1, V_SS_1 = compute_matrices(alpha_p, 1, 1, 1.0e1, mu=mu)
    _, _, _, S_SS_2, V_LL_2, V_SS_2 = compute_matrices(alpha_p, 1, -2, 1.0e1, mu=mu)
    Np = len(alpha_p)
    S_locked_avg = S_LL + 1.0 / 3.0 * S_SS_1 + 2.0 / 3.0 * S_SS_2
    c_2p = x_2p / jnp.sqrt(jnp.dot(x_2p, jnp.dot(S_locked_avg, x_2p)))
    H_locked_1 = V_LL_1 + V_SS_1 + (4.0 - 2.0 * mu) * C_LIGHT**2 * S_SS_1
    S_locked_1 = S_LL + S_SS_1
    E_2p_1 = jnp.dot(c_2p, jnp.dot(H_locked_1, c_2p)) / jnp.dot(
        c_2p, jnp.dot(S_locked_1, c_2p)
    )
    H_locked_2 = V_LL_2 + V_SS_2 + (4.0 - 2.0 * mu) * C_LIGHT**2 * S_SS_2
    S_locked_2 = S_LL + S_SS_2
    E_2p_2 = jnp.dot(c_2p, jnp.dot(H_locked_2, c_2p)) / jnp.dot(
        c_2p, jnp.dot(S_locked_2, c_2p)
    )
    E_2p = 1.0 / 3.0 * E_2p_1 + 2.0 / 3.0 * E_2p_2
    zeta_2p = 2.0 / 3.0 * (E_2p_2 - E_2p_1)
    _, _, S_5s_LL, S_5s_SS, V_5s_LL, V_5s_SS = compute_matrices(
        alpha_s, 0, -1, 1.0e1, mu=mu
    )
    Ns = len(alpha_s)
    S_5s_locked = S_5s_LL + S_5s_SS
    c_5s = x_5s / jnp.sqrt(jnp.dot(x_5s, jnp.dot(S_5s_locked, x_5s)))
    H_5s_locked = V_5s_LL + V_5s_SS + (4.0 - 2.0 * mu) * C_LIGHT**2 * S_5s_SS
    E_5s = jnp.dot(c_5s, jnp.dot(H_5s_locked, c_5s)) / jnp.dot(
        c_5s, jnp.dot(S_5s_locked, c_5s)
    )
    G_2p_2p = compute_G_generic(alpha_p, 1, alpha_p, 1, alpha_p, 1, alpha_p, 1)
    G_2p_5s_coul = compute_G_generic(alpha_p, 1, alpha_p, 1, alpha_s, 0, alpha_s, 0)
    G_2p_5s_exch = compute_G_generic(alpha_p, 1, alpha_s, 0, alpha_p, 1, alpha_s, 0)
    J_2p_2p = jnp.einsum("i,j,k,l,ijkl->", c_2p, c_2p, c_2p, c_2p, G_2p_2p)
    K_2p_2p = J_2p_2p
    J_2p_5s = jnp.einsum("i,j,k,l,ijkl->", c_2p, c_2p, c_5s, c_5s, G_2p_5s_coul)
    K_2p_5s = jnp.einsum("i,j,k,l,ijkl->", c_2p, c_5s, c_2p, c_5s, G_2p_5s_exch)
    E_elec = (
        5.0 * E_2p
        + E_5s
        + 1.0e1 * J_2p_2p
        + -4.0 * K_2p_2p
        + 5.0 * J_2p_5s
        + -2.5 * K_2p_5s
    )
    H_SO = jnp.array(
        [
            [E_elec - 0.5 * zeta_2p, 1.0 / jnp.sqrt(2.0) * zeta_2p],
            [1.0 / jnp.sqrt(2.0) * zeta_2p, E_elec],
        ]
    )
    eigvals = jnp.linalg.eigh(H_SO)
    return eigvals[0][0]


def final_state_energy(params, nuclear_mass):
    log_alpha_s = jnp.linspace(jnp.log(0.1), jnp.log(1.0e2), 4)
    log_alpha_p = jnp.linspace(jnp.log(0.1), jnp.log(5.0e1), 4)
    x_2p = params["x_2p"]
    x_3p = params["x_3p"]
    alpha_s = jnp.exp(log_alpha_s)
    alpha_p = jnp.exp(log_alpha_p)
    M_au = nuclear_mass * 1822.888
    mu = M_au / (1.0 + M_au)
    _, _, S_LL, S_SS_1, V_LL_1, V_SS_1 = compute_matrices(alpha_p, 1, 1, 1.0e1, mu=mu)
    _, _, _, S_SS_2, V_LL_2, V_SS_2 = compute_matrices(alpha_p, 1, -2, 1.0e1, mu=mu)
    Np = len(alpha_p)
    S_locked_avg = S_LL + 1.0 / 3.0 * S_SS_1 + 2.0 / 3.0 * S_SS_2
    c_2p = x_2p / jnp.sqrt(jnp.dot(x_2p, jnp.dot(S_locked_avg, x_2p)))
    H_locked_1 = V_LL_1 + V_SS_1 + (4.0 - 2.0 * mu) * C_LIGHT**2 * S_SS_1
    S_locked_1 = S_LL + S_SS_1
    E_2p_1 = jnp.dot(c_2p, jnp.dot(H_locked_1, c_2p)) / jnp.dot(
        c_2p, jnp.dot(S_locked_1, c_2p)
    )
    H_locked_2 = V_LL_2 + V_SS_2 + (4.0 - 2.0 * mu) * C_LIGHT**2 * S_SS_2
    S_locked_2 = S_LL + S_SS_2
    E_2p_2 = jnp.dot(c_2p, jnp.dot(H_locked_2, c_2p)) / jnp.dot(
        c_2p, jnp.dot(S_locked_2, c_2p)
    )
    E_2p = 1.0 / 3.0 * E_2p_1 + 2.0 / 3.0 * E_2p_2
    zeta_2p = 2.0 / 3.0 * (E_2p_2 - E_2p_1)
    _, _, S_3p_LL, S_3p_SS_1, V_3p_LL_1, V_3p_SS_1 = compute_matrices(
        alpha_p, 1, 1, 1.0e1, mu=mu
    )
    _, _, _, S_3p_SS_2, V_3p_LL_2, V_3p_SS_2 = compute_matrices(
        alpha_p, 1, -2, 1.0e1, mu=mu
    )
    S_3p_locked_avg = S_3p_LL + 1.0 / 3.0 * S_3p_SS_1 + 2.0 / 3.0 * S_3p_SS_2
    c_3p = x_3p / jnp.sqrt(jnp.dot(x_3p, jnp.dot(S_3p_locked_avg, x_3p)))
    H_3p_locked_1 = V_3p_LL_1 + V_3p_SS_1 + (4.0 - 2.0 * mu) * C_LIGHT**2 * S_3p_SS_1
    S_3p_locked_1 = S_3p_LL + S_3p_SS_1
    E_3p_1 = jnp.dot(c_3p, jnp.dot(H_3p_locked_1, c_3p)) / jnp.dot(
        c_3p, jnp.dot(S_3p_locked_1, c_3p)
    )
    H_3p_locked_2 = V_3p_LL_2 + V_3p_SS_2 + (4.0 - 2.0 * mu) * C_LIGHT**2 * S_3p_SS_2
    S_3p_locked_2 = S_3p_LL + S_3p_SS_2
    E_3p_2 = jnp.dot(c_3p, jnp.dot(H_3p_locked_2, c_3p)) / jnp.dot(
        c_3p, jnp.dot(S_3p_locked_2, c_3p)
    )
    E_3p = 1.0 / 3.0 * E_3p_1 + 2.0 / 3.0 * E_3p_2
    zeta_3p = 2.0 / 3.0 * (E_3p_2 - E_3p_1)
    G_2p_2p = compute_G_generic(alpha_p, 1, alpha_p, 1, alpha_p, 1, alpha_p, 1)
    G_2p_3p_coul = G_2p_2p
    J_2p_2p = jnp.einsum("i,j,k,l,ijkl->", c_2p, c_2p, c_2p, c_2p, G_2p_2p)
    K_2p_2p = J_2p_2p
    J_2p_3p = jnp.einsum("i,j,k,l,ijkl->", c_2p, c_2p, c_3p, c_3p, G_2p_3p_coul)
    K_2p_3p = jnp.einsum("i,j,k,l,ijkl->", c_2p, c_3p, c_2p, c_3p, G_2p_2p)
    E_elec = (
        5.0 * E_2p
        + E_3p
        + 1.0e1 * J_2p_2p
        + -4.0 * K_2p_2p
        + 5.0 * J_2p_3p
        + -2.5 * K_2p_3p
    )
    H_SO = jnp.array(
        [
            [E_elec - 0.5 * zeta_2p, 0.5 * zeta_3p],
            [0.5 * zeta_3p, E_elec + 0.5 * zeta_2p],
        ]
    )
    eigvals = jnp.linalg.eigh(H_SO)
    return eigvals[0][0]


def nominal_frequency_wrapper(nuclear_mass):
    init_params_initial = dict(x_2p=jnp.ones(4), x_5s=jnp.ones(4))
    init_params_final = dict(x_2p=jnp.ones(4), x_3p=jnp.ones(4))
    solver_initial = jaxopt.LBFGS(
        fun=initial_state_energy, maxiter=150, tol=1.0e-10, implicit_diff=True
    )
    res_initial = solver_initial.run(init_params_initial, nuclear_mass)
    E_initial = initial_state_energy(res_initial.params, nuclear_mass)
    solver_final = jaxopt.LBFGS(
        fun=final_state_energy, maxiter=150, tol=1.0e-10, implicit_diff=True
    )
    res_final = solver_final.run(init_params_final, nuclear_mass)
    E_final = final_state_energy(res_final.params, nuclear_mass)
    delta_E = E_initial - E_final
    HARTREE_TO_THZ = 1.0
    nu_0 = delta_E * HARTREE_TO_THZ
    return nu_0
