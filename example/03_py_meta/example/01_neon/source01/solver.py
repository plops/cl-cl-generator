import jax
import jax.numpy as jnp
import jax.scipy.special as jsp
import jaxopt

jax.config.update("jax_enable_x64", True)
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
    log_alpha_s = jnp.linspace(jnp.log(1.0e-2), jnp.log(5.0e2), 8)
    log_alpha_p = jnp.linspace(jnp.log(5.0e-2), jnp.log(1.0e2), 6)
    X_s = params["X_s"]
    x_2p = params["x_2p"]
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
    _, _, S_s_LL, S_s_SS, V_s_LL, V_s_SS = compute_matrices(
        alpha_s, 0, -1, 1.0e1, mu=mu
    )
    Ns = len(alpha_s)
    S_s = S_s_LL + S_s_SS
    H_s = V_s_LL + V_s_SS + (4.0 - 2.0 * mu) * C_LIGHT**2 * S_s_SS
    M_s = jnp.dot(jnp.transpose(X_s), jnp.dot(S_s, X_s))
    vals_s, vecs_s = jnp.linalg.eigh(M_s)
    M_s_inv_sqrt = jnp.dot(
        vecs_s, jnp.dot(jnp.diag(1.0 / jnp.sqrt(vals_s)), jnp.transpose(vecs_s))
    )
    C_s = jnp.dot(X_s, M_s_inv_sqrt)
    c_1s = C_s[:, 0]
    c_2s = C_s[:, 1]
    c_5s = C_s[:, 2]
    E_1s = jnp.dot(c_1s, jnp.dot(H_s, c_1s))
    E_2s = jnp.dot(c_2s, jnp.dot(H_s, c_2s))
    E_5s = jnp.dot(c_5s, jnp.dot(H_s, c_5s))
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
    E_ee = (
        J_1s_1s
        + J_2s_2s
        + 1.0e1 * J_2p_2p
        + -4.0 * K_2p_2p
        + 4.0 * J_1s_2s
        + -2.0 * K_1s_2s
        + 2.0 * J_1s_5s
        + -1.0 * K_1s_5s
        + 2.0 * J_2s_5s
        + -1.0 * K_2s_5s
        + 1.0e1 * J_2p_1s
        + -5.0 * K_2p_1s
        + 1.0e1 * J_2p_2s
        + -5.0 * K_2p_2s
        + 5.0 * J_2p_5s
        + -2.5 * K_2p_5s
    )
    E_elec = 2.0 * E_1s + 2.0 * E_2s + 5.0 * E_2p + E_5s + E_ee
    H_SO = jnp.array(
        [
            [E_elec - 0.5 * zeta_2p, 1.0 / jnp.sqrt(2.0) * zeta_2p],
            [1.0 / jnp.sqrt(2.0) * zeta_2p, E_elec],
        ]
    )
    eigvals = jnp.linalg.eigh(H_SO)
    norm_penalty = 1.0 * (
        (jnp.dot(X_s[:, 0], X_s[:, 0]) - 1.0) ** 2
        + (jnp.dot(X_s[:, 1], X_s[:, 1]) - 1.0) ** 2
        + (jnp.dot(X_s[:, 2], X_s[:, 2]) - 1.0) ** 2
        + (jnp.dot(x_2p, x_2p) - 1.0) ** 2
    )
    return eigvals[0][0] + norm_penalty


