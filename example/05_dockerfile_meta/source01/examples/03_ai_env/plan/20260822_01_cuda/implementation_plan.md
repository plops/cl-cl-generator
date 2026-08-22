# Implementation Plan: Optional NVIDIA CUDA Support for `03_ai_env`

This document details the architectural design, parameter configuration, layer optimizations, and runtime workflow for introducing optional NVIDIA CUDA support into the `cl-dockerfile-generator` environment (`03_ai_env`).

---

## 1. Motivation & Objectives

- **Target Workloads**: Support both CUDA development (compilation with `nvcc`, linking cuDNN, C++/Rust CUDA bindings) and runtime execution (neural network training/inference with PyTorch, GPU-accelerated data processing with CuPy, Polars, PyArrow, Triton).
- **Modularity & Backward Compatibility**: Provide clean Common Lisp parameter toggles in `gen_ai_env.lisp` so users can switch seamlessly between standard Ubuntu CPU images and NVIDIA CUDA development images without breaking defaults.
- **Fast Multi-Stage Builds**: Avoid bloated intermediate builder layers by using lightweight Ubuntu bases for CLI downloads while leveraging official NVIDIA CUDA images for Python and runner stages.
- **Host GPU Passthrough**: Ensure portable container execution via `setup02_run.sh` with `--gpus` support for the NVIDIA Container Toolkit.

---

## 2. Generator Parameters in `gen_ai_env.lisp`

### Parameter Specifications

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `*enable-cuda*` | Boolean | `t` (or `nil`) | Master switch for NVIDIA CUDA support. |
| `*cuda-flavor*` | Keyword | `:devel` | Base image variant (`:cudnn-devel`, `:devel`, `:cudnn-runtime`, `:runtime`, `:base`). |
| `*cuda-version*` | String | `"13.3.1"` | CUDA release tag (e.g., `"13.3.1"`, `"12.8.0"`). |
| `*cuda-ubuntu-version*` | String | `"ubuntu26.04"` | Ubuntu base release suffix matching NVIDIA repository tags. |
| `*base-image*` | String | Computed | Base image string derived via `compute-base-image`. |
| `*builder-base-image*` | String | `"ubuntu:26.04"` | Lightweight base image used for standalone CLI download stages. |

### Lisp Implementation

```lisp
;; Toggle NVIDIA / CUDA GPU Support
(defparameter *enable-cuda* t
  "When true, configure the image with NVIDIA CUDA and cuDNN support.")

(defparameter *cuda-flavor* :devel
  "CUDA image variant:
   - :cudnn-devel   : AI / Deep Learning development (NVCC compiler, CUDA headers, cuDNN headers & libs)
   - :devel         : General GPU development (NVCC compiler, CUDA headers, no cuDNN)
   - :cudnn-runtime : AI / Deep Learning production execution (CUDA runtime + cuDNN)
   - :runtime       : General GPU production execution (CUDA runtime)
   - :base          : Minimal deployment / driver linking")

(defparameter *cuda-version* "13.3.1"
  "NVIDIA CUDA version tag.")

(defparameter *cuda-ubuntu-version* "ubuntu26.04"
  "Ubuntu base release for CUDA images.")

(defun compute-base-image ()
  (if *enable-cuda*
      (format nil "nvidia/cuda:~a-~(~a~)-~a"
              *cuda-version*
              *cuda-flavor*
              *cuda-ubuntu-version*)
      "ubuntu:26.04"))

(defparameter *base-image* (compute-base-image))
(defparameter *builder-base-image* "ubuntu:26.04"
  "Minimal base image for CLI builder stages to save build time and memory.")
```

---

## 3. Builder Stages & Layer Optimization

To optimize build time, network traffic, and disk usage:
- **CLI Download Stages** (`builder-agy`, `builder-copilot`, `builder-kiro`, `builder-teamcity`):
  These stages only require `curl` and `unzip` to fetch binaries. Using `*builder-base-image*` (`ubuntu:26.04`, ~30 MB) avoids redundant pulls of the ~4.4 GB CUDA development image.
