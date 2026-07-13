import pytest
import jax
import jax.numpy as jnp
import jax.scipy.special as jsp
import jaxopt

jax.config.update("jax_enable_x64", True)
from solver import (
    compute_matrices,
    compute_G_generic,
    nominal_frequency_wrapper,
    C_LIGHT,
    safe_I_k,
    get_initial_guesses,
    get_physical_coefficients,
)


def test_overlap_normalization():
    alpha = jnp.array([1.0])
    H, S, _, _, _, _ = compute_matrices(alpha, 0, -1, 1.0)
    overlap = S[0, 0]
    assert jnp.allclose(overlap, 1.0, atol=1.0e-6)


def test_hydrogen_atom():
    def hydrogen_energy(params):
        log_alpha = params["log_alpha"]
        x = params["x"]
        alpha = jnp.exp(log_alpha)
        _, _, S_LL, S_SS, V_LL, V_SS = compute_matrices(alpha, 0, -1, 1.0)
        S_locked = S_LL + S_SS
        c = x / jnp.sqrt(jnp.dot(x, jnp.dot(S_locked, x)))
        H_locked = V_LL + V_SS + 2.0 * C_LIGHT**2 * S_SS
        return jnp.dot(c, jnp.dot(H_locked, c)) / jnp.dot(c, jnp.dot(S_locked, c))

    init_params = dict(
        log_alpha=jnp.linspace(jnp.log(0.1), jnp.log(1.0e1), 6), x=jnp.ones(6)
    )
    solver = jaxopt.LBFGS(fun=hydrogen_energy, maxiter=100, tol=1.0e-6)
    res = solver.run(init_params)
    E_opt = hydrogen_energy(res.params)
    assert abs(E_opt + 0.5) < 1.0e-3


def test_coulomb_symmetries_and_decay():
    alpha_a = 0.5
    alpha_b = 1.2
    alpha_c = 0.8
    alpha_d = 1.5

    def primitive_coulomb_integral_R(alpha_a, alpha_b, alpha_c, alpha_d, R):
        p = alpha_a + alpha_b
        q = alpha_c + alpha_d
        gamma = p * q / (p + q)
        val_R = (
            jnp.pi**3
            / jnp.power(p * q, 1.5)
            * (jax.scipy.special.erf(jnp.sqrt(gamma) * R) / jnp.maximum(R, 1.0e-15))
        )
        val_0 = 2.0 * jnp.power(jnp.pi, 2.5) / (p * q * jnp.sqrt(p + q))
        return jnp.where(R > 1.0e-10, val_R, val_0)

    R = 2.0
    val1 = primitive_coulomb_integral_R(alpha_a, alpha_b, alpha_c, alpha_d, R)
    val2 = primitive_coulomb_integral_R(alpha_b, alpha_a, alpha_c, alpha_d, R)
    val3 = primitive_coulomb_integral_R(alpha_a, alpha_b, alpha_d, alpha_c, R)
    val4 = primitive_coulomb_integral_R(alpha_c, alpha_d, alpha_a, alpha_b, R)
    assert jnp.allclose(val1, val2)
    assert jnp.allclose(val1, val3)
    assert jnp.allclose(val1, val4)
    R1 = 1.0e1
    R2 = 2.0e1
    val_R1 = primitive_coulomb_integral_R(alpha_a, alpha_b, alpha_c, alpha_d, R1)
    val_R2 = primitive_coulomb_integral_R(alpha_a, alpha_b, alpha_c, alpha_d, R2)
    assert jnp.allclose(R1 * val_R1, R2 * val_R2, rtol=1.0e-3)


def test_kinetic_balance_enforcer():
    exponents = [0.5, 1.0, 2.0]
    H, S, _, _, _, _ = compute_matrices(exponents, 0, -1, 0.0)
    S_val, S_vec = jnp.linalg.eigh(S)
    S_inv_sqrt = jnp.dot(
        S_vec, jnp.dot(jnp.diag(1.0 / jnp.sqrt(S_val)), jnp.transpose(S_vec))
    )
    H_std = jnp.dot(S_inv_sqrt, jnp.dot(H, S_inv_sqrt))
    eigvals_sorted, _ = jnp.linalg.eigh(H_std)
    c = C_LIGHT
    pos_e = eigvals_sorted[3:]
    neg_e = eigvals_sorted[:3]
    gap = pos_e[0] - neg_e[-1]
    assert gap > 1.9 * c**2


def test_isotope_shift_cross_check():
    grad_fn = jax.grad(nominal_frequency_wrapper)
    grad_val = grad_fn(2.1e1)
    fd_slope = (
        nominal_frequency_wrapper(2.2e1) - nominal_frequency_wrapper(2.0e1)
    ) / 2.0
    assert jnp.allclose(grad_val, fd_slope, rtol=5.0e-3, atol=5.0e-3)
