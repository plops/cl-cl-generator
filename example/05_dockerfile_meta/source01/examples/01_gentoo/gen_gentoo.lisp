(eval-when (:compile-toplevel :execute :load-toplevel)
  (let ((current-dir (make-pathname :directory (pathname-directory *load-pathname*))))
    (push (merge-pathnames "../../" current-dir) asdf:*central-registry*))
  (ql:quickload :cl-dockerfile-generator))

(in-package :cl-dockerfile-generator)

;; --- Configuration parameters (edit as needed) ---
(defparameter *target-machine* :thinkpad
  "Target hardware. Choices: :both, :workstation, :thinkpad")

(defparameter *split-world-build* t
  "If T, split the @world compilation into 10 cached Docker layers.")

(defparameter *portage-date* :auto
  "Portage snapshot date (YYYYMMDD) or :auto for current date.")

(defparameter *stage3-date* :auto
  "Stage3 snapshot date (YYYYMMDD) or :auto for the most recent Monday.")

(defparameter *minimal-image* t
  "If T, build a minimal image (xorg, xterm, dwm only). Package categories default to NIL.")

(defparameter *enable-flaggie-cleanup* nil
  "If T, run flaggie cleanup to remove redundant USE flags.")

;; --- Optional feature flags ---
(defparameter *enable-emacs-sbcl* nil)
(defparameter *enable-rust* nil)
(defparameter *enable-go* nil)
(defparameter *enable-uv-ruff* nil)
(defparameter *enable-nvidia* nil)
(defparameter *enable-nvidia-cuda* nil)
(defparameter *enable-wireshark* nil)
(defparameter *enable-lua* nil)
(defparameter *enable-firefox* nil)
(defparameter *enable-google-chrome* nil)
(defparameter *enable-llvm* nil)
(defparameter *enable-clion* nil)
(defparameter *audio-system* :pipewire
  "Audio system. Choices: :pipewire, :alsa, :none")

;; --- Logical category flags ---
(defparameter *enable-docker* nil)
(defparameter *enable-dev-tools* nil)
(defparameter *enable-media-playback* nil)
(defparameter *enable-network-admin* nil)
(defparameter *enable-remote-access* nil)
(defparameter *enable-cli-productivity* nil)
(defparameter *enable-sys-monitoring-hw* nil)
(defparameter *enable-power-management* nil)
(defparameter *enable-desktop-extras* nil)
(defparameter *enable-signal* nil)
(defparameter *enable-pdf-viewer* nil)
(defparameter *enable-ios-sync* nil)
(defparameter *enable-alacritty* nil)

(defparameter *kver* "6.18.36")

;; --- Helper functions for Date Calculations ---
(defun get-formatted-date (universal-time)
  (multiple-value-bind (sec min hour day month year day-of-week dst-p tz)
      (decode-universal-time universal-time 0) ; use UTC
    (declare (ignore sec min hour day-of-week dst-p tz))
    (format nil "~4,'0d~2,'0d~2,'0d" year month day)))

(defun get-portage-date ()
  (if (eq *portage-date* :auto)
      (get-formatted-date (get-universal-time))
      *portage-date*))

(defun get-stage3-date ()
  (if (eq *stage3-date* :auto)
      (let* ((now (get-universal-time))
             (day-of-week (nth-value 6 (decode-universal-time now 0)))
             ;; decode-universal-time returns 0 for Monday, 6 for Sunday
             (monday-time (- now (* day-of-week 86400))))
        (get-formatted-date monday-time))
      *stage3-date*))