def final_state_energy(params, nuclear_mass):
    log_alpha_s = jnp.linspace(jnp.log(1.0e-2), jnp.log(5.0e2), 8)
    log_alpha_p = jnp.linspace(jnp.log(5.0e-2), jnp.log(1.0e2), 6)
    X_s = params["X_s"]
    X_p = params["X_p"]
    alpha_s = jnp.exp(log_alpha_s)
    alpha_p = jnp.exp(log_alpha_p)
    M_au = nuclear_mass * 1822.888
    mu = M_au / (1.0 + M_au)
    _, _, S_s_LL, S_s_SS, V_s_LL, V_s_SS = compute_matrices(
        alpha_s, 0, -1, 1.0e1, mu=mu
    )
    S_s = S_s_LL + S_s_SS
    H_s = V_s_LL + V_s_SS + (4.0 - 2.0 * mu) * C_LIGHT**2 * S_s_SS
    M_s = jnp.dot(jnp.transpose(X_s), jnp.dot(S_s, X_s))
    vals_s, vecs_s = jnp.linalg.eigh(M_s)
    M_s_inv_sqrt = jnp.dot(
        vecs_s, jnp.dot(jnp.diag(1.0 / jnp.sqrt(vals_s)), jnp.transpose(vecs_s))
    )
    C_s = jnp.dot(X_s, M_s_inv_sqrt)
    c_1s = C_s[:, 0]
    c_2s = C_s[:, 1]
    E_1s = jnp.dot(c_1s, jnp.dot(H_s, c_1s))
    E_2s = jnp.dot(c_2s, jnp.dot(H_s, c_2s))
    _, _, S_LL, S_SS_1, V_LL_1, V_SS_1 = compute_matrices(alpha_p, 1, 1, 1.0e1, mu=mu)
    _, _, _, S_SS_2, V_LL_2, V_SS_2 = compute_matrices(alpha_p, 1, -2, 1.0e1, mu=mu)
    Np = len(alpha_p)
    S_locked_avg = S_LL + 1.0 / 3.0 * S_SS_1 + 2.0 / 3.0 * S_SS_2
    M_p = jnp.dot(jnp.transpose(X_p), jnp.dot(S_locked_avg, X_p))
    vals_p, vecs_p = jnp.linalg.eigh(M_p)
    M_p_inv_sqrt = jnp.dot(
        vecs_p, jnp.dot(jnp.diag(1.0 / jnp.sqrt(vals_p)), jnp.transpose(vecs_p))
    )
    C_p = jnp.dot(X_p, M_p_inv_sqrt)
    c_2p = C_p[:, 0]
    c_3p = C_p[:, 1]
    H_locked_1 = V_LL_1 + V_SS_1 + (4.0 - 2.0 * mu) * C_LIGHT**2 * S_SS_1
    S_locked_1 = S_LL + S_SS_1
    E_2p_1 = jnp.dot(c_2p, jnp.dot(H_locked_1, c_2p)) / jnp.dot(
        c_2p, jnp.dot(S_locked_1, c_2p)
    )
    E_3p_1 = jnp.dot(c_3p, jnp.dot(H_locked_1, c_3p)) / jnp.dot(
        c_3p, jnp.dot(S_locked_1, c_3p)
    )
    H_locked_2 = V_LL_2 + V_SS_2 + (4.0 - 2.0 * mu) * C_LIGHT**2 * S_SS_2
    S_locked_2 = S_LL + S_SS_2
    E_2p_2 = jnp.dot(c_2p, jnp.dot(H_locked_2, c_2p)) / jnp.dot(
        c_2p, jnp.dot(S_locked_2, c_2p)
    )
    E_3p_2 = jnp.dot(c_3p, jnp.dot(H_locked_2, c_3p)) / jnp.dot(
        c_3p, jnp.dot(S_locked_2, c_3p)
    )
    E_2p = 1.0 / 3.0 * E_2p_1 + 2.0 / 3.0 * E_2p_2
    E_3p = 1.0 / 3.0 * E_3p_1 + 2.0 / 3.0 * E_3p_2
    zeta_2p = 2.0 / 3.0 * (E_2p_2 - E_2p_1)
    zeta_3p = 2.0 / 3.0 * (E_3p_2 - E_3p_1)
    G_s = compute_G_generic(alpha_s, 0, alpha_s, 0, alpha_s, 0, alpha_s, 0)
    G_p = compute_G_generic(alpha_p, 1, alpha_p, 1, alpha_p, 1, alpha_p, 1)
    G_ps_coul = compute_G_generic(alpha_p, 1, alpha_p, 1, alpha_s, 0, alpha_s, 0)
    G_ps_exch = compute_G_generic(alpha_p, 1, alpha_s, 0, alpha_p, 1, alpha_s, 0)
    J_1s_1s = jnp.einsum("i,j,k,l,ijkl->", c_1s, c_1s, c_1s, c_1s, G_s)
    J_2s_2s = jnp.einsum("i,j,k,l,ijkl->", c_2s, c_2s, c_2s, c_2s, G_s)
    J_1s_2s = jnp.einsum("i,j,k,l,ijkl->", c_1s, c_1s, c_2s, c_2s, G_s)
    K_1s_2s = jnp.einsum("i,j,k,l,ijkl->", c_1s, c_2s, c_1s, c_2s, G_s)
    J_1s_3p = jnp.einsum("i,j,k,l,ijkl->", c_3p, c_3p, c_1s, c_1s, G_ps_coul)
    K_1s_3p = jnp.einsum("i,j,k,l,ijkl->", c_3p, c_1s, c_3p, c_1s, G_ps_exch)
    J_2s_3p = jnp.einsum("i,j,k,l,ijkl->", c_3p, c_3p, c_2s, c_2s, G_ps_coul)
    K_2s_3p = jnp.einsum("i,j,k,l,ijkl->", c_3p, c_2s, c_3p, c_2s, G_ps_exch)
    J_2p_2p = jnp.einsum("i,j,k,l,ijkl->", c_2p, c_2p, c_2p, c_2p, G_p)
    K_2p_2p = J_2p_2p
    J_2p_1s = jnp.einsum("i,j,k,l,ijkl->", c_2p, c_2p, c_1s, c_1s, G_ps_coul)
    K_2p_1s = jnp.einsum("i,j,k,l,ijkl->", c_2p, c_1s, c_2p, c_1s, G_ps_exch)
    J_2p_2s = jnp.einsum("i,j,k,l,ijkl->", c_2p, c_2p, c_2s, c_2s, G_ps_coul)
    K_2p_2s = jnp.einsum("i,j,k,l,ijkl->", c_2p, c_2s, c_2p, c_2s, G_ps_exch)
    J_2p_3p = jnp.einsum("i,j,k,l,ijkl->", c_2p, c_2p, c_3p, c_3p, G_p)
    K_2p_3p = jnp.einsum("i,j,k,l,ijkl->", c_2p, c_3p, c_2p, c_3p, G_p)
    E_ee = (
        J_1s_1s
        + J_2s_2s
        + 1.0e1 * J_2p_2p
        + -4.0 * K_2p_2p
        + 4.0 * J_1s_2s
        + -2.0 * K_1s_2s
        + 2.0 * J_1s_3p
        + -1.0 * K_1s_3p
        + 2.0 * J_2s_3p
        + -1.0 * K_2s_3p
        + 1.0e1 * J_2p_1s
        + -5.0 * K_2p_1s
        + 1.0e1 * J_2p_2s
        + -5.0 * K_2p_2s
        + 5.0 * J_2p_3p
        + -2.5 * K_2p_3p
    )
    E_elec = 2.0 * E_1s + 2.0 * E_2s + 5.0 * E_2p + E_3p + E_ee
    H_SO = jnp.array(
        [
            [E_elec - 0.5 * zeta_2p, 0.5 * zeta_3p],
            [0.5 * zeta_3p, E_elec + 0.5 * zeta_2p],
        ]
    )
    eigvals = jnp.linalg.eigh(H_SO)
    norm_penalty = 1.0 * (
        (jnp.dot(X_s[:, 0], X_s[:, 0]) - 1.0) ** 2
        + (jnp.dot(X_s[:, 1], X_s[:, 1]) - 1.0) ** 2
        + (jnp.dot(X_p[:, 0], X_p[:, 0]) - 1.0) ** 2
        + (jnp.dot(X_p[:, 1], X_p[:, 1]) - 1.0) ** 2
    )
    return eigvals[0][0] + norm_penalty


