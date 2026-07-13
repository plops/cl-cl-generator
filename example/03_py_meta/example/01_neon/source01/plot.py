import matplotlib
import matplotlib.pyplot as plt
import jax
import jax.numpy as jnp
import jaxopt
from solver import (
    initial_state_energy,
    final_state_energy,
    compute_matrices,
    safe_I_k,
    C_LIGHT,
    get_initial_guesses,
    get_physical_coefficients,
)


def run_optimization_history(fun, init_params, nuclear_mass, max_steps):
    solver = jaxopt.LBFGS(fun=fun, maxiter=1, tol=1.0e-6)
    state = solver.init_state(init_params, nuclear_mass)
    params = init_params
    history = []
    for i in range(max_steps):
        params, state = solver.update(params, state, nuclear_mass)
        history.append(state.value)
    return (
        params,
        history,
    )


def generate_radial_wavefunctions(c, l, kappa, is_s):
    if is_s:
        log_alpha = jnp.linspace(jnp.log(1.0e-2), jnp.log(5.0e2), 8)
    else:
        log_alpha = jnp.linspace(jnp.log(5.0e-2), jnp.log(1.0e2), 6)
    alpha = jnp.exp(log_alpha)
    Np = len(alpha)
    C_coeffs = []
    for i in range(Np):
        val = (jax.vmap(lambda a: safe_I_k(2 * l + 2, 2.0 * a)))(
            (jnp.array([alpha[i]]))
        )
        Ci = 1.0 / jnp.sqrt(val[0])
        C_coeffs.append(Ci)
    r = jnp.linspace(1.0e-2, 5.0, 500)
    P = jnp.zeros_like(r)
    Q = jnp.zeros_like(r)
    A = l + 1 + kappa
    for i in range(Np):
        g_i = C_coeffs[i] * jnp.power(r, l + 1) * jnp.exp(-1.0 * alpha[i] * r**2)
        B_i = -2.0 * alpha[i]
        f_i = (
            C_coeffs[i]
            / (2.0 * C_LIGHT)
            * (A * jnp.power(r, l) + B_i * jnp.power(r, l + 2))
            * jnp.exp(-1.0 * alpha[i] * r**2)
        )
        P = P + c[i] * g_i
        Q = Q + c[i] * f_i
    return (
        r,
        P,
        Q,
    )


def main():
    x_1s_init, x_2s_init, x_5s_init, x_2p_init, x_3p_init = get_initial_guesses(20.18)
    init_params_initial = dict(
        x_1s=x_1s_init, x_2s=x_2s_init, x_2p=x_2p_init, x_5s=x_5s_init
    )
    init_params_final = dict(
        x_1s=x_1s_init, x_2s=x_2s_init, x_2p=x_2p_init, x_3p=x_3p_init
    )
    params_initial, hist_initial = run_optimization_history(
        initial_state_energy, init_params_initial, 20.18, 50
    )
    params_final, hist_final = run_optimization_history(
        final_state_energy, init_params_final, 20.18, 50
    )
    c_1s_init, c_2s_init, c_5s_init, c_2p_init_state = get_physical_coefficients(
        params_initial, 20.18, True
    )
    c_1s_final, c_2s_final, c_2p_final_state, c_3p_final = get_physical_coefficients(
        params_final, 20.18, False
    )
    plt.figure(
        figsize=(
            12,
            5,
        )
    )
    plt.subplot(1, 2, 1)
    plt.plot(hist_initial, label="Initial State (5s)")
    plt.plot(hist_final, label="Final State (3p)")
    plt.xlabel("Iteration")
    plt.ylabel("Energy (Hartree)")
    plt.title("Optimization Convergence Curve")
    plt.legend()
    plt.grid(True)
    plt.subplot(1, 2, 2)
    r_1s, P_1s, Q_1s = generate_radial_wavefunctions(c_1s_init, 0, -1, True)
    r_2s, P_2s, Q_2s = generate_radial_wavefunctions(c_2s_init, 0, -1, True)
    r_5s, P_5s, Q_5s = generate_radial_wavefunctions(c_5s_init, 0, -1, True)
    r_2p, P_2p, Q_2p = generate_radial_wavefunctions(c_2p_final_state, 1, -2, False)
    r_3p, P_3p, Q_3p = generate_radial_wavefunctions(c_3p_final, 1, -2, False)
    plt.plot(r_1s, P_1s, label="1s Large P(r)", linestyle="-")
    plt.plot(r_2s, P_2s, label="2s Large P(r)", linestyle="-")
    plt.plot(r_5s, P_5s, label="5s Large P(r)", linestyle="-")
    plt.plot(r_2p, P_2p, label="2p Large P(r)", linestyle="-")
    plt.plot(r_3p, P_3p, label="3p Large P(r)", linestyle="-")
    plt.xlabel("Radius r (a.u.)")
    plt.ylabel("Wavefunction Amplitude")
    plt.title("Radial Wavefunctions")
    plt.legend()
    plt.grid(True)
    plt.tight_layout()
    plt.savefig(
        "/workspace/src/cl-cl-generator/example/03_py_meta/example/01_neon/source01/neon_transition_plots.png"
    )
    plt.close()


if __name__ == "__main__":
    main()
