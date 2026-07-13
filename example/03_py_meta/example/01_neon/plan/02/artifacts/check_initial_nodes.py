import sys
sys.path.append("/workspace/src/cl-cl-generator/example/03_py_meta/example/01_neon/source01")
import jax
import jax.numpy as jnp
from solver import get_initial_guesses, safe_I_k

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

x_1s, x_2s, x_5s, x_2p, x_3p = get_initial_guesses(20.18)
print("Initial guess node counts:")
print(f"1s nodes = {count_nodes(x_1s, True)}")
print(f"2s nodes = {count_nodes(x_2s, True)}")
print(f"5s nodes = {count_nodes(x_5s, True)}")
print(f"2p nodes = {count_nodes(x_2p, False)}")
print(f"3p nodes = {count_nodes(x_3p, False)}")
