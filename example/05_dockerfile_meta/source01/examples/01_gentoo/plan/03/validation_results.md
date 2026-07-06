# Validation Results: Gentoo Dockerfile Meta-Generator

We have successfully executed the validation plan for the configurable Gentoo Dockerfile Meta-Generator and its hybrid Portage caching pipeline. Below is the summary of results.

## 1. Exported Build Artifacts on Host

The build pipeline exported all build outputs to the `./output` directory successfully. 

| Artifact File | Size | Description |
| :--- | :--- | :--- |
| [gentoo.squashfs_e14](file:///home/kiel/stage/cl-cl-generator/example/05_dockerfile_meta/source01/examples/01_gentoo/output/gentoo.squashfs_e14) | 1.14 GiB | Compressed ThinkPad E14 squashfs rootfs (with NVIDIA/CUDA stripped) |
| [vmlinuz](file:///home/kiel/stage/cl-cl-generator/example/05_dockerfile_meta/source01/examples/01_gentoo/output/vmlinuz) | 25.2 MiB | Custom compiled Gentoo kernel |
| [initramfs_squash_sda1-x86_64.img](file:///home/kiel/stage/cl-cl-generator/example/05_dockerfile_meta/source01/examples/01_gentoo/output/initramfs_squash_sda1-x86_64.img) | 13.1 MiB | Custom Dracut initramfs |
| [packages.txt](file:///home/kiel/stage/cl-cl-generator/example/05_dockerfile_meta/source01/examples/01_gentoo/output/packages.txt) | 36.1 KiB | Installed packages list with sizes and compilation statistics |
| [packages.tsv](file:///home/kiel/stage/cl-cl-generator/example/05_dockerfile_meta/source01/examples/01_gentoo/output/packages.tsv) | 13.5 KiB | Tab-separated format of package installation list |
| [packages_obsolete.txt](file:///home/kiel/stage/cl-cl-generator/example/05_dockerfile_meta/source01/examples/01_gentoo/output/packages_obsolete.txt) | 2.5 KiB | Eix obsolete configuration report |
| [build.log](file:///home/kiel/stage/cl-cl-generator/example/05_dockerfile_meta/source01/examples/01_gentoo/output/build.log) | 8.3 MiB | Complete BuildKit redirect logs |

## 2. Caching & Performance Verification

We verified the dual Portage caching behavior (host bind mounts + BuildKit cache mounts):

- **First Build Run (Task-331)**:
  - Portage successfully configured the build tree, retrieved binary packages from the Gentoo binhost, and compiled the sources.
  - Caching directory `./distfiles/` on the host was successfully populated with **38 files** (totaling ~1.05 GB) including `linux-6.18.tar.xz`, `linux-firmware-20260519.tar.xz`, `mesa-26.0.8.tar.xz`, and other package sources.
  - Downloaded packages from binhost were also successfully cached.
  
- **Second Build Run (Validation Run)**:
  - Over 120 docker stages were immediately resolved as `CACHED`.
  - The build script completed in a few minutes, avoiding all compilations and downloads, and only took time to re-export the final 2.28 GB squashfs/kernel files to the host.

## 3. Interactive Debugging Environment Verification

We verified the interactive container environment:
- Executed `./enter_container.sh` with a pseudo-terminal.
- Verified that it built the `base` dev stage target `gentoo-z6-min-openrc-dev` successfully.
- Verified it correctly mounted host directories `distfiles` and `binpkgs` into `/var/cache/distfiles` and `/var/cache/binpkgs` respectively inside the container.
- Inside the container, verified file access and exited cleanly.

> [!NOTE]
> Since we use `getbinpkg` features in Portage without `buildpkg` FEATURES configured (which downloads binhost packages rather than creating them locally), the local `./binpkgs/` directory remains empty while `./distfiles/` has been fully populated. This is the expected behavior.
