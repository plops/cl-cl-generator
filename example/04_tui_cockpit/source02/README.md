# Tuition Interactive TUI Cockpit

This is version 2 of the bandwidth-optimized Linux cockpit, built using the modern `cl-tuition` framework.

## Features

1. **Interactive Process Throttling**:
   * Navigate using **Up / Down** arrows.
   * Press **[t]** or **[Enter]** to throttle the selected process using Traffic Control and Cgroups.
2. **Process Network History & Accumulation**:
   * Tracks and displays process-level network download rate trends using Unicode sparklines.
   * Keeps a session running total of accumulated downloaded bytes per process.
3. **Responsive Polling Speeds**:
   * Press **[+]** to speed up refresh rates (decrement interval seconds).
   * Press **[-]** to slow down refresh rates (increment interval seconds).
4. **Help Overlay**:
   * Press **[h]** or **[F1]** to toggle helper key bindings inline.

## How to Run

Must be run as root:
```bash
sudo ./run-cockpit.sh
```

## Running Tests

To run the Rove test suite:
```bash
sbcl --eval '(push "$(pwd)/" asdf:*central-registry*)' \
     --eval '(asdf:test-system :cockpit-tui/tests)' \
     --quit
```
