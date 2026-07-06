# Test Instructions: Gentoo Dockerfile Meta-Generator Binhost Caching Verification

We have updated the Gentoo Dockerfile meta-generator `gen_gentoo.lisp` to support caching of downloaded binhost packages (`.gpkg.tar` files) in addition to distfiles.

Please execute the following steps to verify this fix:

## Step 1: Verify Host Cache Directories
Check that the host directories now contain the cached packages:
1. Check `./distfiles/` on the host to ensure it still contains downloaded source files.
2. Check `./binpkgs/` on the host to verify that it is **no longer empty** and now contains subdirectories of downloaded binary packages (e.g., `gentoo/sys-devel/gcc/...`).

## Step 2: Verify Speed and Caching (Second Build)
Run the build script again:
`./build.sh`
- Verify that the build runs extremely fast, utilizing the cached layers and the bind-mounted host `./binpkgs/` directory.
- Verify in `output/build.log` that `emerge` does not perform network downloads for binary packages, and they are copied/extracted from local caches.

## Step 3: Verify Interactive Debugging Environment
1. Run `./enter_container.sh` to boot the temporary development container.
2. Inside the container, check the directories `/var/cache/binpkgs` and `/var/cache/binhost`. Verify that they are populated with the cached binary packages from the host.
3. Exit the container.

## Step 4: Verify SquashFS Size and Exclusions
Verify that the `var/cache/binhost` directory was successfully excluded from the generated SquashFS file to keep its size minimal:
- Check that `output/gentoo.squashfs_e14` is approximately the same size as before (~1.14 GiB) and does not contain the binary packages under `var/cache/binhost`.

Report the verification results to the user.
