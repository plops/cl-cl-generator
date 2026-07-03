# Task List: Rust Integration in `cl-dockerfile-generator`

- [x] Implement Rust toolchain installation in `gen_ai_env.lisp`
  - [x] Add `*install-rust*` and `*rust-cache-volume*` parameters
  - [x] Update `runner-stage` to run rustup installation when `*install-rust*` is `t`
  - [x] Append `/root/.cargo` to `volume` list when `*rust-cache-volume*` is `t`
- [x] Update `setup02_run.sh` script
  - [x] Add `-v my-ai-env-cargo-cache:/root/.cargo` volume mapping
- [x] Generate and Verify Dockerfile Output
  - [x] Run Lisp generation to build the Dockerfile
  - [x] Lint/inspect generated Dockerfile for correctness
  - [x] Verify various toggle combinations (no-rust, rust-only, etc.)
- [x] Update README documentation
  - [x] Document Rust setup, caching, and toggling in `README.md`
- [x] Final Walkthrough
  - [x] Create walkthrough artifact summarizing modifications and tests
