import sys
sys.path.append("/workspace/src/cl-cl-generator/example/03_py_meta/example/01_neon/source01")
import jax
import jax.numpy as jnp
import jaxopt
from solver import (
    initial_state_energy,
    final_state_energy,
    nominal_frequency_wrapper,
    get_initial_guesses,
    get_physical_coefficients
)

print("Starting gradient debug...")
m = 21.0
nu = nominal_frequency_wrapper(m)
print(f"Frequency at M={m}: {nu} THz")

grad_fn = jax.grad(nominal_frequency_wrapper)
try:
    g = grad_fn(m)
    print(f"jax.grad: {g}")
except Exception as e:
    print(f"Error in jax.grad: {e}")

nu_plus = nominal_frequency_wrapper(22.0)
nu_minus = nominal_frequency_wrapper(20.0)
fd = (nu_plus - nu_minus) / 2.0
print(f"nu(20.0): {nu_minus} THz")
print(f"nu(22.0): {nu_plus} THz")
print(f"Finite Difference slope: {fd}")
