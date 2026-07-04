# Capturing X11 UNIX Domain Socket Traffic with Wireshark

Standard packet capture libraries (like `libpcap`, which Wireshark/tcpdump use) operate at the network layer and cannot natively capture traffic from UNIX domain sockets (`AF_UNIX`). Since modern Linux display systems typically run X11/Xwayland with `-nolisten tcp` for security, local X11 client connections rely entirely on UNIX domain sockets (usually located in `/tmp/.X11-unix/X0` for display `:0`).

To analyze local X11 traffic in Wireshark, you can use one of the following workarounds:

---

## Method 1: TCP Proxying via `socat` (Recommended)

This method redirects UNIX socket traffic through a local TCP port. This is highly recommended because Wireshark has a built-in **X11 protocol dissector** that can easily decode the resulting TCP stream.

### 1. Rename the original socket
*Note: This requires root or socket owner privileges.*
```bash
sudo mv /tmp/.X11-unix/X0 /tmp/.X11-unix/X0.orig
```

### 2. Proxy the new socket path to a local TCP port (e.g., 6010)
```bash
socat UNIX-LISTEN:/tmp/.X11-unix/X0,fork,mode=777 TCP-CONNECT:localhost:6010 &
```

### 3. Bridge the TCP port back to the original socket
```bash
socat TCP-LISTEN:6010,reuseaddr,fork UNIX-CONNECT:/tmp/.X11-unix/X0.orig &
```

### 4. Capture and decode in Wireshark
1. Open Wireshark and start capturing on the Loopback interface (`lo`).
2. Filter for TCP port 6010: `tcp.port == 6010`.
3. Right-click any captured packet, select **Decode As...**, and set the current protocol for TCP port `6010` to **X11**.

---

## Method 2: Passive eBPF Sniffing via `sockdump`

If you cannot modify the socket files or disrupt ongoing X11 connections, you can use eBPF to capture socket traffic passively at the kernel level.

1. Install `bcc` (BPF Compiler Collection) and clone [sockdump](https://github.com/nhooyr/sockdump).
2. Start the capture on the target X11 socket, outputting directly to a `.pcap` file:
   ```bash
   sudo ./sockdump.py /tmp/.X11-unix/X0 --format pcap --output x11_capture.pcap
   ```
3. Open `x11_capture.pcap` directly in Wireshark.

---

## Method 3: Enable TCP Natively in X11

If you can configure your Display Manager (e.g., GDM, LightDM) to enable TCP:

1. Edit your Display Manager configuration (e.g., in `/etc/gdm3/custom.conf` under `[security]`, set `DisallowTCP=false`) and restart it.
2. Launch your client application using TCP instead of UNIX sockets:
   ```bash
   export DISPLAY=127.0.0.1:0.0
   your-x11-app
   ```
3. Capture on the loopback interface (`lo`) in Wireshark with the filter `tcp.port == 6000` (X11 TCP ports start at `6000` + display number).
