# Walkthrough: Rust Integration and Caching

This document summarizes the changes made to support optional Rust development toolchain installation and Docker-volume-based dependency caching in the `03_ai_env` environment.

## Changes Made

### 1. Generator Parameters & Toggles
In [gen_ai_env.lisp](file:///home/kiel/stage/cl-cl-generator/example/05_dockerfile_meta/source01/examples/03_ai_env/gen_ai_env.lisp), we added two new parameter variables:
- `*install-rust*` (default `t`): Toggle variable to control whether Rust is installed.
- `*rust-cache-volume*` (default `t`): Toggle variable to control whether `/root/.cargo` is added as a persistent container volume.

### 2. Dockerfile Generation AST
- In [gen_ai_env.lisp](file:///home/kiel/stage/cl-cl-generator/example/05_dockerfile_meta/source01/examples/03_ai_env/gen_ai_env.lisp), we updated the `runner-stage` function to automatically install `build-essential` and `gcc` if `*install-rust*` is active.
- Added a `rustup` runner block using Common Lisp list splicing:
  ```lisp
  ,@(when *install-rust*
      `((comment "Install rustup and stable Rust toolchain")
        (run (and "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable"
                  "chmod -R a+w /root/.rustup"))
        (env PATH "/root/.cargo/bin:$PATH")))
  ```
- Dynamically constructed the list of `volume` declarations to include `"/root/.cargo"` when `*rust-cache-volume*` is enabled.

### 3. Container Runner Script
In [setup02_run.sh](file:///home/kiel/stage/cl-cl-generator/example/05_dockerfile_meta/source01/examples/03_ai_env/setup02_run.sh), we added a named volume mount (`-v my-ai-env-cargo-cache:/root/.cargo`) so Cargo registry downloads persist across container stops/starts/recreations:
```bash
docker run -it \
  -e ANTIGRAVITY_PLAINTEXT_AUTH=1 \
  -v "$HOME/.gemini:/root/.gemini" \
  -v "/home/kiel/stage:/workspace/src" \
  -v my-ai-env-cargo-cache:/root/.cargo \
  my-ai-env:latest
```

### 4. Documentation
We updated [README.md](file:///home/kiel/stage/cl-cl-generator/example/05_dockerfile_meta/source01/examples/03_ai_env/README.md) to document these new options, the new volume mount, and how to run the container.

---

## Verification & Testing

### Toggle Verification:
- **Case 1: `*install-rust*` = `t`, `*rust-cache-volume*` = `t` (Default)**
  - Successfully generated the `Dockerfile` with the `rustup` installation block.
  - Correctly appended `"/root/.cargo"` to the `VOLUME` instruction.
  - Verified by inspecting [Dockerfile](file:///home/kiel/stage/cl-cl-generator/example/05_dockerfile_meta/source01/examples/03_ai_env/Dockerfile).

- **Case 2: `*install-rust*` = `nil` (Backward Compatibility)**
  - Disabled `*install-rust*` and generated the Dockerfile.
  - Verified using `git status` that the resulting file had exactly 0 changes relative to the upstream code repository, confirming perfect backward compatibility.

### Compilation Verification:
- **Workspace Build (`rs-summarizer` & `viz-tool`)**:
  - Ran `cargo build --workspace` inside the container using the persistent volume `my-ai-env-cargo-cache`.
  - The build completed successfully, downloading and compiling all dependencies (including `fast-umap` and `viz-tool`) and target artifacts in `37.57s` inside the clean container environment.

### Git Commits
All changes have been successfully committed to the repository with descriptive conventional messages:
1. `feat: add toggleable rust installation via rustup`
2. `feat: mount named cargo cache volume in run script`
3. `feat: generate dockerfile with rust installation and volume caching`
4. `docs: document rust development and caching setup in readme`
