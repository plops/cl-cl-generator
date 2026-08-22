# Walkthrough: NVIDIA CUDA Integration in `03_ai_env`

This document summarizes the changes made to support optional NVIDIA CUDA development and execution in the `cl-dockerfile-generator` environment (`03_ai_env`), along with validation results.

---

## 1. Summary of Changes

### A. Generator Parameters & Base Image Selection
In [gen_ai_env.lisp](file:///home/martin/stage/cl-cl-generator/example/05_dockerfile_meta/source01/examples/03_ai_env/gen_ai_env.lisp):
- Added parameter `*enable-cuda*` (default `t` when enabled, `nil` for standard CPU image).
- Added `*cuda-flavor*` (`:devel`, `:cudnn-devel`, `:cudnn-runtime`, `:runtime`, `:base`).
- Added `*cuda-version*` (`"13.3.1"`) and `*cuda-ubuntu-version*` (`"ubuntu26.04"`).
- Added `compute-base-image` function to dynamically compute `*base-image*`.
- Added `*builder-base-image*` (`"ubuntu:26.04"`) for lightweight CLI download stages (`agy`, `copilot`, `kiro-cli`, `teamcity`), preventing duplicate pulls of multi-gigabyte CUDA images.

### B. CUDA Environment Variables & Toolchain
In the `runner-stage` of [gen_ai_env.lisp](file:///home/martin/stage/cl-cl-generator/example/05_dockerfile_meta/source01/examples/03_ai_env/gen_ai_env.lisp):
- Injected `NVIDIA_VISIBLE_DEVICES=all` and `NVIDIA_DRIVER_CAPABILITIES=compute,utility` for NVIDIA Container Toolkit integration.
- Configured `CUDA_HOME=/usr/local/cuda`, `CUDA_PATH=/usr/local/cuda`, `CUDACXX=/usr/local/cuda/bin/nvcc`, and updated `PATH` and `LD_LIBRARY_PATH`.

### C. Build-Time Smoke Tests
- Added a build-time test in `*smoke-tests*` that compiles a sample CUDA kernel (`.cu`) with `nvcc` to verify the compiler and headers during `docker build`.

### D. Runner Script (`setup02_run.sh`)
In [setup02_run.sh](file:///home/martin/stage/cl-cl-generator/example/05_dockerfile_meta/source01/examples/03_ai_env/setup02_run.sh):
- Added `--gpus [SPEC]` (default `all`) and `--gpu` command-line flags.
- Appended `--gpus "$gpus_spec"` to the `docker run` command when enabled.

### E. Emacs Batch Mode Compatibility
- Fixed a package sorting issue during Emacs batch mode (`setq package-selected-packages nil` and `setq custom-file null-device`) when installing MELPA packages (`slime`, `yaml-mode`, etc.).

---

## 2. Validation & Verification Results

### 1. Build Verification
The Docker image was regenerated with `./setup00_generate_dockerfile.sh` and built using `./setup01_build.sh`.
- All 56 build steps completed successfully.
- Build-time smoke tests for GCC, Rust, Python, SBCL, Emacs/SLIME, and the new CUDA `nvcc` compiler smoke test all passed.

### 2. GPU Passthrough Verification (`nvidia-smi`)
Running `nvidia-smi` inside the built container:
```bash
docker run --rm --gpus all my-ai-env:latest nvidia-smi
```
**Output:**
```
==========
== CUDA ==
==========

CUDA Version 13.3.1

Sat Aug 22 05:40:00 2026       
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 580.173.02             Driver Version: 580.173.02     CUDA Version: 13.3     |
+-----------------------------------------+------------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |
| Fan  Temp   Perf          Pwr:Usage/Cap |           Memory-Usage | GPU-Util  Compute M. |
|                                         |                        |               MIG M. |
|=========================================+========================+======================|
|   0  NVIDIA GeForce RTX 2060 ...    Off |   00000000:08:00.0  On |                  N/A |
| 29%   33C    P8             13W /  175W |     133MiB /   8192MiB |      3%      Default |
+-----------------------------------------+------------------------+----------------------+
```

### 3. CUDA Compilation & GPU Execution
Compiled and executed a multi-threaded CUDA kernel on the host GPU inside the container:
```bash
docker run --rm --gpus all my-ai-env:latest bash -c 'cat <<CU_EOF > /tmp/test.cu
#include <stdio.h>
__global__ void hello() {
    printf("Hello from GPU thread %d!\n", threadIdx.x);
}
int main() {
    hello<<<1, 4>>>();
    cudaDeviceSynchronize();
    printf("CUDA execution success!\n");
    return 0;
}
CU_EOF
nvcc /tmp/test.cu -o /tmp/test && /tmp/test'
```
**Output:**
```
Hello from GPU thread 0!
Hello from GPU thread 1!
Hello from GPU thread 2!
Hello from GPU thread 3!
CUDA execution success!
```

### 4. Data Processing Libraries Test
Verified Python data processing tools inside the virtual environment:
```bash
docker run --rm --gpus all my-ai-env:latest python3 -c 'import polars as pl, pyarrow as pa, numpy as np, pandas as pd; df = pl.DataFrame({"x": [1, 2, 3], "y": [4.0, 5.0, 6.0]}); print("Polars DataFrame:\n", df); print("PyArrow, NumPy, Pandas all imported successfully!")'
```
**Output:**
```
Polars DataFrame:
 shape: (3, 2)
┌─────┬─────┐
│ x   ┆ y   │
│ --- ┆ --- │
│ i64 ┆ f64 │
╞═════╪═════╡
│ 1   ┆ 4.0 │
│ 2   ┆ 5.0 │
│ 3   ┆ 6.0 │
└─────┴─────┘
PyArrow, NumPy, Pandas all imported successfully!
```

### 5. Backward Compatibility
When `*enable-cuda*` is set to `nil`, running `./setup00_generate_dockerfile.sh` produces the exact standard Ubuntu CPU `Dockerfile` with zero diff against standard CPU configurations.
