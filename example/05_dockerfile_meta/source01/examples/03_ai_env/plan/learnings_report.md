# Learnings Report: Rust Environment Integration & Caching Experiment

This report documents the key insights and learnings gained during the integration of Rust development capabilities and volume-based build caching into the Lisp-generated `03_ai_env` Docker environment.

---

## 1. Core Insights & Technical Learnings

### 1.1. Volume-Based Caching vs. In-Image Baking
During the design phase, we evaluated two caching strategies: baking dependencies into the image via multi-stage stubs (e.g. `cargo-chef`), and mounting a persistent Docker volume for Cargo's registry.
- **The Warmed Image Pitfall**: Baking dependencies/builds directly into the image filesystem requires copying manifest files and running dummy compilations. However, if the development workflow mounts a host directory over the workspace (e.g., `/workspace/src`), any pre-copied code inside the image is shadowed. Furthermore, compiling inside the container filesystem without host volume mapping risks losing code edits if the container is recreated.
- **The Named Volume Advantage**: Declaring `/root/.cargo` as a container volume and mounting it at run time via a named volume (`-v my-ai-env-cargo-cache:/root/.cargo`) is simpler, cleaner, and highly robust.
  - Downloaded registry crates and git repositories persist across container restarts.
  - Build speeds for subsequent compiles are identical to a pre-warmed image.
  - There is zero risk of losing code modifications since the source directory resides entirely on the host.

### 1.2. Toolchain Mismatch & Isolation Benefits
One major reason for developing inside containers is host toolchain mismatch or corruption.
- During the verification of the host compilation environment, `cargo check` failed on the host due to a missing library dependency (`rustc: error while loading shared libraries: libLLVM.so.21.1`).
- Building the project inside the container completed successfully in **37.57s** because the container isolates the toolchain, libraries, and Cargo environments completely from the host system.

### 1.3. Cargo Workspace Feature Resolution
- In multi-crate workspaces (like `rs-summarizer` which contains `viz-tool`), Cargo evaluates the feature flags and dependencies of all crates.
- An invalid feature declaration in `viz-tool/Cargo.toml` (`fast-umap/cuda` instead of the correct `gpu` feature) caused the cargo build command to fail entirely.
- By inspecting the patched crate at `third_party/fast-umap/Cargo.toml`, we confirmed the valid feature set (`gpu`, `cpu`) and resolved the issue by restoring `viz-tool/Cargo.toml` to its original clean state.

---

## 2. Generator Design & Extensibility

Using the `cl-dockerfile-generator` DSL made adding optional features extremely clean:
- **Toggleable Parameters**: Adding `*install-rust*` and `*rust-cache-volume*` allowed toggling the environment on/off.
- **List Splicing**: Splicing blocks in Lisp using `,@(when ...)` ensures that when features are disabled, the generator outputs a file with exactly zero diff compared to the previous code, guaranteeing perfect backward compatibility.
- **Linker Requirements**: If Rust is enabled but GCC/C-toolchain is disabled, the compiler lacks a linker. We resolved this by dynamically appending `build-essential` and `gcc` to the runner's apt packages when either option is `t`:
  ```lisp
  (when (or *install-gcc* *install-rust*)
    (setf apt-packages (append apt-packages '("build-essential" "gcc"))))
  ```

---

## 3. Best Practices for Future Dockerized Development Environments

1. **Isolate Registry Caches**: Always map compiler caches (`~/.cargo` for Rust, `~/.cache/pip` or `.cache/uv` for Python) to named Docker volumes rather than anonymous volumes or host directories.
2. **Keep Source Code on the Host**: Never copy active source code into development images. Always map host directories at runtime to prevent progress loss.
3. **Handle Implicit Dependencies**: Ensure that adding toolchains (like Rust) also pulls in low-level compilation tooling (like linkers/make/gcc) even if general GCC installation is disabled.
