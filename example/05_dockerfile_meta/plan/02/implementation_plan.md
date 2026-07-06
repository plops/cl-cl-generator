# Implementation Plan - Configurable and Optimized Gentoo Dockerfile Generator

This plan describes modifications to [gen_gentoo.lisp](file:///workspace/src/cl-cl-generator/example/05_dockerfile_meta/source01/examples/01_gentoo/gen_gentoo.lisp) to support configurable target machines, package feature flags, dynamic dates with cache-locking capability, and chunked emerge execution to optimize Docker build layer caching.

## User Review Required

> [!IMPORTANT]
> **Key Configuration Parameters Introduced:**
> We will add the following Lisp variables at the top of [gen_gentoo.lisp](file:///workspace/src/cl-cl-generator/example/05_dockerfile_meta/source01/examples/01_gentoo/gen_gentoo.lisp):
> - `*target-machine*` (`:both`, `:workstation`, `:thinkpad`): Selects the target hardware. If `:thinkpad` is set, all NVIDIA-specific drivers, CUDA SDK, and squashfs image steps are excluded, significantly reducing build times and image sizes.
> - `*split-world-build*` (`T` or `NIL`): If `T`, splits the `@world` update into 10 separate cached Docker RUN layers to protect against transient compilation failures and utilize cache layers.
> - `*portage-date*` (`:auto` or string like `"20260624"`): Automatically calculates today's date or locks a specific date.
> - `*stage3-date*` (`:auto` or string like `"20260622"`): Automatically calculates the date of the most recent Monday or locks a specific date.
> - `*minimal-image*` (`T` or `NIL`): If `T`, builds a minimal squashfs with only Xorg, xterm, and basic tools.
> - Feature flags (`*enable-emacs-sbcl*`, `*enable-rust*`, `*enable-go*`, `*enable-uv-ruff*`, `*enable-nvidia*`, `*enable-nvidia-cuda*`, `*enable-wireshark*`, `*enable-lua*`, `*enable-firefox*`, `*enable-google-chrome*`, `*enable-llvm*`, `*enable-clion*`, and `*audio-system*`).

> [!TIP]
> **Docker Caching Support:**
> Dynamic date calculations can invalidate Docker's cache. By default, setting `*portage-date*` and `*stage3-date*` to explicit strings will ensure stable Dockerfile generation and stable build layers during active development.

## Proposed Changes

### Configuration Directory Copy
We need to copy the original configuration files (kernel config, init scripts, dwm custom configuration, etc.) from `cl-py-generator` to the `cl-cl-generator` example directory so they are accessible during the Docker build.

#### [NEW] Configuration files under `/workspace/src/cl-cl-generator/example/05_dockerfile_meta/source01/examples/01_gentoo/config/`
Copied from `/workspace/src/cl-py-generator/example/110_gentoo/openrc/config/`.

---

### Gentoo Dockerfile Generator

#### [MODIFY] [gen_gentoo.lisp](file:///workspace/src/cl-cl-generator/example/05_dockerfile_meta/source01/examples/01_gentoo/gen_gentoo.lisp)
- Define variables for the target machine, feature flags, date locking, and chunked builds.
- Implement helper functions for dynamic date calculation:
  - Portage date: Today's date (`YYYYMMDD`).
  - Stage3 date: The most recent Monday's date (`YYYYMMDD`).
- Implement dynamic configuration content generation for `world`, `make.conf`, `package.use`, and `package.accept_keywords` via heredocs, avoiding static configurations that mismatch flags.
- Conditionally output Dockerfile steps:
  - If `*split-world-build*` is `T`, generate the 10-layer split compilation.
  - If `*target-machine*` is `:thinkpad`, skip NVIDIA/CUDA dependencies and avoid building `/gentoo.squashfs_nv`.
  - Only clean up compiler toolchains (Rust, Go) if they are not explicitly enabled by their respective feature flags.

## Verification Plan

### Automated Tests
1. Run the SBCL load command to check that `gen_gentoo.lisp` compiles and generates a valid Dockerfile:
   ```bash
   sbcl --load /workspace/src/cl-cl-generator/example/05_dockerfile_meta/source01/examples/01_gentoo/gen_gentoo.lisp --eval "(quit)"
   ```
2. Verify the contents of the generated `Dockerfile` under different flag combinations:
   - Target `:thinkpad` vs `:workstation`.
   - `*split-world-build*` as `T` vs `NIL`.
   - `*minimal-image*` as `T` vs `NIL`.

### Manual Verification
- Confirm that the `config/` directory contains all files, including `config6.18.18`.
