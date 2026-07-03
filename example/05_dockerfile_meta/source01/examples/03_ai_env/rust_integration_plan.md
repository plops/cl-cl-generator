# Plan: Rust Support and Caching in `cl-dockerfile-generator`

This document details the strategy for integrating Rust development environment support and package/build caching strategies into the S-expression Dockerfile generator (`gen_ai_env.lisp`).

## 1. Goal and Objectives

We want to expand the generated `Dockerfile` (via `gen_ai_env.lisp`) to support Rust development. The solution must:
1. **Be Optional/Toggleable**: Allow creating images with or without Rust (supporting arbitrary combinations: just gcc + agy, rust + kiro-cli, gcc + rust + python + agy, etc.).
2. **Support Dynamic Cache/Volume Mounting (Development Mode)**: For initial/active development, cache downloaded Cargo registry/git crates and compiled artifacts outside the container so they are not lost when the container is rebuilt.
3. **Support Pre-baked Dependencies (Warmed Mode)**: When the dependencies in `Cargo.toml` are stable, provide the option to build a Docker image that already contains the pre-compiled debug/release dependencies and the project source code.
4. **Use `rs-summarizer` as the reference project**: The configuration should work seamlessly with the `~/stage/rs-summarizer` project workspace structure.

---

## 2. Architecture & Design Options

To address the two caching requirements, we propose two caching strategies:

### Option A: External Volume/Mount Caching (Active Development)
When writing code and introducing new crates, dependencies are unknown in advance.
- **Cargo Registry**: We map `/root/.cargo/registry` and `/root/.cargo/git` to external Docker volumes.
- **Build Artifacts (`target`)**: By default, compiling Cargo projects puts targets under `/workspace/src/<project>/target`. Since `/workspace/src` maps to the host's `/home/kiel/stage`, compilation artifacts would normally be written directly to the host filesystem.
  > [!TIP]
  > To avoid architecture-matching issues between the host OS and the Linux container, we can optionally define a distinct `CARGO_TARGET_DIR=/root/target` environment variable and expose `/root/target` as a persistent volume. This keeps compilation artifacts completely inside container volumes and prevents cluttering the host's source tree.

### Option B: Pre-Baked Caching (Image Warming)
Once dependencies are established in `Cargo.toml`, we compile them into the image using a multi-stage build.
- We will leverage the **Builder stage** to:
  1. Copy the Cargo manifests (`Cargo.toml`, `Cargo.lock`, plus any workspace directories and local patches).
  2. Create a dummy structure (e.g. `src/lib.rs` / `src/main.rs`) for each member crate.
  3. Run `cargo build` to fetch and compile all dependencies.
  4. Copy the actual source files and build the final binary.
- In the **Runner stage**, we copy the compiled binaries and the warmed cargo target/registry folders, allowing the container to boot up with all dependencies pre-compiled.

---

## 3. Proposed Generator Parameter Configurations

We will introduce the following variables in `gen_ai_env.lisp`:

```lisp
;; Toggle Rust installation
(defparameter *install-rust* t)

;; Caching mode for Rust dependencies:
;; - :external-volume -> Declares /root/.cargo and /root/target as volumes
;; - :baked-in        -> Copies manifests, warms dependencies, and builds in image
;; - nil             -> Normal rust installation without special caching structure
(defparameter *rust-caching-mode* :external-volume)

;; Configuration for the reference project (when :baked-in is active)
(defparameter *rust-project-name* "rs-summarizer")
(defparameter *rust-build-profile* :debug) ; :debug or :release
```

---

## 4. Step-by-Step Implementation Strategy

### Step 4.1: Extend `runner-stage` for Rust Installation
When `*install-rust*` is `t`, we will:
1. Install base utilities needed by Rust (like `curl`, `build-essential`, `ca-certificates`).
2. Download and run the `rustup` installer to set up stable Rust.
3. Configure `PATH` to include `/root/.cargo/bin`.

```lisp
;; Inside runner-stage:
,@(when *install-rust*
    `((comment "Install Rustup and the Rust toolchain")
      (run (and "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable"
                "chmod -R a+w /root/.rustup"))
      (env PATH "/root/.cargo/bin:$PATH")))
```

### Step 4.2: Configure Caching and Volumes
Depending on `*rust-caching-mode*`:

#### Mode `:external-volume` (Active Development)
We declare `/root/.cargo` and `/root/target` (or the host project `target` location) as persistent Docker volumes.
We configure `CARGO_TARGET_DIR=/root/target` so that build files do not conflict with host build files.

```lisp
;; Inside runner-stage (under volume/env setup):
,@(when (and *install-rust* (eq *rust-caching-mode* :external-volume))
    `((env CARGO_TARGET_DIR "/root/target")
      (volume ("/root/.cargo" "/root/target"))))
```

#### Mode `:baked-in` (Warmed Image)
1. **In the Builder Stage**:
   We copy the dependencies config of `rs-summarizer`. Note that `rs-summarizer` is a workspace containing:
   - `Cargo.toml`
   - `Cargo.lock`
   - `viz-tool/Cargo.toml`
   - `third_party/fast-umap/Cargo.toml` (and its source, since it's a local patch)

   We will:
   - Copy only the `Cargo.toml` files and local paths.
   - Run a script/command to stub the source files (`mkdir -p src && echo "fn main() {}" > src/main.rs`).
   - Run `cargo build` (with `--release` if profile is `:release`) to compile dependencies.
   - Copy the actual source files of `rs-summarizer`.
   - Run `cargo build` again to compile the actual project.
2. **In the Runner Stage**:
   We copy the pre-warmed targets and cargo folder from the builder stage:
   ```lisp
   (copy "/root/.cargo" "/root/.cargo" :from builder)
   (copy "/root/target" "/root/target" :from builder)
   ```

---

## 5. Verification & Workflow Plan

1. **Dry-Run Dockerfile Generation**: Generate the `Dockerfile` under different parameter variations:
   - Case 1: `*install-rust*` is `nil` (verifies backward compatibility).
   - Case 2: `*install-rust*` is `t`, `*rust-caching-mode*` is `:external-volume`.
   - Case 3: `*install-rust*` is `t`, `*rust-caching-mode*` is `:baked-in`.
2. **Code Lint & Check**: Inspect generated Dockerfiles to ensure correct syntax and formatting.
3. **Container Test Execution**: Build and launch the container using the modified runner options to verify Cargo commands resolve properly inside the container.
