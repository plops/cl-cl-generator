# Implementation Plan - TUI Cockpit for Linux (Bandwidth Optimized)

This plan outlines the design and files for building a lightweight, bandwidth-optimized Linux system cockpit TUI, designed to work smoothly over slow SSH connections (e.g. 6 kB/s) and monitor VPS metrics (CPU steal time, disk I/O, network bandwidth, memory/OOM pressure).

## User Review Required

> [!IMPORTANT]
> - **Permissions:** To read all process file descriptors `/proc/<pid>/fd/` and to configure `cgroups` + `tc` bandwidth limiting, the TUI program must run with **root privileges**.
> - **Traffic Control (tc):** Throttling relies on standard `tc` commands and `cgroups v2` support. We assume the system runs a modern Linux distribution (like Ubuntu or Gentoo) with `cgroup2` mounted and `iproute2` (`tc`) installed.

## Proposed Changes

We will create a new generator and generated source codebase under `example/04_tui_cockpit/`.

### TUI Cockpit Component

#### [NEW] [gen.lisp](file:///workspace/src/cl-cl-generator/example/04_tui_cockpit/gen.lisp)
The generator script written in Common Lisp using the `cl-cl-generator` package. It will:
- Define generator-time loops to construct repetitive parsers for `/proc/stat`, `/proc/pressure/io`, `/proc/vmstat`, and `/proc/<pid>/io`.
- Generate the core event loop, state structure, and TUI display rendering functions.
- Write the finalized source code to `cockpit.lisp`.

#### [NEW] [cockpit.asd](file:///workspace/src/cl-cl-generator/example/04_tui_cockpit/cockpit.asd)
The ASDF system definition file for the generated TUI cockpit.

#### [NEW] [package.lisp](file:///workspace/src/cl-cl-generator/example/04_tui_cockpit/package.lisp)
The package definition file for the generated application.

---

### Technical Design Details

1. **Parser Generation:**
   We will generate parsers using generation-time lists of fields to reduce code duplication:
   - For `/proc/stat`, we'll generate the extraction of CPU metrics (user, system, idle, steal).
   - For `/proc/pressure/io`, we'll extract `some` and `full` stall averages.
   - For `/proc/vmstat`, we'll extract `pswpin` and `pswpout`.

2. **Network Bandwidth via Procfs & FD Inspection:**
   - Scan `/proc/net/tcp` and `/proc/net/udp` (including IPv6 versions) to map socket inodes to IP/port addresses.
   - Iterate through `/proc/<pid>/fd/` to find symlinks containing `socket:[<inode>]`, mapping sockets to process PIDs.
   - Track read/write data sizes dynamically using procfs file sizes or byte diffs of process-level IO files (`/proc/<pid>/io`).

3. **Delta-Buffered Terminal Renderer:**
   - A grid of `[width, height]` characters and colors representing the current terminal screen.
   - A back-buffer representing the previously drawn screen.
   - A diff function that compares the two buffers and sends only `ESC [ <y>;<x>H` cursor movement instructions followed by the modified characters/colors. This avoids full screen clears and saves up to 95% of terminal refresh bandwidth.

4. **Throttling Implementation:**
   - Create a cgroup directory `/sys/fs/cgroup/tui-throttle/`.
   - Setup a `tc` queueing discipline (`qdisc`) and a filter matching the cgroup ID/class to throttle egress/ingress bandwidth.
   - Move target PIDs dynamically into `/sys/fs/cgroup/tui-throttle/cgroup.procs`.

## Verification Plan

### Automated Tests
- We will add standard validation test cases within `gen.lisp` or a companion `tests.lisp` file to verify parser correctness.
- We will run the generator and compile the output:
  ```bash
  sbcl --load example/04_tui_cockpit/gen.lisp --eval "(quit)"
  ```

### Manual Verification
1. Run the generated cockpit on the local container or virtual machine.
2. Check that the terminal bandwidth footprint remains low during fast refreshes (verify using network capture or monitoring).
3. Test adding a process to the throttled cgroup and verifying its network rate is limited.
