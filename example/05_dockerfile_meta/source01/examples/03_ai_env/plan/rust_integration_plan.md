# Plan: Rust Support and Caching in `cl-dockerfile-generator` (Revised)

This document details the strategy for integrating Rust development environment support and package/build caching strategies into the S-expression Dockerfile generator (`gen_ai_env.lisp`).

## 1. Goal and Objectives

We want to expand the generated `Dockerfile` (via `gen_ai_env.lisp`) to support Rust development. The solution must:
1. **Be Optional/Toggleable**: Allow creating images with or without Rust (supporting arbitrary combinations: just gcc + agy, rust + kiro-cli, gcc + rust + python + agy, etc.).
2. **Implement Volume-based Caching (Development Mode)**: Keep all source code on the host (mapped via `/workspace/src`), and persist Cargo's cache (downloaded registry packages/git repositories) using persistent Docker volumes.
3. **Simplify the Caching Strategy**: Eliminate the obsolete `:pre-fetch` (baked-in dependencies) option to prevent complexity and avoid the risk of losing source code progress. All cargo source downloads are preserved in a dedicated persistent Docker volume.

---

## 2. Answers to Design Questions & Feedback

### 2.1. Why did we have `:pre-fetch`? Is it obsolete?
Yes, it is obsolete.
- Since we map `/workspace/src` to the host workspace (`/home/kiel/stage`), all target and code changes are saved on the host and persist naturally.
- Adding a persistent Docker volume for `/root/.cargo` completely covers downloading and caching registry packages.
- As a result, the very first build downloads dependencies, and all subsequent builds are instantaneous without needing to bake anything into the image.
- **Action**: The `:pre-fetch` mode is entirely removed from the plan to keep the implementation simple, clean, and robust.

### 2.2. Adapting `setup*.sh` Scripts
- **`setup01_build.sh`**: No changes required (simply builds the generated `Dockerfile`).
- **`setup02_run.sh`**: Needs to mount a named volume for `/root/.cargo` so the downloaded Rust registry packages and git checkouts persist across container recreations.
  We will add:
  ```bash
  -v my-ai-env-cargo-cache:/root/.cargo
  ```
- **`setup03_save.sh`**: No changes required.

---

## 3. Important Context & File References

For the AI executing this plan, here is a list of the key files and the information they contain:

### Core Generator Files
1. **[SKILL.md](file:///home/kiel/stage/cl-cl-generator/.agents/skills/cl-cl-generator/SKILL.md)**: Explains the `cl-cl-generator` S-expression engine. Explains how to construct Common Lisp code dynamically, write helper functions, and use generation-time loops (`,@(loop ...)`) or backquoted templating (`,@(when ...)`).
2. **[README.md](file:///home/kiel/stage/cl-cl-generator/README.md)**: Details the design philosophy of the pretty-printer system, custom pprint dispatches, and the automatic hash-checking mechanism (`write-source`) which prevents changing the file's modification time (mtime) if output is identical.
3. **[gen_ai_env.lisp](file:///home/kiel/stage/cl-cl-generator/example/05_dockerfile_meta/source01/examples/03_ai_env/gen_ai_env.lisp)**: The Lisp generator script that defines parameters (e.g. `*install-gcc*`, `*install-sbcl*`), and constructs the `builder-stage` and `runner-stage` using S-expressions.
4. **[dock.lisp](file:///home/kiel/stage/cl-cl-generator/example/05_dockerfile_meta/source01/dock.lisp)**: The Dockerfile DSL compiler. It defines `emit-df` (how Lisp symbols/lists correspond to Dockerfile keywords like `RUN`, `ENV`, `VOLUME`, etc.) and `write-df`.

### Scripts & Target Project
5. **[setup02_run.sh](file:///home/kiel/stage/cl-cl-generator/example/05_dockerfile_meta/source01/examples/03_ai_env/setup02_run.sh)**: The shell script that executes the container and handles host volume mounting.
6. **[Cargo.toml](file:///home/kiel/stage/rs-summarizer/Cargo.toml)**: Reference Rust project. Demonstrates the workspace member configuration and dependencies, validating why volume-based caching is required.

---

## 4. Proposed Generator Parameter Configurations

We will introduce the following variables in `gen_ai_env.lisp`:

```lisp
;; Toggle Rust installation
(defparameter *install-rust* t)

;; Toggle volume-based cargo caching (adds /root/.cargo to volume list)
(defparameter *rust-cache-volume* t)
```

---

## 5. Implementation Steps & Git Commit Plan

We will perform the implementation incrementally, making frequent conventional git commits:

### Step 5.1: Extend `runner-stage` to support Rust installation
- Download and run the `rustup` installer to set up stable Rust when `*install-rust*` is `t`.
- Add `/root/.cargo/bin` to the `PATH` environment variable.
- **Commit**: `feat: add toggleable rust installation via rustup`

### Step 5.2: Configure Caching and Volumes
- If `*rust-cache-volume*` is `t`, append `/root/.cargo` to the list of `VOLUME` mounts in `runner-stage`.
- **Commit**: `feat: add cargo registry volume caching configuration`

### Step 5.3: Update Runner Script
- Add `-v my-ai-env-cargo-cache:/root/.cargo` to `setup02_run.sh` to persist the Cargo folder.
- **Commit**: `feat: mount named cargo cache volume in run script`

### Step 5.4: Verify Output
- Test Dockerfile generation under different toggle combinations (e.g. Rust only, Rust + GCC, SBCL + Python, etc.).
- **Commit**: `test: verify generated dockerfiles match target configurations`

### Step 5.5: Document in README
- Update [README.md](file:///home/kiel/stage/cl-cl-generator/example/05_dockerfile_meta/source01/examples/03_ai_env/README.md) with instructions on how to use, configure, and run the container with Rust.
- **Commit**: `docs: document rust development and caching setup in readme`