;; --- Dynamic Configuration File Generators ---
(defun generate-world-packages ()
  (let ((pkgs '("app-admin/sudo"
                "app-admin/sysklogd"
                "sys-apps/ripgrep"
                "sys-process/htop"
                "x11-base/xorg-server"
                "x11-terms/xterm"
                "x11-wm/dwm"
                "sys-kernel/gentoo-sources"
                "sys-kernel/linux-firmware"
                "sys-kernel/dracut"
                "sys-fs/e2fsprogs"
                "sys-fs/erofs-utils"
                "sys-fs/squashfs-tools"
                "sys-fs/lvm2"
                "sys-fs/btrfs-progs"
                "sys-fs/cryptsetup"
                "app-portage/cpuid2cpuflags"
                "app-portage/eix"
                "app-portage/gentoolkit"
                "dev-vcs/git"
                "net-wireless/iwd"
                "net-wireless/iw"
                "net-misc/dhcpcd"
                "net-misc/autossh")))
    (unless *minimal-image*
      (setf pkgs (append pkgs '("app-containers/docker"
                                "app-containers/docker-buildx"
                                "app-containers/docker-cli"
                                "app-crypt/p11-kit"
                                "app-misc/fastfetch"
                                "app-misc/fdupes"
                                "app-misc/jq"
                                "app-misc/mc"
                                "app-misc/tmate"
                                "app-misc/tmux"
                                "app-pda/ifuse"
                                "app-shells/bash-completion"
                                "app-shells/zsh"
                                "app-text/mupdf"
                                "app-text/tree"
                                "dev-build/ninja"
                                "dev-debug/ltrace"
                                "dev-debug/strace"
                                "dev-libs/nss"
                                "dev-python/btrfs"
                                "media-fonts/wqy-zenhei"
                                "media-gfx/feh"
                                "media-gfx/scrot"
                                "media-sound/pulsemixer"
                                "media-video/mpv"
                                "net-analyzer/hping"
                                "net-analyzer/iftop"
                                "net-analyzer/iptraf-ng"
                                "net-analyzer/macchanger"
                                "net-analyzer/netcat"
                                "net-analyzer/nethogs"
                                "net-analyzer/ngrep"
                                "net-analyzer/ssmping"
                                "net-dns/bind-tools"
                                "net-dns/dnsmasq"
                                "net-im/signal-desktop-bin"
                                "net-misc/bridge-utils"
                                "net-misc/chrony"
                                "net-misc/dhcp"
                                "net-misc/freerdp"
                                "net-misc/ipcalc"
                                "net-misc/mosh"
                                "net-misc/sipcalc"
                                "net-misc/socat"
                                "net-misc/udpcast"
                                "net-misc/whois"
                                "net-print/cups"
                                "net-vpn/tailscale"
                                "sys-apps/cpuid"
                                "sys-apps/dmidecode"
                                "sys-apps/ethtool"
                                "sys-apps/lm-sensors"
                                "sys-apps/lshw"
                                "sys-apps/pciutils"
                                "sys-apps/pv"
                                "sys-apps/qdirstat"
                                "sys-apps/smartmontools"
                                "sys-apps/usbutils"
                                "sys-devel/mold"
                                "sys-firmware/sof-firmware"
                                "sys-power/acpi"
                                "sys-power/tlp"
                                "sys-process/btop"
                                "sys-process/iotop"
                                "sys-process/lsof"
                                "sys-process/psmisc"
                                "x11-apps/setxkbmap"
                                "x11-apps/xhost"
                                "x11-apps/xkill"
                                "x11-apps/xrandr"
                                "x11-apps/xset"
                                "x11-libs/libXtst"
                                "x11-misc/redshift"
                                "x11-misc/xclip"
                                "x11-misc/xtrlock"
                                "x11-terms/alacritty"))))
    
    (when (or *enable-docker* (and (not *minimal-image*) (not (member "app-containers/docker" pkgs :test #'string=))))
      (setf pkgs (append pkgs '("app-containers/docker" "app-containers/docker-buildx" "app-containers/docker-cli"))))
    (when *enable-dev-tools*
      (setf pkgs (append pkgs '("dev-build/ninja" "dev-debug/strace" "dev-debug/ltrace" "sys-devel/mold"))))
    (when *enable-media-playback*
      (setf pkgs (append pkgs '("media-video/mpv" "media-gfx/feh" "media-gfx/scrot" "media-sound/pulsemixer"))))
    (when *enable-network-admin*
      (setf pkgs (append pkgs '("net-analyzer/hping" "net-analyzer/iftop" "net-analyzer/iptraf-ng" "net-analyzer/macchanger" "net-analyzer/netcat" "net-analyzer/nethogs" "net-analyzer/ngrep" "net-analyzer/ssmping" "net-dns/bind-tools" "net-dns/dnsmasq"))))
    (when *enable-remote-access*
      (setf pkgs (append pkgs '("net-misc/autossh" "net-misc/mosh" "net-misc/freerdp" "net-vpn/tailscale" "net-misc/bridge-utils"))))
    (when *enable-cli-productivity*
      (setf pkgs (append pkgs '("app-misc/jq" "app-misc/mc" "app-misc/tmate" "app-misc/tmux" "app-shells/zsh" "app-shells/bash-completion" "app-text/tree"))))
    (when *enable-sys-monitoring-hw*
      (setf pkgs (append pkgs '("sys-apps/cpuid" "sys-apps/dmidecode" "sys-apps/ethtool" "sys-apps/lm-sensors" "sys-apps/lshw" "sys-apps/nvme-cli" "sys-apps/pciutils" "sys-apps/usbutils" "sys-process/btop" "sys-process/iotop" "sys-process/lsof" "sys-process/psmisc"))))
    (when *enable-power-management*
      (setf pkgs (append pkgs '("sys-power/acpi" "sys-power/tlp"))))
    (when *enable-desktop-extras*
      (setf pkgs (append pkgs '("media-fonts/wqy-zenhei" "x11-misc/redshift" "x11-misc/xclip" "x11-misc/xtrlock"))))
    (when *enable-signal*
      (setf pkgs (append pkgs '("net-im/signal-desktop-bin"))))
    (when *enable-pdf-viewer*
      (setf pkgs (append pkgs '("app-text/mupdf"))))
    (when *enable-ios-sync*
      (setf pkgs (append pkgs '("app-pda/ifuse"))))
    (when *enable-alacritty*
      (setf pkgs (append pkgs '("x11-terms/alacritty"))))

    (when *enable-emacs-sbcl*
      (setf pkgs (append pkgs '("app-editors/emacs" "dev-lisp/sbcl"))))
    (when *enable-rust*
      (setf pkgs (append pkgs '("dev-lang/rust-bin" "virtual/rust" "dev-util/cargo-c"))))
    (when *enable-go*
      (setf pkgs (append pkgs '("dev-lang/go" "dev-lang/go-bootstrap"))))
    (when *enable-uv-ruff*
      (setf pkgs (append pkgs '("dev-python/uv" "dev-util/ruff"))))
    (when (and *enable-nvidia* (member *target-machine* '(:both :workstation)))
      (setf pkgs (append pkgs '("x11-drivers/nvidia-drivers"))))
    (when (and *enable-nvidia-cuda* (member *target-machine* '(:both :workstation)))
      (setf pkgs (append pkgs '("dev-util/nvidia-cuda-toolkit"))))
    (when *enable-wireshark*
      (setf pkgs (append pkgs '("net-analyzer/wireshark"))))
    (when *enable-lua*
      (setf pkgs (append pkgs '("dev-lang/lua"))))
    (when *enable-firefox*
      (setf pkgs (append pkgs '("www-client/firefox-bin"))))
    (when *enable-google-chrome*
      (setf pkgs (append pkgs '("www-client/google-chrome"))))
    (when *enable-llvm*
      (setf pkgs (append pkgs '("llvm-core/llvm" "llvm-core/clang" "dev-util/clang-format"))))
    (when *enable-clion*
      (setf pkgs (append pkgs '("dev-util/clion"))))
    
    (case *audio-system*
      (:pipewire
       (setf pkgs (append pkgs '("media-video/pipewire" "media-video/wireplumber" "media-sound/pulsemixer"))))
      (:alsa
       (setf pkgs (append pkgs '("media-libs/alsa-lib" "media-sound/alsa-utils" "media-plugins/alsa-plugins")))))
    
    (remove-duplicates pkgs :test #'string=)))

(defun generate-make-conf ()
  (let ((video-cards (case *target-machine*
                       (:thinkpad "amdgpu radeonsi")
                       (:workstation "nvidia")
                       (t "nvidia amdgpu radeonsi")))
        (llvm-targets (case *target-machine*
                        (:thinkpad "X86 AMDGPU")
                        (:workstation "X86 NVPTX")
                        (t "X86 NVPTX AMDGPU")))
        (use-flags (case *audio-system*
                     (:pipewire "-vaapi -doc -cups -opencl -jemalloc -wayland pipewire dbus elogind policykit udev")
                     (:alsa "-vaapi -doc -cups -opencl -jemalloc -wayland -pipewire alsa dbus elogind policykit udev")
                     (t "-vaapi -doc -cups -opencl -jemalloc -wayland -pipewire -alsa dbus elogind policykit udev"))))
    (format nil "COMMON_FLAGS=\"-O2 -pipe\"
CFLAGS=\"${COMMON_FLAGS}\"
CXXFLAGS=\"${COMMON_FLAGS}\"
FCFLAGS=\"${COMMON_FLAGS}\"
FFLAGS=\"${COMMON_FLAGS}\"

LC_MESSAGES=C.UTF-8

USE=\"~a\"
VIDEO_CARDS=\"~a\"
LLVM_TARGETS=\"~a\"

ACCEPT_LICENSE=\"*\"

FEATURES=\"-ipc-sandbox -network-sandbox -pid-sandbox getbinpkg binpkg-request-signature\"

GENTOO_MIRRORS=\"https://pkg.adfinis-on-exoscale.ch/gentoo/ \\
    http://pkg.adfinis-on-exoscale.ch/gentoo/ \\
    https://ch.mirrors.cicku.me/gentoo/ \\
    http://ch.mirrors.cicku.me/gentoo/ \\
    https://mirror.init7.net/gentoo/ \\
    http://mirror.init7.net/gentoo/ \\
    rsync://mirror.init7.net/gentoo/\"
" use-flags video-cards llvm-targets)))

(defun generate-package-use ()
  (let ((lines '("media-libs/vulkan-loader X"
                 "media-libs/libpulse X"
                 "sys-libs/minizip-ng compat"
                 "x11-wm/dwm savedconfig -xinerama"
                 "sys-fs/lvm2 lvm"
                 "sys-fs/squashfs-tools xattr -debug -lz4 -lzma -lzo zstd")))
    (when (member *target-machine* '(:both :thinkpad))
      (push "x11-libs/libdrm video_cards_radeon" lines))
    (case *audio-system*
      (:pipewire
       (push "media-video/pipewire alsa dbus sound-server udev" lines)
       (push "media-video/wireplumber dbus" lines)
       (push "media-plugins/alsa-plugins pulseaudio" lines))
      (:alsa
       (push "media-plugins/alsa-plugins -pulseaudio" lines)))
    (format nil "~{~a~^~%~}~%" (nreverse lines))))

(defun generate-package-accept-keywords ()
  (let ((lines '("sys-kernel/gentoo-sources ~amd64"
                 "sys-kernel/dracut-crypt-ssh ~amd64"
                 ">=net-misc/freerdp-3.17.2-r1 ~amd64")))
    (when (or *enable-uv-ruff* (not *minimal-image*))
      (push "dev-util/ruff ~amd64" lines))
    (when (or *enable-clion* (not *minimal-image*))
      (push "dev-util/clion ~amd64" lines))
    (when (and *enable-nvidia* (member *target-machine* '(:both :workstation)))
      (push "x11-drivers/nvidia-drivers ~amd64" lines))
    (when (and *enable-nvidia-cuda* (member *target-machine* '(:both :workstation)))
      (push "dev-util/nvidia-cuda-toolkit ~amd64" lines))
    (format nil "~{~a~^~%~}~%" (nreverse lines))))

(defun generate-package-env ()
  (let ((lines '("sys-devel/llvm low-mem"
                 "sys-devel/gcc low-mem"
                 "dev-lang/rust low-mem"
                 "www-client/google-chrome low-mem"
                 "www-client/chromium low-mem"
                 "www-client/firefox low-mem"
                 "dev-vcs/git lto-gcc"
                 "app-editors/emacs lto-gcc"
                 "media-video/ffmpeg lto-gcc"
                 "media-video/mpv lto-gcc"
                 "net-misc/freerdp lto-gcc")))
    (format nil "~{~a~^~%~}~%" lines)))

;; --- Helper macro for emerge commands with dual host+cache mounts ---
(defun run-emerge (command)
  (let ((mounts-str "type=bind,source=./distfiles,target=/var/cache/distfiles-host,ro \
--mount=type=bind,source=./binpkgs,target=/var/cache/binpkgs-host,ro \
--mount=type=cache,target=/var/cache/distfiles-cache \
--mount=type=cache,target=/var/cache/binpkgs-cache"))
    `(run :mount ,mounts-str
          (and "mkdir -p /var/cache/distfiles /var/cache/binpkgs"
               "cp -rn /var/cache/distfiles-host/. /var/cache/distfiles/ 2>/dev/null || true"
               "cp -rn /var/cache/distfiles-cache/. /var/cache/distfiles/ 2>/dev/null || true"
               "cp -rn /var/cache/binpkgs-host/. /var/cache/binpkgs/ 2>/dev/null || true"
               "cp -rn /var/cache/binpkgs-cache/. /var/cache/binpkgs/ 2>/dev/null || true"
               ,command
               "cp -rn /var/cache/distfiles/. /var/cache/distfiles-cache/ 2>/dev/null || true"
               "cp -rn /var/cache/binpkgs/. /var/cache/binpkgs-cache/ 2>/dev/null || true"))))

;; --- Inline service & configuration files content ---
(defparameter *resolv-conf*
  "nameserver 1.1.1.1
nameserver 8.8.8.8
")

(defparameter *user-session-sh*
  "#!/bin/sh
uid=\"$(id -u 2>/dev/null || printf '')\"
if [ -n \"${uid}\" ] && [ \"${uid}\" -ge 1000 ] 2>/dev/null; then
  : \"${XDG_RUNTIME_DIR:=/run/user/${uid}}\"
  export XDG_RUNTIME_DIR
  if [ -z \"${DBUS_SESSION_BUS_ADDRESS:-}\" ]; then
    export DBUS_SESSION_BUS_ADDRESS=\"unix:path=${XDG_RUNTIME_DIR}/bus\"
  fi
  if [ -z \"${PULSE_SERVER:-}\" ]; then
    export PULSE_SERVER=\"unix:${XDG_RUNTIME_DIR}/pulse/native\"
  fi
fi
")

(defparameter *user-dbus-initd*
  "#!/sbin/openrc-run
description=\"User D-Bus session bus\"
command=\"/usr/bin/dbus-daemon\"
command_args=\"--session --address=unix:path=${XDG_RUNTIME_DIR}/bus --nofork --nopidfile --nosyslog\"
command_background=\"yes\"
pidfile=\"${XDG_RUNTIME_DIR}/dbus-session.pid\"
")

(defparameter *user-pipewire-initd*
  "#!/sbin/openrc-run
description=\"PipeWire media server\"
command=\"/usr/bin/pipewire\"
command_background=\"yes\"
pidfile=\"${XDG_RUNTIME_DIR}/pipewire.pid\"
depend() {
  need dbus
}
")

(defparameter *user-pipewire-pulse-initd*
  "#!/sbin/openrc-run
description=\"PipeWire PulseAudio compatibility server\"
command=\"/usr/bin/pipewire-pulse\"
command_background=\"yes\"
pidfile=\"${XDG_RUNTIME_DIR}/pipewire-pulse.pid\"
depend() {
  need pipewire dbus
}
")

(defparameter *user-wireplumber-initd*
  "#!/sbin/openrc-run
description=\"WirePlumber session manager\"
command=\"/usr/bin/wireplumber\"
command_background=\"yes\"
pidfile=\"${XDG_RUNTIME_DIR}/wireplumber.pid\"
depend() {
  need pipewire dbus
}
")

(defparameter *reverse-ssh-eu-initd*
  "#!/sbin/openrc-run
name=\"reverse-ssh-eu\"
description=\"Reverse SSH tunnel to tinyeu\"
supervisor=\"supervise-daemon\"
command=\"/usr/bin/autossh\"
command_args=\"-M 0 -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -R 2332:localhost:22 tinyeu\"
command_user=\"kiel\"
supervise_daemon_args=\"-e HOME=/home/kiel\"
depend() {
    use net
    after iwd
    want tailscale
}
")

(defparameter *reverse-ssh-us-initd*
  "#!/sbin/openrc-run
name=\"reverse-ssh-us\"
description=\"Reverse SSH tunnel to tinyus\"
supervisor=\"supervise-daemon\"
command=\"/usr/bin/autossh\"
command_args=\"-M 0 -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -R 2332:localhost:22 tinyus\"
command_user=\"kiel\"
supervise_daemon_args=\"-e HOME=/home/kiel\"
depend() {
    use net
    after iwd
    want tailscale
}
")

(defparameter *user-runtime-initd*
  "#!/sbin/openrc-run
description=\"Prepare XDG runtime directories for lingering OpenRC user sessions\"
depend() {
  need localmount
  before user.kiel
}
start() {
  ebegin \"Preparing XDG runtime directory for kiel\"
  checkpath -d -m 0755 /run/user
  checkpath -d -o kiel:kiel -m 0700 /run/user/1000
  checkpath -d -o kiel:kiel -m 0755 /home/kiel/.config
  checkpath -d -o kiel:kiel -m 0755 /home/kiel/.config/rc
  checkpath -d -o kiel:kiel -m 0755 /home/kiel/.config/rc/runlevels
  checkpath -d -o kiel:kiel -m 0755 /home/kiel/.config/rc/runlevels/default
  ln -snf /etc/user/init.d/dbus /home/kiel/.config/rc/runlevels/default/dbus
  ln -snf /etc/user/init.d/pipewire /home/kiel/.config/rc/runlevels/default/pipewire
  ln -snf /etc/user/init.d/pipewire-pulse /home/kiel/.config/rc/runlevels/default/pipewire-pulse
  ln -snf /etc/user/init.d/wireplumber /home/kiel/.config/rc/runlevels/default/wireplumber
  chown -h kiel:kiel \\
    /home/kiel/.config/rc/runlevels/default/dbus \\
    /home/kiel/.config/rc/runlevels/default/pipewire \\
    /home/kiel/.config/rc/runlevels/default/pipewire-pulse \\
    /home/kiel/.config/rc/runlevels/default/wireplumber
  eend $?
}
")

(defparameter *xinitrc*
  "xrandr --output DP-0 --scale 1x1 --rotate left; xrandr --output DP-2 --scale 1x1 --rotate right; xrandr --output DP-2 --right-of DP-0

# xrandr --output DP-0 --scale 2x2; xrandr --output DP-2 --scale 2x2 --pos 2160x0
# xrandr --output DP-0 --scale 2x2; xrandr --output DP-2 --scale 2x2 --below DP-0 --pos 0x3840

export XDG_RUNTIME_DIR=\"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}\"
export DBUS_SESSION_BUS_ADDRESS=\"${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}\"
export PULSE_SERVER=\"${PULSE_SERVER:-unix:${XDG_RUNTIME_DIR}/pulse/native}\"

setxkbmap -layout us -variant colemak

xterm -e btop &
slstatus &
#xterm &
# Start PipeWire stack
~/start-pipewire.sh &

cd /home/kiel
# Use dbus-run-session to ensure a working session bus
exec dbus-run-session dwm
#exec /usr/local/bin/plwm
")

;; --- Main Dockerfile Meta-Generator ---
(defparameter *gentoo-code*
  `(toplevel
     (directive syntax "docker/dockerfile:1")
     (comment "Base images")
     (from ,(format nil "gentoo/portage:~a" (get-portage-date)) :as portage)
     (comment "Stage3 base (1GB)")
     (comment "https://hub.docker.com/r/gentoo/stage3/tags")
     (from ,(format nil "gentoo/stage3:nomultilib-~a" (get-stage3-date)) :as base)
     (comment "https://hub.docker.com/r/gentoo/portage/tags")
     (comment "Copy full Portage tree (570MB)")
     (copy "/var/db/repos/gentoo" "/var/db/repos/gentoo" :from portage)
     
     (comment "Portage configuration (Dynamic Heredocs)")
     (run "eselect profile set default/linux/amd64/23.0/no-multilib")
     (copy :heredoc "/etc/portage/package.accept_keywords/package.accept_keywords" ,(generate-package-accept-keywords))
     (copy :heredoc "/etc/portage/make.conf" ,(generate-make-conf))
     (copy :heredoc "/etc/portage/package.use" ,(generate-package-use))
     (copy :heredoc "/etc/portage/package.env" ,(generate-package-env))
     
     (comment "Portage env files")
     (run "mkdir -p /etc/portage/env")
     (copy :heredoc "/etc/portage/env/low-mem" "MAKEOPTS=\"-j8\"")
     (copy :heredoc "/etc/portage/env/lto-gcc"
           #r(WARNING_FLAGS="-Werror=odr -Werror=lto-type-mismatch -Werror=strict-aliasing"
LTO_FLAGS="-flto ${WARNING_FLAGS}"
CFLAGS="${CFLAGS} ${LTO_FLAGS}"
CXXFLAGS="${CXXFLAGS} ${LTO_FLAGS}"
FCFLAGS="${FCFLAGS} ${LTO_FLAGS}"
FFLAGS="${FFLAGS} ${LTO_FLAGS}"
LDFLAGS="${LDFLAGS} ${LTO_FLAGS}"
))
     
     (comment "Keep the world set on PipeWire and let PipeWire provide PulseAudio compatibility.")
     (copy :heredoc "/var/lib/portage/world" ,(format nil "~{~a~^~%~}~%" (generate-world-packages)))
     (copy "config/dwm-6.8" "/etc/portage/savedconfig/x11-wm/dwm-6.8")
     
     (env KVER_PURE ,*kver*)
     (env KVER_SOURCE "${KVER_PURE}-gentoo")
     (env KVER_RELEASE "${KVER_SOURCE}-dist")
     (run "df -h")
     
     (comment ,(format nil "Recreate the gentoo-sources-~a ebuild" *kver*))
     (copy :heredoc ,(format nil "/var/db/repos/gentoo/sys-kernel/gentoo-sources/gentoo-sources-~a.ebuild" *kver*)
           #r(EAPI="8"
ETYPE="sources"
K_WANT_GENPATCHES="base extras experimental"
K_GENPATCHES_VER="42"

inherit kernel-2
detect_version
detect_arch

DESCRIPTION="Full sources including the Gentoo patchset for the ${KV_MAJOR}.${KV_MINOR} kernel tree"
HOMEPAGE="https://dev.gentoo.org/~alicef/genpatches"
SRC_URI="${KERNEL_URI} ${GENPATCHES_URI} ${ARCH_URI}"
KEYWORDS="~alpha amd64 arm arm64 ~hppa ~m68k ~mips ppc ppc64 ~riscv ~s390 ~sparc x86"
IUSE="experimental"
))
     (run ,(format nil "ebuild /var/db/repos/gentoo/sys-kernel/gentoo-sources/gentoo-sources-~a.ebuild manifest" *kver*))
     
     ,(run-emerge "emerge =sys-kernel/gentoo-sources-${KVER_PURE}")
     (run "eselect kernel list")
     (run "eselect kernel set linux-${KVER_SOURCE}")
     
     (workdir "/usr/src/linux")
     (copy "config/config6.18.18" ".config")
     (run #r(sed -i \
    -e 's/^CONFIG_LOCALVERSION="-gentoo-dist"/CONFIG_LOCALVERSION="-dist"/' \
    -e 's/^CONFIG_DEBUG_INFO=y/# CONFIG_DEBUG_INFO is not set/' \
    -e 's/^CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT=y/# CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT is not set/' \
    -e 's/^CONFIG_DEBUG_INFO_BTF=y/# CONFIG_DEBUG_INFO_BTF is not set/' \
    -e 's/^CONFIG_DEBUG_INFO_BTF_MODULES=y/# CONFIG_DEBUG_INFO_BTF_MODULES is not set/' \
    .config))
     (run "make prepare")
     
     (comment "compile the kernel")
     (run "make -j32")
     (run "make modules_install")
     (run "depmod -a ${KVER_RELEASE}")
     (run "make install")
     
     (comment "Clean up the locales")
     (run (and "printf 'en_US.UTF-8 UTF-8\\n' > /etc/locale.gen"
               "locale-gen"
               "env-update"
               ". /etc/profile"))
     
     (env LANG "en_US.UTF-8"
          LC_ALL "en_US.UTF-8")
     (run "env-update && source /etc/profile")
     
     ,(run-emerge "emerge -1 sys-apps/portage")
     (run #r(sed -i \
    -e '/^net-analyzer\/arping\>/d' \
    -e '/^net-misc\/speedtest-cli\>/d' \
    -e '/^sys-process\/progress\>/d' \
    -e '/^sys-process\/sysstat\>/d' \
    /var/lib/portage/world))
     (run (and "mkdir -p /etc/portage/package.use"
               "touch /etc/portage/package.use/zz-late-world"
               "grep -qxF 'app-text/xmlto text' /etc/portage/package.use/zz-late-world || printf '\\napp-text/xmlto text\\n' >> /etc/portage/package.use/zz-late-world"))
     
     ,@(if *split-world-build*
           `((run (and "emerge -pqe --columns @world | awk '$2 ~ /\\// {print $2}' > /tmp/world_packages.txt"
                       "total_lines=$(wc -l < /tmp/world_packages.txt)"
                       "lines_per_stage=$(( (total_lines + 9) / 10 ))"
                       "for i in $(seq 1 10); do start=$(( (i - 1) * lines_per_stage + 1 )); end=$(( i * lines_per_stage )); sed -n \"${start},${end}p\" /tmp/world_packages.txt > \"/tmp/world_stage_${i}.txt\"; done"))
             ,@(loop for i from 1 to 10
                     collect (run-emerge (format nil "if [ -s /tmp/world_stage_~d.txt ]; then emerge --ask=n $(grep -E '.+/.+' /tmp/world_stage_~d.txt); fi" i i))))
           `(,(run-emerge "emerge -uNav @world")))
           
     (run "gcc-config -l")
     
     (comment "Temporarily install package analysis tools")
     ,(run-emerge "emerge --ask=n app-portage/genlop app-portage/gentoolkit")
     (run (and "qlist -Iv sys-devel/gcc"
               #r#echo "Generating package statistics..."#
               #r(for pkg in $(qlist -I); do \
      SIZE=$(qsize -m "$pkg" | awk '{print $5$6}'); \
      TIME=$(genlop -t "$pkg" | grep "merge time" | tail -n 1 | sed 's/.*merge time: //'); \
      echo "$pkg | Size: ${SIZE:-N/A} | Build Time: ${TIME:-N/A}"; \
    done > /packages.txt)))
     ,(run-emerge "emerge -C app-portage/genlop app-portage/gentoolkit || true")
     
     (comment "Sudo policy")
     (run "mkdir -p /etc/sudoers.d")
     (copy :heredoc "/etc/sudoers.d/wheel" "%wheel ALL=(ALL:ALL) NOPASSWD: ALL")
     
     (comment "slstatus")
     (workdir "/usr/src")
     (run "git clone https://git.suckless.org/slstatus")
     (workdir "/usr/src/slstatus")
     (copy "config/slstatus_config.h" ".config")
     (run "make -j32")
     (run "make install")
     (run "make clean")
     
     (run (and "groupadd -f input"
               "useradd -m -G users,wheel,audio,video,input -s /bin/bash kiel"
               #r#for grp in libvirt kvm qemu; do if getent group "${grp}" >/dev/null; then usermod -aG "${grp}" kiel; fi; done#))
     
     (copy :heredoc "/home/kiel/.xinitrc" ,*xinitrc*)
     
     (copy "config/activate" "/home/kiel/activate")
     (copy "config/start2" "/home/kiel/start2")
     (copy "config/start-pipewire.sh" "/home/kiel/start-pipewire.sh")
     
     (run (and "chmod +x /home/kiel/activate /home/kiel/start2 /home/kiel/start-pipewire.sh"
               "chown kiel:kiel /home/kiel/activate /home/kiel/start2 /home/kiel/start-pipewire.sh"))
     
     (copy :heredoc "/etc/init.d/user-runtime" ,*user-runtime-initd*)
     (copy :heredoc "/etc/profile.d/zz-openrc-user-session.sh" ,*user-session-sh*)
     (copy :heredoc "/etc/user/init.d/dbus" ,*user-dbus-initd*)
     (copy :heredoc "/etc/user/init.d/pipewire" ,*user-pipewire-initd*)
     (copy :heredoc "/etc/user/init.d/pipewire-pulse" ,*user-pipewire-pulse-initd*)
     (copy :heredoc "/etc/user/init.d/wireplumber" ,*user-wireplumber-initd*)
     (copy :heredoc "/etc/resolv.conf" ,*resolv-conf*)
     (copy :heredoc "/etc/init.d/reverse-ssh-eu" ,*reverse-ssh-eu-initd*)
     (copy :heredoc "/etc/init.d/reverse-ssh-us" ,*reverse-ssh-us-initd*)
     
     (run (and "chmod +x /etc/init.d/reverse-ssh-*"
               "rc-update add sshd default"
               "rc-update add reverse-ssh-eu default"
               "rc-update add reverse-ssh-us default"))
     
     (user kiel)
     (env HOME "/home/kiel")
     
     (comment "Install Emacs packages from MELPA in batch mode")
     ,@(when (or *enable-emacs-sbcl* (not *minimal-image*))
         `((run #r(emacs --batch \
     --eval "(require 'package)" \
     --eval "(add-to-list 'package-archives '(\"melpa\" . \"https://melpa.org/packages/\") t)" \
     --eval "(package-initialize)" \
     --eval "(package-refresh-contents)" \
     --eval "(dolist (pkg '(magit paredit slime)) (package-install pkg))"))))
     
     (user root)
     (run "mkdir -p /usr/local/share/openrc-host-config")
     
     (copy "config/activate" "/usr/local/share/openrc-host-config/activate")
     (copy "config/start2" "/usr/local/share/openrc-host-config/start2")
     (copy :heredoc "/usr/local/share/openrc-host-config/reverse-ssh-eu.initd" ,*reverse-ssh-eu-initd*)
     (copy :heredoc "/usr/local/share/openrc-host-config/reverse-ssh-us.initd" ,*reverse-ssh-us-initd*)
     
     (run "fc-cache -fv")
     (copy :heredoc "/etc/conf.d/modules" "modules=\"amdgpu mt7921e\"")
     (copy :heredoc "/etc/conf.d/keymaps" "keymap=\"colemak\"")
     (run :heredoc #r(set -e
if grep -q '^rc_logger=' /etc/rc.conf 2>/dev/null; then
  sed -i 's/^rc_logger=.*/rc_logger="YES"/' /etc/rc.conf
else
  printf '%s\n' 'rc_logger="YES"' >> /etc/rc.conf
fi
if grep -q '^rc_log_path=' /etc/rc.conf 2>/dev/null; then
  sed -i 's|^rc_log_path=.*|rc_log_path="/var/log/rc.log"|' /etc/conf
else
  printf '%s\n' 'rc_log_path="/var/log/rc.log"' >> /etc/rc.conf
fi
if grep -q '^rc_verbose=' /etc/rc.conf 2>/dev/null; then
  sed -i 's/^rc_verbose=.*/rc_verbose="YES"/' /etc/rc.conf
else
  printf '%s\n' 'rc_verbose="YES"' >> /etc/rc.conf
fi
if grep -q '^rc_autostart_user=' /etc/rc.conf 2>/dev/null; then
  sed -i 's/^rc_autostart_user=.*/rc_autostart_user="NO"/' /etc/rc.conf
else
  printf '%s\n' 'rc_autostart_user="NO"' >> /etc/rc.conf
fi
if ! grep -q '^s0:12345:respawn:/sbin/agetty 115200 ttyS0 vt100$' /etc/inittab; then
  printf '%s\n' 's0:12345:respawn:/sbin/agetty 115200 ttyS0 vt100' >> /etc/inittab
fi
if ! grep -qx 'ttyS0' /etc/securetty; then
  printf '%s\n' 'ttyS0' >> /etc/securetty
fi
chmod 0755 /etc/init.d/user-runtime /etc/profile.d/zz-openrc-user-session.sh \
     /etc/user/init.d/dbus /etc/user/init.d/pipewire /etc/user/init.d/pipewire-pulse /etc/user/init.d/wireplumber
install -d -m 0755 /run/user
install -d -o kiel -g kiel -m 0700 /run/user/1000
test -e /etc/init.d/user
ln -sf /etc/init.d/user /etc/init.d/user.kiel
install -d -o kiel -g kiel -m 0755 /home/kiel/.config/rc/runlevels/default
ln -sf /etc/user/init.d/dbus /home/kiel/.config/rc/runlevels/default/dbus
rc-update add udev sysinit
rc-update add udev-trigger sysinit
rc-update add udev-settle sysinit
rc-update add modules boot
rc-update add keymaps boot
rc-update add user-runtime default
rc-update add user.kiel default
rc-update add dbus default
rc-update add iwd default
chown -R kiel:kiel /home/kiel/.config))
     
     (run "rm -rf /var/tmp/portage/*")
     
     ;; Only clean up toolchains if they aren't explicitly enabled
     (run ,(format nil "emerge -C ~{~a~^ ~} || true"
                   (let (to-clean)
                     (unless (or *enable-rust* (not *minimal-image*))
                       (push "dev-lang/rust-bin" to-clean)
                       (push "virtual/rust" to-clean)
                       (push "dev-util/cargo-c" to-clean))
                     (unless (or *enable-go* (not *minimal-image*))
                       (push "dev-lang/go" to-clean)
                       (push "dev-lang/go-bootstrap" to-clean))
                     (if to-clean to-clean '("dummy-pkg-to-avoid-syntax-error")))))
                     
     (workdir "/")
     ,(run-emerge "emerge --ask=n sys-fs/e2fsprogs sys-fs/erofs-utils || true")
     (copy "config/mount-overlayfs.sh" "/usr/lib/dracut/modules.d/70overlayfs")
     (run "chmod +x /usr/lib/dracut/modules.d/70overlayfs/*.sh")
     (run (seq #r(dracut \
-m "kernel-modules base dmsquash-live dm udev-rules crypt lvm overlayfs" \
--filesystems "squashfs erofs vfat ext4 overlay btrfs" \
--add-drivers "libnvdimm nd_pmem nd_btt nd_blk dax device_dax dax_pmem dax_pmem_core nd_e820" \
--kver=${KVER_RELEASE} \
--install "stat blockdev" \
--force \
/boot/initramfs_squash_sda1-x86_64.img)))
     
     ;; eix validation always runs
     ,(run-emerge "emerge --ask=n --oneshot app-portage/genlop")
     (run #r(set -e \
&& printf 'package\tsize_mib\tbuild_seconds\tbuild_time_human\n' > /packages.tsv \
&& time_threshold_mib=50 \
&& for pkg in $(qlist -I); do \
      size_line=$(qsize -m "$pkg" | head -n 1 || true); \
      size_mib=$(printf '%s\n' "$size_line" | sed -nE 's/.*,[[:space:]]*([0-9.]+)[[:space:]]+MiB$/\1/p'); \
      if [ -z "$size_mib" ]; then \
        size_kib=$(printf '%s\n' "$size_line" | sed -nE 's/.*,[[:space:]]*([0-9.]+)[[:space:]]+KiB$/\1/p'); \
        if [ -n "$size_kib" ]; then \
          size_mib=$(awk "BEGIN { printf \"%.3f\", ${size_kib}/1024 }"); \
        else \
          size_mib=0; \
        fi; \
      fi; \
      is_large=$(awk "BEGIN { print (${size_mib} >= ${time_threshold_mib}) ? 1 : 0 }"); \
      if [ "$is_large" -eq 1 ]; then \
        time_human=$(genlop -t "$pkg" 2>/dev/null | sed -nE 's/.*merge time: (.*)/\1/p' | tail -n 1 | sed -E 's/\x1B\[[0-9;]*[[:alpha:]]//g'); \
        build_seconds=$(TIME_HUMAN="$time_human" awk 'BEGIN{t=ENVIRON["TIME_HUMAN"]; gsub(/,/, "", t); n=split(t, a, / +/); s=0; for (i=1; i<=n; i++) { if (a[i] ~ /^[0-9]+$/) { v=a[i]+0; u=a[i+1]; if (u ~ /^day/) s+=v*86400; else if (u ~ /^hour/) s+=v*3600; else if (u ~ /^minute/) s+=v*60; else if (u ~ /^second/) s+=v; } } print s }'); \
      else \
        time_human='-'; \
        build_seconds=0; \
      fi; \
      printf '%s\t%s\t%s\t%s\n' "$pkg" "$size_mib" "${build_seconds:-0}" "${time_human:-N/A}" >> /packages.tsv; \
    done \
&& { \
      printf '%-40s %10s %14s  %s\n' "Package" "Size MiB" "Build Seconds" "Build Time"; \
      tail -n +2 /packages.tsv | sort -t "$(printf '\t')" -k2,2nr -k3,3nr | awk -F '\t' '{printf "%-40s %10s %14s  %s\n", $1, $2, $3, $4}'; \
    } > /packages.txt \
&& emerge -C app-portage/genlop || true))
     
     (run "df -h")
     
     ;; Flaggie optional cleanup
     ,@(when *enable-flaggie-cleanup*
         `(,(run-emerge "emerge --ask=n app-portage/flaggie")
           (run "flaggie --cleanup")
           ,(run-emerge "emerge -C app-portage/flaggie || true")))
     
     ;; Always run obsolete test and write validation report
     (run "eix-update")
     (run "eix-test-obsolete > /packages_obsolete.txt || true")
     
     ,@(when (member *target-machine* '(:both :workstation))
         `((run #r(set -e \
  && echo "Preparing NVIDIA squashfs" \
  && test -e /lib/modules/${KVER_RELEASE}/video/nvidia.ko \
  && rm -rf /tmp/fw_original /tmp/fw_nv_root \
  && mkdir -p /tmp/fw_original /tmp/fw_nv_root/usr/lib/firmware \
  && cp -a /usr/lib/firmware/. /tmp/fw_original/ \
  && modinfo -F firmware /lib/modules/${KVER_RELEASE}/video/nvidia.ko \
       | sort -u \
       | while IFS= read -r rel; do \
           test -n "${rel}"; \
           src="/usr/lib/firmware/${rel}"; \
           dst="/tmp/fw_nv_root/usr/lib/firmware/${rel}"; \
           test -e "${src}"; \
           mkdir -p "$(dirname "${dst}")"; \
           cp -a "${src}" "${dst}"; \
           done \
  && rm -rf /usr/lib/firmware/* \
  && cp -a /tmp/fw_nv_root/usr/lib/firmware/. /usr/lib/firmware/ \
  && mksquashfs / /gentoo.squashfs_nv \
    -comp zstd \
    -Xcompression-level 19 \
    -b 256K \
    -mem 10G \
    -xattrs \
    -noappend \
    -not-reproducible \
    -progress \
    -one-file-system-x \
    -p "/dev d 755 0 0" \
    -p "/proc d 555 0 0" \
    -p "/sys d 555 0 0" \
    -noI -noX \
    -wildcards \
    -e \
      usr/src \
      var/cache/binpkgs \
      var/cache/distfiles \
      "gentoo*squashfs*" \
      "gentoo*ext4" \
      "usr/lib64/libQt*.a" \
      usr/share/genkernel/distfiles \
      usr/src/linux \
      usr/share/sgml \
      var/cache/eix/previous.eix \
      boot \
      persistent \
      home/*/.cache \
      tmp/fw_original \
      tmp/fw_nv_root \
      var/log/journal \
      var/cache/genkernel \
      var/tmp \
      initramfs-with-squashfs.img \
      lost+found \
  && rm -rf /usr/lib/firmware/* \
  && cp -a /tmp/fw_original/. /usr/lib/firmware/ \
  && rm -rf /tmp/fw_original /tmp/fw_nv_root))))
     
     ,@(when (member *target-machine* '(:both :thinkpad))
         `((run #r(set -e \
  && echo "Preparing ThinkPad E14 squashfs (remove NVIDIA)" \
  && mkdir -p /tmp/tmpfw/amdgpu /tmp/tmpfw/mediatek /tmp/tmpfw/amd /tmp/tmpfw/rtl_bt /tmp/tmpfw/rtl_nic || true \
  && cp -a /usr/lib/firmware/regulatory.db* /tmp/tmpfw/ 2>/dev/null || true \
  && cp -a /usr/lib/firmware/mediatek /tmp/tmpfw/ 2>/dev/null || true \
  && cp -a /usr/lib/firmware/amdgpu/yellow_carp* /tmp/tmpfw/amdgpu/ 2>/dev/null || true \
  && cp -a /usr/lib/firmware/amdgpu/rembrandt* /tmp/tmpfw/amdgpu/ 2>/dev/null || true \
  && cp -a /usr/lib/firmware/amd /tmp/tmpfw/ 2>/dev/null || true \
  && cp -a /usr/lib/firmware/rtl_nic /tmp/tmpfw/ 2>/dev/null || true \
  && cp -a /usr/lib/firmware/rtl_bt /tmp/tmpfw/ 2>/dev/null || true \
  && rm -rf /usr/lib/firmware/* \
  && mv /tmp/tmpfw/* /usr/lib/firmware/ 2>/dev/null || true \
  && echo "Stripping NVIDIA/CUDA userspace for E14 squashfs" \
  && rm -rf /opt/cuda /usr/lib64/lib{cuda,nvidia,nv}* /usr/lib64/libnv* 2>/dev/null || true \
  && rm -rf /usr/bin/nvidia* \
       /usr/lib/elogind/system-sleep/nvidia \
       /usr/lib/systemd/system/nvidia-* \
       /usr/lib/systemd/system-sleep/nvidia \
       /usr/lib/dracut/dracut.conf.d/10-nvidia-drivers.conf \
       /usr/share/applications/nvidia-settings.desktop \
       /usr/share/pixmaps/nvidia-settings.png \
       /usr/share/doc/nvidia-drivers-* \
       /usr/share/nvidia \
       /usr/lib64/nvidia \
       /usr/lib64/gbm/nvidia-drm_gbm.so \
       /usr/lib64/vdpau/libvdpau_nvidia.so* 2>/dev/null || true \
  && rm -rf /nvidia${KVER_RELEASE} 2>/dev/null || true \
  && mksquashfs / /gentoo.squashfs_e14 \
    -comp zstd \
    -Xcompression-level 19 \
    -b 256K \
    -mem 10G \
    -xattrs \
    -noappend \
    -not-reproducible \
    -progress \
    -one-file-system-x \
    -p "/dev d 755 0 0" \
    -p "/proc d 555 0 0" \
    -p "/sys d 555 0 0" \
    -noI -noX \
    -wildcards \
    -e \
      usr/src \
      var/cache/binpkgs \
      var/cache/distfiles \
      "gentoo*squashfs*" \
      "gentoo*ext4" \
      "usr/lib64/libQt*.a" \
      usr/share/genkernel/distfiles \
      usr/src/linux \
      usr/share/sgml \
      var/cache/eix/previous.eix \
      boot \
      persistent \
      home/*/.cache \
      var/log/journal \
      var/cache/genkernel \
      var/tmp \
      initramfs-with-squashfs.img \
      lost+found \
    || true))))))

;; --- Intermediate stage to export the cache volume content ---
(defparameter *exporter-code*
  `(toplevel
     (from "base" :as builder)
     (from "scratch" :as cache-exporter)
     ;; Mount the caches and copy them to the exporter root directory
     (run :mount "type=cache,target=/var/cache/distfiles-cache \
--mount=type=cache,target=/var/cache/binpkgs-cache"
          (and "mkdir -p /distfiles-export /binpkgs-export"
               "cp -rn /var/cache/distfiles-cache/. /distfiles-export/ 2>/dev/null || true"
               "cp -rn /var/cache/binpkgs-cache/. /binpkgs-export/ 2>/dev/null || true"))))

;; --- Final stage Scratch Exporter ---
(defparameter *final-exporter-code*
  `(toplevel
     (from "scratch")
     ;; Copy build products from builder stage
     ,@(when (member *target-machine* '(:both :workstation))
         `((copy "/gentoo.squashfs_nv" "/" :from builder)))
     ,@(when (member *target-machine* '(:both :thinkpad))
         `((copy "/gentoo.squashfs_e14" "/" :from builder)))
     (copy "/boot/vmlinuz" "/" :from builder)
     (copy "/boot/initramfs_squash_sda1-x86_64.img" "/" :from builder)
     (copy "/packages.txt" "/" :from builder)
     (copy "/packages.tsv" "/" :from builder)
     (copy "/packages_obsolete.txt" "/" :from builder)
     ;; Copy Cache outputs from exporter stage
     (copy "/distfiles" "/distfiles" :from cache-exporter)
     (copy "/binpkgs" "/binpkgs" :from cache-exporter)))

(let ((current-dir (make-pathname :directory (pathname-directory *load-pathname*))))
  ;; We compile both codeblocks sequentially into a single Dockerfile
  (let ((full-code `(toplevel ,*gentoo-code* ,*exporter-code* ,*final-exporter-code*)))
    (write-df (merge-pathnames "Dockerfile" current-dir) full-code t)
    (format t "Generated Dockerfile in ~a successfully.~%" current-dir)))
