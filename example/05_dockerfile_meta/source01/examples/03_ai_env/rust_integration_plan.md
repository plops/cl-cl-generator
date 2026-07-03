# Plan: Rust Support and Caching in `cl-dockerfile-generator` (Revised)

This document details the strategy for integrating Rust development environment support and package/build caching strategies into the S-expression Dockerfile generator (`gen_ai_env.lisp`).

## 1. Goal and Objectives

We want to expand the generated `Dockerfile` (via `gen_ai_env.lisp`) to support Rust development. The solution must:
1. **Be Optional/Toggleable**: Allow creating images with or without Rust (supporting arbitrary combinations: just gcc + agy, rust + kiro-cli, gcc + rust + python + agy, etc.).
2. **Implement Volume-based Caching (Development Mode)**: Keep all source code on the host (mapped via `/workspace/src`), and persist Cargo's cache (downloaded registry packages/git repositories) using persistent Docker volumes.
3. **Address the "Warmed Image" Question**: Evaluate whether a pre-baked image is necessary, and define a safe dependency pre-fetching mechanism that doesn't store source code inside the image.

---

## 2. Answers to Design Questions & Feedback

### 2.1. Do we even need a warmed image ("brauchen wir ueberhaupt ein warmed image?")?
**Short Answer:** No, not strictly.
**Why:**
- In Docker development environments, we map the host's source directory (e.g. `/home/kiel/stage` to `/workspace/src`). This means the project's target directories (like `/workspace/src/rs-summarizer/target`) naturally live on the host filesystem and persist.
- If we configure `/root/.cargo` as a persistent Docker volume, all downloaded crates, indexes, and git repositories are kept across container recreations.
- Therefore, after the very first compile, all subsequent builds are instantaneous because both the dependencies (in the `/root/.cargo` volume) and the build artifacts (in the host target folder) are fully cached.
- **Verdict**: We will make the volume-based cache the default standard. We will not copy or compile the project's actual source code into the image (preventing any risk of losing edits).

### 2.2. If we want pre-fetched dependencies (Offline / Clean Boot speed)
If the user still wants the image itself to contain dependencies (so the first build in a brand-new container doesn't need to download anything), we can support a "pre-fetch" mode:
1. We only copy the `Cargo.toml` and `Cargo.lock` files during the build.
2. We run `cargo fetch` or a dummy cargo build (with dummy `src/lib.rs` / `src/main.rs`) inside the image.
3. This populates `/root/.cargo/registry` and `/root/.cargo/git` *inside the image*.
4. **Important**: Since mounting a volume over `/root/.cargo` would hide these pre-fetched files, we can store them in the image at `/root/.cargo` *without* declaring it as a volume in the Dockerfile, or let Docker's named volumes handle the initialization.

### 2.3. Architecture-matching issues
We will ignore architecture-matching issues to keep the setup clean and simple. Cargo target artifacts will be written directly to `/workspace/src/<project>/target`.

---

## 3. Proposed Generator Parameter Configurations

We will introduce the following variables in `gen_ai_env.lisp`:

```lisp
;; Toggle Rust installation
(defparameter *install-rust* t)

;; Caching mode for Rust dependencies:
;; - :volume    -> Declares /root/.cargo as a volume (recommended, keeps code on host)
;; - :pre-fetch -> Pre-downloads dependencies from Cargo.toml into the image (no source code)
;; - nil        -> Normal rust installation without special caching
(defparameter *rust-caching-mode* :volume)

;; Context path of the Cargo project on the host for pre-fetching
(defparameter *rust-project-path* "rs-summarizer")
```

---

## 4. Implementation Steps & Git Commit Plan

We will perform the implementation incrementally, making frequent conventional git commits:

### Step 4.1: Extend `runner-stage` to support Rust installation
- Install `curl`, `build-essential`, and `ca-certificates` if they are not already installed.
- Download and run the `rustup` installer to set up stable Rust.
- Add `/root/.cargo/bin` to the `PATH` environment variable.
- **Commit**: `feat: add toggleable rust installation via rustup`

### Step 4.2: Configure Caching and Volumes
- If `*rust-caching-mode*` is `:volume`, append `/root/.cargo` to the `VOLUME` instruction.
- If `*rust-caching-mode*` is `:pre-fetch`, copy `Cargo.toml`, `Cargo.lock` (and workspace files) in a build stage and run `cargo fetch` to populate the image cache.
- **Commit**: `feat: add cargo registry volume and pre-fetch caching options`

### Step 4.3: Verify Output
- Test Dockerfile generation under different toggle combinations (e.g. Rust only, Rust + GCC, SBCL + Python, etc.).
- **Commit**: `test: verify generated dockerfiles match target configurations`

### Step 4.4: Document in README
- Update [README.md](file:///home/kiel/stage/cl-cl-generator/example/05_dockerfile_meta/source01/examples/03_ai_env/README.md) with instructions on how to use, configure, and run the container with Rust.
- **Commit**: `docs: document rust development and caching setup in readme`
