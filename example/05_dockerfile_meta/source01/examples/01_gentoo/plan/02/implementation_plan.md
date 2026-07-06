# Implementation Plan - Configurable and Optimized Gentoo Dockerfile Generator

This plan describes modifications to [gen_gentoo.lisp](file:///workspace/src/cl-cl-generator/example/05_dockerfile_meta/source01/examples/01_gentoo/gen_gentoo.lisp) to support configurable target machines, package feature flags, dynamic dates with cache-locking capability, and chunked emerge execution to optimize Docker build layer caching.

## User Review Required

> [!IMPORTANT]
> **Key Configuration Parameters & Logical Flags Introduced:**
> We will add the following Lisp variables at the top of [gen_gentoo.lisp](file:///workspace/src/cl-cl-generator/example/05_dockerfile_meta/source01/examples/01_gentoo/gen_gentoo.lisp):
> - `*target-machine*` (`:both`, `:workstation`, `:thinkpad`): Selects the target hardware. If `:thinkpad` is set, all NVIDIA-specific drivers, CUDA SDK, and squashfs image steps are excluded, significantly reducing build times and image sizes.
> - `*split-world-build*` (`T` or `NIL`): If `T`, splits the `@world` update into 10 separate cached Docker RUN layers to protect against transient compilation failures and utilize cache layers.
> - `*portage-date*` (`:auto` or string like `"20260624"`): Automatically calculates today's date or locks a specific date.
> - `*stage3-date*` (`:auto` or string like `"20260622"`): Automatically calculates the date of the most recent Monday or locks a specific date.
> - `*minimal-image*` (`T` or `NIL`): If `T`, builds a minimal squashfs with only Xorg, xterm, and basic tools.
> - `*enable-flaggie-cleanup*` (`T` or `NIL`, defaults to `NIL`): If `T`, installs `flaggie` and cleans up redundant package USE flags.
> - Feature flags (`*enable-emacs-sbcl*`, `*enable-rust*`, `*enable-go*`, `*enable-uv-ruff*`, `*enable-nvidia*`, `*enable-nvidia-cuda*`, `*enable-wireshark*`, `*enable-lua*`, `*enable-firefox*`, `*enable-google-chrome*`, `*enable-llvm*`, `*enable-clion*`, and `*audio-system*`).
> 
> **Logical Package Grouping Flags (Freely Selected):**
> We grouped all remaining packages from the original `world` file into logical flags for modular customization:
> - `*enable-docker*`: Container tooling (`app-containers/docker`, `docker-buildx`, `docker-cli`).
> - `*enable-dev-tools*`: High-performance compiler/debugging tools (`dev-build/ninja`, `dev-debug/strace`, `dev-debug/ltrace`, `sys-devel/mold`).
> - `*enable-media-playback*`: Local audio/video and image viewing (`media-video/mpv`, `media-gfx/feh`, `media-gfx/scrot`, `media-sound/pulsemixer`).
> - `*enable-network-admin*`: Advanced network troubleshooting (`hping`, `iftop`, `iptraf-ng`, `macchanger`, `netcat`, `nethogs`, `ngrep`, `ssmping`, `bind-tools`, `dnsmasq`).
> - `*enable-remote-access*`: Tunneling, VPNs, and RDP client (`autossh`, `mosh`, `freerdp`, `tailscale`, `bridge-utils`).
> - `*enable-cli-productivity*`: Enhanced shell tools (`jq`, `mc`, `tmate`, `tmux`, `zsh`, `bash-completion`, `tree`).
> - `*enable-sys-monitoring-hw*`: Hardware diagnostics & status monitoring (`cpuid`, `dmidecode`, `ethtool`, `lm-sensors`, `lshw`, `nvme-cli`, `pciutils`, `usbutils`, `btop`, `iotop`, `lsof`).
> - `*enable-power-management*`: ACPI daemon and TLP, highly recommended for the laptop (`sys-power/acpi`, `sys-power/tlp`).
> - `*enable-desktop-extras*`: Redshift color calibration and Zenhei Chinese fonts (`x11-misc/redshift`, `media-fonts/wqy-zenhei`).
> - `*enable-signal*`: Signal Messenger client (`net-im/signal-desktop-bin`).
> - `*enable-pdf-viewer*`: MuPDF viewer (`app-text/mupdf`).
> - `*enable-ios-sync*`: iOS filesystem mounting connectivity (`app-pda/ifuse`).
> - `*enable-alacritty*`: Alacritty terminal emulator (`x11-terms/alacritty`).

> [!TIP]
> **Docker Caching & Heredoc Configuration:**
> - To optimize caching, small configuration files (`make.conf`, `package.use`, `package.accept_keywords`, `package.env`, `env/low-mem`, `env/lto-gcc`, `resolv.conf`, user profile and all OpenRC service scripts) will be outputted as **inline heredocs** directly in the Dockerfile using the DSL's `:heredoc` support.
> - The large `config6.18.18` kernel configuration (207KB) will remain a file copy to prevent bloat of the generator source code.

> [!IMPORTANT]
> **Hybrid Distfiles & Binaries Cache Exporter (Zero Downloads & Host Isolation):**
> To satisfy both fast local folder access and persistent read-write caching, we implement a hybrid pipeline:
> 1. **Dual Mounts during Compile:** For every emerge command, we bind mount the host's `./distfiles` and `./binpkgs` directories (read-only) alongside a BuildKit cache mount (read-write):
>    - `--mount=type=bind,source=./distfiles,target=/var/cache/distfiles-host`
>    - `--mount=type=cache,target=/var/cache/distfiles-cache`
> 2. **Combine & Execute:** A helper script combines files from the host and cache mounts into Portage's active `DISTDIR` and `PKGDIR` folders, executes emerge, and saves any new downloads/binaries back to the read-write cache mount.
> 3. **Export Stage:** An intermediate exporter stage mounts the final read-write caches and copies them to `/distfiles-export` and `/binpkgs-export`.
> 4. **Scratch Exporter Output:** The final `FROM scratch` stage copies these export folders along with the squashfs files, kernel vmlinuz, initramfs, and reports. 
> 5. **Host Synchronisation:** Running `docker build -o ./output .` writes all files directly into the host's `./output/` directory. After a successful build, the host script `build.sh` automatically synchronizes (`rsync`) `./output/distfiles/` and `./output/binpkgs/` back into the host's `./distfiles/` and `./binpkgs/` folders, ready to be mounted read-only during the next build!
> 
> **Build/Execution Scripts:**
> - `build.sh`: Runs the SBCL generator, initializes empty `./distfiles` and `./binpkgs` host folders if not present, triggers the BuildKit export build, redirects logs to `output/build.log`, and syncs newly compiled packages/distfiles back to the host folders.
> - `enter_container.sh`: Runs a temporary interactive bash shell inside the builder stage for testing and debugging.

## Proposed Changes

### Configuration Directory Copy
We will copy only the large/binary configuration files (like `config6.18.18`, and optionally `dwm-6.8` / `slstatus_config.h` if they remain external) from `cl-py-generator` to `/workspace/src/cl-cl-generator/example/05_dockerfile_meta/source01/examples/01_gentoo/config/`. All other small configuration files will be generated as inline heredocs.

---

### Gentoo Dockerfile Generator

#### [MODIFY] [gen_gentoo.lisp](file:///workspace/src/cl-cl-generator/example/05_dockerfile_meta/source01/examples/01_gentoo/gen_gentoo.lisp)
- Define variables for target machine, feature flags, package category flags, date locking, and chunked builds.
- Implement helper functions for dynamic date calculation:
  - Portage date: Today's date (`YYYYMMDD`).
  - Stage3 date: The most recent Monday's date (`YYYYMMDD`).
- Implement helper macro `run-emerge` to automatically wrap package compilation steps in the dual cache + host bind mounts, combining them dynamically.
- Generate configuration content dynamically based on selected flags and write them inside the container via heredocs:
  - `/etc/portage/make.conf` (sets correct `VIDEO_CARDS`, `LLVM_TARGETS` and audio USE flags).
  - `/etc/portage/package.use` (sets Vulkan, PipeWire, ALSA, squashfs-tools options based on target/audio).
  - `/etc/portage/package.accept_keywords/package.accept_keywords` (sets keyword masking for tools/drivers).
  - `/etc/portage/package.env` and `/etc/portage/env/*` (low-mem and lto-gcc compiler flags).
  - OpenRC services for session, D-Bus, audio services, and reverse ssh tunnels.
- Conditionally output Dockerfile steps:
  - If `*split-world-build*` is `T`, generate the 10-layer split compilation.
  - If `*target-machine*` is `:thinkpad`, skip NVIDIA/CUDA dependencies and avoid building `/gentoo.squashfs_nv`.
  - Only clean up compiler toolchains (Rust, Go) if they are not explicitly enabled by their respective feature flags.
  - If `*enable-flaggie-cleanup*` is `T`, install flaggie and execute cleanup.
  - Run the `eix-test-obsolete` validation and dump the output to `/packages_obsolete.txt`.
- Add a final `FROM scratch` stage copying the build products (`/gentoo.squashfs*`, `/boot/vmlinuz`, `/boot/initramfs*`, `/packages.txt`, `/packages_obsolete.txt`, `/distfiles-export`, `/binpkgs-export`) to `/`.

#### [NEW] Scripts under `/workspace/src/cl-cl-generator/example/05_dockerfile_meta/source01/examples/01_gentoo/`
- `build.sh`
- `enter_container.sh`

## Verification Plan

### Automated Tests
1. Run the `build.sh` script to verify that the Dockerfile generates and builds/exports successfully.
2. Verify the contents of the generated `Dockerfile` under different flag combinations:
   - Target `:thinkpad` vs `:workstation`.
   - `*split-world-build*` as `T` vs `NIL`.
   - `*minimal-image*` as `T` vs `NIL`.
3. Check that the host `./output` directory contains the squashfs files, kernel, initramfs, packages list, and validation report.
4. Verify that newly downloaded files are correctly copied back to `./distfiles` and `./binpkgs` on the host after build.

### Manual Verification
- Confirm that the `config/` directory contains all files, including `config6.18.18`.