def get_initial_guesses(nuclear_mass):
    log_alpha_s = jnp.linspace(jnp.log(1.0e-2), jnp.log(5.0e2), 8)
    log_alpha_p = jnp.linspace(jnp.log(5.0e-2), jnp.log(1.0e2), 6)
    alpha_s = jnp.exp(log_alpha_s)
    alpha_p = jnp.exp(log_alpha_p)
    M_au = nuclear_mass * 1822.888
    mu = M_au / (1.0 + M_au)
    _, _, S_s_LL, S_s_SS, V_s_LL, V_s_SS = compute_matrices(
        alpha_s, 0, -1, 1.0e1, mu=mu
    )
    S_s = S_s_LL + S_s_SS
    H_s = V_s_LL + V_s_SS + (4.0 - 2.0 * mu) * C_LIGHT**2 * S_s_SS
    S_s_val, S_s_vec = jnp.linalg.eigh(S_s)
    S_s_inv_sqrt = jnp.dot(
        S_s_vec, jnp.dot(jnp.diag(1.0 / jnp.sqrt(S_s_val)), jnp.transpose(S_s_vec))
    )
    H_s_std = jnp.dot(S_s_inv_sqrt, jnp.dot(H_s, S_s_inv_sqrt))
    _, eigvecs_s_std = jnp.linalg.eigh(H_s_std)
    c_eig_s = jnp.dot(S_s_inv_sqrt, eigvecs_s_std)
    x_1s_init = c_eig_s[:, 0]
    x_2s_init = c_eig_s[:, 1]
    x_5s_init = c_eig_s[:, 4]
    _, _, S_p_LL, S_p_SS_1, V_p_LL_1, V_p_SS_1 = compute_matrices(
        alpha_p, 1, 1, 1.0e1, mu=mu
    )
    _, _, _, S_p_SS_2, V_p_LL_2, V_p_SS_2 = compute_matrices(
        alpha_p, 1, -2, 1.0e1, mu=mu
    )
    S_p_locked_avg = S_p_LL + 1.0 / 3.0 * S_p_SS_1 + 2.0 / 3.0 * S_p_SS_2
    H_p_locked_1 = V_p_LL_1 + V_p_SS_1 + (4.0 - 2.0 * mu) * C_LIGHT**2 * S_p_SS_1
    H_p_locked_2 = V_p_LL_2 + V_p_SS_2 + (4.0 - 2.0 * mu) * C_LIGHT**2 * S_p_SS_2
    H_p = 1.0 / 3.0 * H_p_locked_1 + 2.0 / 3.0 * H_p_locked_2
    S_p_val, S_p_vec = jnp.linalg.eigh(S_p_locked_avg)
    S_p_inv_sqrt = jnp.dot(
        S_p_vec, jnp.dot(jnp.diag(1.0 / jnp.sqrt(S_p_val)), jnp.transpose(S_p_vec))
    )
    H_p_std = jnp.dot(S_p_inv_sqrt, jnp.dot(H_p, S_p_inv_sqrt))
    _, eigvecs_p_std = jnp.linalg.eigh(H_p_std)
    c_eig_p = jnp.dot(S_p_inv_sqrt, eigvecs_p_std)
    x_2p_init = c_eig_p[:, 0]
    x_3p_init = c_eig_p[:, 1]
    return (
        x_1s_init,
        x_2s_init,
        x_5s_init,
        x_2p_init,
        x_3p_init,
    )


