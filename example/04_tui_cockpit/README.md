# Example 04: Bandwidth-Optimized Linux TUI Cockpit

This folder contains a generated, extremely lightweight Linux TUI Cockpit designed for very slow connections (e.g., 6 kB/s SSH links) and virtual private servers (VPS).

It is written in Common Lisp and generated using S-expression templates in [cl-cl-generator](file:///workspace/src/cl-cl-generator/.agents/skills/cl-cl-generator/SKILL.md) to reduce parser and state boilerplate.

---

## TUI Console Screenshot

Here is what the TUI Cockpit looks like in your terminal (using Unicode sparklines and delta-buffered redraws):

```text
  === Linux TUI Cockpit (Bandwidth-Optimiert) ===

  CPU Steal:  0.00% [ ]

  I/O Pressure Stall (PSI): SOME: 0.0%, FULL: 0.0%

  Swap Page In/Out: pswpin: 0, pswpout: 0

  Net Rate: RX:  0.06 kB/s [ ]  TX:  0.06 kB/s [ ]


  Top Bandwidth Processes:
    PID    NAME          NET-RX       NET-TX       DISK-R/W     OOM
    33     agy             0.0kB/s    0.0kB/s   0.2M/241.4M  669
```

---

## Features

1. **Bandwidth Savings (SSH-friendly):**
   * **Double Buffering:** Maintains a screen buffer in memory, compares it to the previous state, and only sends ANSI escape sequences (`ESC [ <y>;<x>H`) for character cells that actually changed.
   * **No Full Clears:** Prevents terminal clears that cause lag on 6 kB/s links.
2. **VPS Metrics:**
   * **CPU Steal Time:** Tracks vCPU latency caused by neighboring VMs on the same host, rendered as a real-time sparkline.
   * **I/O Pressure (PSI):** Instantly alerts you if the shared storage layer is throttling.
   * **OOM Score:** Displays which process is most vulnerable to being terminated if memory runs out.
3. **Bandwidth Rate Limiting:**
   * Contains hooks to place processes dynamically into `cgroups v2` and use Linux Traffic Control (`tc`) to throttle their speeds.

---

## How to Run

Since the cockpit reads `/proc/<pid>/fd/` of other processes and configures `cgroups`, you must run it as **root**.

Simply run the portable startup script (you can run it from any directory, or copy it and the Lisp files to another folder):

```bash
sudo ./run-cockpit.sh
```

Alternatively, you can load and run it manually in SBCL:

```bash
sbcl --eval '(push "/workspace/src/cl-cl-generator/example/04_tui_cockpit/" asdf:*central-registry*)' \
     --eval '(ql:quickload :cockpit)' \
     --eval '(cockpit:run-cockpit)'
```
