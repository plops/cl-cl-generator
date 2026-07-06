# Walkthrough - Configurable and Optimized Gentoo Dockerfile Generator

We have successfully implemented the configurable and optimized Gentoo Dockerfile generator in [gen_gentoo.lisp](file:///workspace/src/cl-cl-generator/example/05_dockerfile_meta/source01/examples/01_gentoo/gen_gentoo.lisp).

## Changes Made

### 1. Fully Configurable parameters in [gen_gentoo.lisp](file:///workspace/src/cl-cl-generator/example/05_dockerfile_meta/source01/examples/01_gentoo/gen_gentoo.lisp)
The top of the Lisp file now defines variables to easily customize the build without altering the code structure:
- `*target-machine*` (`:both`, `:workstation`, `:thinkpad`): Configured to `:thinkpad` by default.
- `*split-world-build*`: Configured to `T` by default (compiles `@world` in 10 separate cached layers).
- `*portage-date*` & `*stage3-date*`: Set to `:auto` to calculate current dates dynamically at compile time.
- `*minimal-image*`: Configured to `T` by default.
- `*enable-flaggie-cleanup*`: Configured to `NIL` by default.
- Feature & Package category flags (all default to `nil` for the minimal profile).
- `*audio-system*`: Configured to `:pipewire` by default.

### 2. Inline Portage & OpenRC Heredocs
Small config files are written dynamically into the Dockerfile as inline heredocs (`COPY <<EOF ...`) to keep the codebase dry and avoid directory bloat:
- `/etc/portage/make.conf` (dynamically selects correct `VIDEO_CARDS`, `LLVM_TARGETS`, and audio flags).
- `/etc/portage/package.use` (enables Vulkan/PipeWire/ALSA options dynamically).
- `/etc/portage/package.accept_keywords`
- `/etc/portage/package.env` and `/etc/portage/env/*`
- OpenRC service configuration files for sessions, D-Bus, PipeWire, and reverse SSH tunnels.

### 3. Hybrid Portage Caching & Local Exporting
To support zero-download builds and cache compiled packages, we implement a hybrid pipeline:
- **During Compile:** Each `emerge` call bind-mounts `./distfiles` and `./binpkgs` from the host as **read-only**, alongside a **read-write** BuildKit cache mount. A helper script combines both sets of files, runs emerge, and copies new files to the cache.
- **Exporting:** An intermediate stage copies all files from the cache mounts to `/distfiles-export` and `/binpkgs-export`.
- **Exporter Output:** The final `FROM scratch` stage copies these export directories alongside the squashfs files, kernel, and package reports.
- Running `docker build -o ./output .` dumps these files to the host.

### 4. Build and Test Scripts
- `build.sh`: Runs the SBCL generator, initializes empty host cache folders, starts the BuildKit export build, redirects logs to `output/build.log`, and syncs (`rsync`) newly compiled packages back to `./distfiles/` and `./binpkgs/`.
- `enter_container.sh`: Enters an interactive bash shell in the `base` stage.

## Validation Results
We ran SBCL to compile the new `gen_gentoo.lisp` and successfully generated the output [Dockerfile](file:///workspace/src/cl-cl-generator/example/05_dockerfile_meta/source01/examples/01_gentoo/Dockerfile). It contains all the correct heredocs and cache mounts.