def get_physical_coefficients(params, nuclear_mass, is_initial):
    log_alpha_s = jnp.linspace(jnp.log(1.0e-2), jnp.log(5.0e2), 8)
    log_alpha_p = jnp.linspace(jnp.log(5.0e-2), jnp.log(1.0e2), 6)
    alpha_s = jnp.exp(log_alpha_s)
    alpha_p = jnp.exp(log_alpha_p)
    M_au = nuclear_mass * 1822.888
    mu = M_au / (1.0 + M_au)
    _, _, S_s_LL, S_s_SS, _, _ = compute_matrices(alpha_s, 0, -1, 1.0e1, mu=mu)
    S_s = S_s_LL + S_s_SS
    X_s = params["X_s"]
    M_s = jnp.dot(jnp.transpose(X_s), jnp.dot(S_s, X_s))
    vals_s, vecs_s = jnp.linalg.eigh(M_s)
    M_s_inv_sqrt = jnp.dot(
        vecs_s, jnp.dot(jnp.diag(1.0 / jnp.sqrt(vals_s)), jnp.transpose(vecs_s))
    )
    C_s = jnp.dot(X_s, M_s_inv_sqrt)
    c_1s = C_s[:, 0]
    c_2s = C_s[:, 1]
    _, _, S_LL, S_SS_1, _, _ = compute_matrices(alpha_p, 1, 1, 1.0e1, mu=mu)
    _, _, _, S_SS_2, _, _ = compute_matrices(alpha_p, 1, -2, 1.0e1, mu=mu)
    S_locked_avg = S_LL + 1.0 / 3.0 * S_SS_1 + 2.0 / 3.0 * S_SS_2
    if is_initial:
        x_2p = params["x_2p"]
        c_2p = x_2p / jnp.sqrt(jnp.dot(x_2p, jnp.dot(S_locked_avg, x_2p)))
        c_5s = C_s[:, 2]
        return (
            c_1s,
            c_2s,
            c_5s,
            c_2p,
        )
    else:
        X_p = params["X_p"]
        M_p = jnp.dot(jnp.transpose(X_p), jnp.dot(S_locked_avg, X_p))
        vals_p, vecs_p = jnp.linalg.eigh(M_p)
        M_p_inv_sqrt = jnp.dot(
            vecs_p, jnp.dot(jnp.diag(1.0 / jnp.sqrt(vals_p)), jnp.transpose(vecs_p))
        )
        C_p = jnp.dot(X_p, M_p_inv_sqrt)
        c_2p = C_p[:, 0]
        c_3p = C_p[:, 1]
        return (
            c_1s,
            c_2s,
            c_2p,
            c_3p,
        )


