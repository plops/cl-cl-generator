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


def generate_radial_wavefunctions(params, l, kappa, name):
    limit = 5.0e1
    if "s" in name:
        limit = 1.0e2
    log_alpha = jnp.linspace(jnp.log(0.1), jnp.log(limit), 4)
    alpha = jnp.exp(log_alpha)
    x = params["x_" + name]
    _, _, S_LL, S_SS, _, _ = compute_matrices(alpha, l, kappa, 1.0e1)
    S_locked = S_LL + S_SS
    c = x / jnp.sqrt(jnp.dot(x, jnp.dot(S_locked, x)))
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
    init_params_initial = dict(x_2p=jnp.ones(4), x_5s=jnp.ones(4))
    init_params_final = dict(x_2p=jnp.ones(4), x_3p=jnp.ones(4))
    params_initial, hist_initial = run_optimization_history(
        initial_state_energy, init_params_initial, 20.18, 50
    )
    params_final, hist_final = run_optimization_history(
        final_state_energy, init_params_final, 20.18, 50
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
    r_5s, P_5s, Q_5s = generate_radial_wavefunctions(params_initial, 0, -1, "5s")
    r_3p, P_3p, Q_3p = generate_radial_wavefunctions(params_final, 1, -2, "3p")
    plt.plot(r_5s, P_5s, label="5s Large P(r)", linestyle="-")
    plt.plot(r_5s, Q_5s, label="5s Small Q(r)", linestyle="--")
    plt.plot(r_3p, P_3p, label="3p Large P(r)", linestyle="-")
    plt.plot(r_3p, Q_3p, label="3p Small Q(r)", linestyle="--")
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
