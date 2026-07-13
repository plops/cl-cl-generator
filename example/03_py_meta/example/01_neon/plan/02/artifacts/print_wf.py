import sys
sys.path.append("/workspace/src/cl-cl-generator/example/03_py_meta/example/01_neon/source01")
import jax
import jax.numpy as jnp
from solver import get_initial_guesses, safe_I_k, compute_matrices

x_1s, x_2s, x_5s, x_2p, x_3p = get_initial_guesses(20.18)

log_alpha = jnp.linspace(jnp.log(0.01), jnp.log(500.0), 8)
alpha = jnp.exp(log_alpha)
C_coeffs = []
for i in range(8):
    val = (jax.vmap(lambda a: safe_I_k(2, 2.0 * a)))(jnp.array([alpha[i]]))
    C_coeffs.append(1.0 / jnp.sqrt(val[0]))

r = jnp.linspace(0.01, 5.0, 20)
P = jnp.zeros_like(r)
for i in range(8):
    g_i = C_coeffs[i] * r * jnp.exp(-alpha[i] * (r ** 2))
    P += x_1s[i] * g_i

for ri, pi in zip(r, P):
    print(f"r = {ri:.3f}, P = {pi:.6e}")