def nominal_frequency_wrapper(nuclear_mass):
    x_1s_init, x_2s_init, x_5s_init, x_2p_init, x_3p_init = get_initial_guesses(
        nuclear_mass
    )
    X_s_init_initial = jnp.stack([x_1s_init, x_2s_init, x_5s_init], axis=1)
    init_params_initial = dict(X_s=X_s_init_initial, x_2p=x_2p_init)
    X_s_init_final = jnp.stack([x_1s_init, x_2s_init], axis=1)
    X_p_init_final = jnp.stack([x_2p_init, x_3p_init], axis=1)
    init_params_final = dict(X_s=X_s_init_final, X_p=X_p_init_final)
    solver_initial = jaxopt.LBFGS(
        fun=initial_state_energy, maxiter=800, tol=1.0e-12, implicit_diff=True
    )
    res_initial = solver_initial.run(init_params_initial, nuclear_mass)
    E_initial = initial_state_energy(res_initial.params, nuclear_mass)
    solver_final = jaxopt.LBFGS(
        fun=final_state_energy, maxiter=800, tol=1.0e-12, implicit_diff=True
    )
    res_final = solver_final.run(init_params_final, nuclear_mass)
    E_final = final_state_energy(res_final.params, nuclear_mass)
    delta_E = E_initial - E_final
    HARTREE_TO_THZ = 6.579684e6
    nu_0 = delta_E * HARTREE_TO_THZ
    return nu_0