- **Python Virtualenv Stage** (`builder-python`):
  Uses `*base-image*` so that any native Python extensions compiled during `uv pip install` have access to CUDA headers and `nvcc`.
- **Final Runtime Stage** (`runner`):
  Uses `*base-image*` to provide all runtime and development libraries.

---

## 4. CUDA Environment Variables & Paths

When `*enable-cuda*` is active, the runner stage exports:

- `NVIDIA_VISIBLE_DEVICES="all"`: Enables NVIDIA Container Toolkit driver passthrough for all available GPUs.
- `NVIDIA_DRIVER_CAPABILITIES="compute,utility"`: Grants compute and management capabilities (e.g. `nvidia-smi`, CUDA driver calls).
- `CUDA_HOME="/usr/local/cuda"` & `CUDA_PATH="/usr/local/cuda"`: Standard paths recognized by CMake, PyTorch, and Rust toolchains (`cudarc`, `cust`).
- `CUDACXX="/usr/local/cuda/bin/nvcc"`: Directs build systems to the CUDA compiler.
- `PATH="/usr/local/cuda/bin:$PATH"`: Exposes `nvcc`, `ptxas`, `cuobjdump`, and CUDA binaries.
- `LD_LIBRARY_PATH="/usr/local/cuda/lib64:$LD_LIBRARY_PATH"`: Ensures CUDA shared libraries (`libcudart.so`, `libcublas.so`, etc.) are readily linkable.

---

## 5. Build-Time Smoke Tests

Under `*smoke-tests*`, an automated test compiles a minimal CUDA kernel with `nvcc`:

```lisp
(*enable-cuda* "CUDA nvcc compiler by compiling and verifying a test CUDA kernel"
               #r(set -eu
if command -v nvcc >/dev/null 2>&1; then
  nvcc --version
  tmpdir="$(mktemp -d /tmp/ai-env-cuda.XXXXXX)"
  cat > "$tmpdir/test.cu" <<'CU_EOF'
#include <stdio.h>

__global__ void test_kernel(void) {}

int main(void) {
  test_kernel<<<1, 1>>>();
  puts("cuda-build-ok");
  return 0;
}
CU_EOF
  nvcc "$tmpdir/test.cu" -o "$tmpdir/test"
  rm -rf "$tmpdir"
fi
))
```

---

## 6. Container Run Script Integration (`setup02_run.sh`)

In `setup02_run.sh`, the `--gpus` (and alias `--gpu`) flag is parsed to inject `--gpus "$gpus_spec"` into the `docker run` command:

```bash
enable_gpus=0
gpus_spec="all"

# In option parsing loop:
--gpus)
  enable_gpus=1
  if [ "$#" -gt 1 ] && [ "$(printf '%s' "$2" | cut -c1-2)" != "--" ]; then
    gpus_spec="$2"
    shift
  fi
  ;;
--gpu)
  enable_gpus=1
  ;;

# In execution assembly:
if [ "$enable_gpus" -eq 1 ]; then
  set -- "$@" --gpus "$gpus_spec"
fi
```

---

## 7. Verification & Validation Workflow

1. **Dockerfile Generation**:
   ```bash
   ./setup00_generate_dockerfile.sh
   ```
2. **Image Compilation**:
   ```bash
   ./setup01_build.sh
   ```
3. **Execution with GPU Access**:
   ```bash
   ./setup02_run.sh --gpus all
   ```
4. **Functional Testing inside Container**:
   - `nvidia-smi`: Verifies driver communication and GPU hardware detection.
   - `nvcc --version`: Verifies the CUDA compiler toolkit.
   - Compile and execute a sample CUDA program (`.cu`).
   - Run Python data processing / PyTorch checks.
5. **Backward Compatibility Check**:
   - Set `*enable-cuda*` to `nil` in `gen_ai_env.lisp`.
   - Regenerate `Dockerfile` and verify clean matching with default CPU Ubuntu image.
