(eval-when (:compile-toplevel :execute :load-toplevel)
  (let ((current-dir (make-pathname :directory (pathname-directory *load-pathname*))))
    (push (merge-pathnames "../../" current-dir) asdf:*central-registry*))
  (ql:quickload '(:cl-dockerfile-generator :cl-json)))

(in-package :cl-dockerfile-generator)

;; --- Configuration parameters (edit as needed) ---
(defparameter *target-machine* :thinkpad
  "Target hardware. Choices: :both, :workstation, :thinkpad")

(defparameter *split-world-build* t
  "If T, split the @world compilation into 10 cached Docker layers.")

(defparameter *portage-date* :auto
  "Portage snapshot date (YYYYMMDD) or :auto for the newest available AMD64 snapshot.")

(defparameter *stage3-date* :auto ;; "20260629"
  "Stage3 snapshot date (YYYYMMDD) or :auto for the newest AMD64 OpenRC nomultilib image.")

(defparameter *snapshot-platform* "amd64"
  "Docker architecture required for automatically selected Gentoo snapshots.")

(defparameter *auto-stage3-date-cache* nil
  "Cached stage3 date selected from the Docker Hub tag API for this generator run.")

(defparameter *auto-portage-date-cache* nil
  "Cached portage date selected from the Docker Hub tag API for this generator run.")

(defparameter *minimal-image* t
  "If T, build a minimal image (xorg, xterm, dwm only). Package categories default to NIL.")

(defparameter *enable-flaggie-cleanup* nil
  "If T, run flaggie cleanup to remove redundant USE flags.")

;; --- Optional feature flags: each entry is (symbol . default-value) ---
(defparameter *feature-flags*
  '((*enable-emacs-sbcl*        . t)
    (*enable-rust*               . nil)
    (*enable-go*                 . nil)
    (*enable-uv-ruff*            . t)
    (*enable-nvidia*             . nil)
    (*enable-nvidia-cuda*        . nil)
    (*enable-wireshark*          . nil)
    (*enable-lua*                . nil)
    (*enable-firefox*            . t)
    (*enable-google-chrome*      . nil)
    (*enable-llvm*               . nil)
    (*enable-clion*              . t)
    (*enable-docker*             . nil)
    (*enable-slstatus*           . t)
    (*enable-dev-tools*          . t)
    (*enable-media-playback*     . nil)
    (*enable-network-admin*      . nil)
    (*enable-remote-access*      . t)
    (*enable-cli-productivity*   . t)
    (*enable-sys-monitoring-hw*  . nil)
    (*enable-power-management*   . nil)
    (*enable-desktop-extras*     . nil)
    (*enable-signal*             . t)
    (*enable-pdf-viewer*         . t)
    (*enable-ios-sync*           . t)
    (*enable-alacritty*          . t)
    (*enable-dracut-ssh*         . nil)))

;; These values are initialized from *feature-flags* below.  Declare them
;; special before compiling the generator functions that reference them.
(declaim (special *enable-emacs-sbcl* *enable-rust* *enable-go*
                  *enable-uv-ruff* *enable-nvidia* *enable-nvidia-cuda*
                  *enable-wireshark* *enable-lua* *enable-firefox*
                  *enable-google-chrome* *enable-llvm* *enable-clion*
                  *enable-docker* *enable-slstatus* *enable-dev-tools*
                  *enable-media-playback* *enable-network-admin*
                  *enable-remote-access* *enable-cli-productivity*
                  *enable-sys-monitoring-hw* *enable-power-management*
                  *enable-desktop-extras* *enable-signal* *enable-pdf-viewer*
                  *enable-ios-sync* *enable-alacritty* *enable-dracut-ssh*
                  *user-pipewire-initd* *user-pipewire-pulse-initd*
                  *user-wireplumber-initd* *reverse-ssh-eu-initd*
                  *reverse-ssh-us-initd*))

;; Instantiate all feature flags from the table above
(dolist (entry *feature-flags*)
  (set (car entry) (cdr entry)))

(defparameter *audio-system* :alsa
  "Audio system. Choices: :pipewire, :alsa, :none")

(defparameter *kver* "6.18.36")

;; --- Snapshot resolution ---
(defun json-value (key object)
  (cdr (assoc key object)))

(defun docker-hub-tags (repository query)
  (let* ((url (format nil "https://hub.docker.com/v2/repositories/~a/tags?page_size=100~a"
                      repository query))
         (json (handler-case
                   (uiop:run-program (list "curl" "--fail" "--silent" "--show-error"
                                           "--location" url)
                                     :output :string)
                 (error (condition)
                   (error "Unable to query Docker Hub tags for ~a: ~a" repository condition)))))
    (json-value :results (cl-json:decode-json-from-string json))))

(defun tag-supports-platform-p (tag platform)
  (some (lambda (image)
          (and (string= "linux" (json-value :os image))
               (string= platform (json-value :architecture image))))
        (json-value :images tag)))

(defun tag-date (tag-name prefix)
  (let ((prefix-length (length prefix)))
    (when (and (<= prefix-length (length tag-name))
               (string= prefix tag-name :end2 prefix-length))
      (let ((date (subseq tag-name prefix-length)))
        (when (and (= 8 (length date)) (every #'digit-char-p date))
          date)))))

(defun available-snapshot-dates ()
  (let* ((stage-prefix (format nil "~a-nomultilib-openrc-" *snapshot-platform*))
         (stage-tags (docker-hub-tags "gentoo/stage3" (format nil "&name=~a" stage-prefix)))
         (portage-tags (docker-hub-tags "gentoo/portage" ""))
         (stage-dates (remove nil
                              (mapcar (lambda (tag)
                                        (when (tag-supports-platform-p tag *snapshot-platform*)
                                          (tag-date (json-value :name tag) stage-prefix)))
                                      stage-tags)))
         (portage-dates (remove nil
                                (mapcar (lambda (tag)
                                          (when (tag-supports-platform-p tag *snapshot-platform*)
                                            (tag-date (json-value :name tag) "")))
                                        portage-tags)))
         (sorted-stage-dates (sort stage-dates #'string>))
         (sorted-portage-dates (sort portage-dates #'string>)))
    (unless sorted-stage-dates
      (error "Docker Hub returned no compatible ~a OpenRC nomultilib stage3 snapshot"
             *snapshot-platform*))
    (unless sorted-portage-dates
      (error "Docker Hub returned no compatible ~a portage snapshot" *snapshot-platform*))
    (values sorted-stage-dates sorted-portage-dates)))

(defun resolve-auto-snapshot-dates ()
  (unless (and *auto-stage3-date-cache* *auto-portage-date-cache*)
    (multiple-value-bind (stage-dates portage-dates) (available-snapshot-dates)
      (setf *auto-stage3-date-cache* (first stage-dates)
            *auto-portage-date-cache* (first portage-dates))
      (format t "Available Gentoo ~a OpenRC nomultilib stage3 snapshots: ~{~a~^, ~}~%"
              *snapshot-platform* stage-dates)
      (format t "Available Gentoo ~a portage snapshots: ~{~a~^, ~}~%"
              *snapshot-platform* portage-dates)
      (format t "Selected stage3 snapshot: ~a; selected portage snapshot: ~a~%"
              *auto-stage3-date-cache* *auto-portage-date-cache*)))
  (values *auto-stage3-date-cache* *auto-portage-date-cache*))

(defun get-portage-date ()
  (if (eq *portage-date* :auto)
      (nth-value 1 (resolve-auto-snapshot-dates))
      *portage-date*))

(defun get-stage3-date ()
  (if (eq *stage3-date* :auto)
      (nth-value 0 (resolve-auto-snapshot-dates))
      *stage3-date*))

;; --- Dynamic Configuration File Generators ---

;; Base world packages always present in a minimal image
(defparameter *world-base-packages*
  '("app-admin/sudo"
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
    "net-misc/autossh"))

;; Additional packages included in a non-minimal (full) image
(defparameter *world-full-extra-packages*
  '("app-containers/docker"
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
    "x11-terms/alacritty"))

;; Conditional package sets: (flag pkg ...) -- appended when flag is non-nil.
;; Machine-restricted packages (nvidia, cuda) are handled separately below.
(defparameter *conditional-package-sets*
  '((*enable-docker*           "app-containers/docker" "app-containers/docker-buildx" "app-containers/docker-cli")
    (*enable-dev-tools*        "dev-build/ninja" "dev-debug/strace" "dev-debug/ltrace" "sys-devel/mold")
    (*enable-media-playback*   "media-video/mpv" "media-gfx/feh" "media-gfx/scrot" "media-sound/pulsemixer")
    (*enable-network-admin*    "net-analyzer/hping" "net-analyzer/iftop" "net-analyzer/iptraf-ng"
                               "net-analyzer/macchanger" "net-analyzer/netcat" "net-analyzer/nethogs"
                               "net-analyzer/ngrep" "net-analyzer/ssmping"
                               "net-dns/bind-tools" "net-dns/dnsmasq")
    (*enable-remote-access*    "net-misc/autossh" "net-misc/mosh" "net-misc/freerdp"
                               "net-vpn/tailscale" "net-misc/bridge-utils")
    (*enable-cli-productivity* "app-misc/jq" "app-misc/mc" "app-misc/tmate" "app-misc/tmux"
                               "app-shells/zsh" "app-shells/bash-completion" "app-text/tree")
    (*enable-sys-monitoring-hw* "sys-apps/cpuid" "sys-apps/dmidecode" "sys-apps/ethtool"
                                "sys-apps/lm-sensors" "sys-apps/lshw" "sys-apps/nvme-cli"
                                "sys-apps/pciutils" "sys-apps/usbutils"
                                "sys-process/btop" "sys-process/iotop" "sys-process/lsof" "sys-process/psmisc")
    (*enable-power-management* "sys-power/acpi" "sys-power/tlp")
    (*enable-desktop-extras*   "media-fonts/wqy-zenhei" "x11-misc/redshift" "x11-misc/xclip" "x11-misc/xtrlock")
    (*enable-signal*           "net-im/signal-desktop-bin")
    (*enable-pdf-viewer*       "app-text/mupdf")
    (*enable-ios-sync*         "app-pda/ifuse")
    (*enable-alacritty*        "x11-terms/alacritty")
    (*enable-dracut-ssh*       "sys-kernel/dracut-crypt-ssh")
    (*enable-emacs-sbcl*       "app-editors/emacs" "dev-lisp/sbcl")
    (*enable-rust*             "dev-lang/rust-bin" "virtual/rust" "dev-util/cargo-c")
    (*enable-go*               "dev-lang/go" "dev-lang/go-bootstrap")
    (*enable-uv-ruff*          "dev-python/uv" "dev-util/ruff")
    (*enable-wireshark*        "net-analyzer/wireshark")
    (*enable-lua*              "dev-lang/lua")
    (*enable-firefox*          "www-client/firefox-bin")
    (*enable-google-chrome*    "www-client/google-chrome")
    (*enable-llvm*             "llvm-core/llvm" "llvm-core/clang" "dev-util/clang-format")
    (*enable-clion*            "dev-util/clion")))

(defun generate-world-packages ()
  (let ((pkgs (copy-list *world-base-packages*)))
    (unless *minimal-image*
      (setf pkgs (append pkgs *world-full-extra-packages*)))
    ;; Append each conditional set whose flag is set
    (dolist (entry *conditional-package-sets*)
      (when (symbol-value (car entry))
        (setf pkgs (append pkgs (cdr entry)))))
    ;; Machine-restricted packages
    (when (and *enable-nvidia* (member *target-machine* '(:both :workstation)))
      (setf pkgs (append pkgs '("x11-drivers/nvidia-drivers"))))
    (when (and *enable-nvidia-cuda* (member *target-machine* '(:both :workstation)))
      (setf pkgs (append pkgs '("dev-util/nvidia-cuda-toolkit"))))
    ;; Audio system packages
    (case *audio-system*
      (:pipewire (setf pkgs (append pkgs '("media-video/pipewire" "media-video/wireplumber" "media-sound/pulsemixer"))))
      (:alsa     (setf pkgs (append pkgs '("media-libs/alsa-lib" "media-sound/alsa-utils" "media-plugins/alsa-plugins")))))
    (remove-duplicates pkgs :test #'string=)))

(defun generate-make-conf ()
  (let ((video-cards (case *target-machine*
                       (:thinkpad    "amdgpu radeonsi")
                       (:workstation "nvidia")
                       (t            "nvidia amdgpu radeonsi")))
        (llvm-targets (case *target-machine*
                        (:thinkpad    "X86 AMDGPU")
                        (:workstation "X86 NVPTX")
                        (t            "X86 NVPTX AMDGPU")))
        (use-flags (case *audio-system*
                     (:pipewire "-vaapi -doc -cups -opencl -jemalloc -wayland pipewire dbus elogind policykit udev")
                     (:alsa     "-vaapi -doc -cups -opencl -jemalloc -wayland -pipewire alsa dbus elogind policykit udev")
                     (t         "-vaapi -doc -cups -opencl -jemalloc -wayland -pipewire -alsa dbus elogind policykit udev"))))
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
       (push "media-plugins/alsa-plugins pulseaudio" lines)))
    (format nil "~{~a~^~%~}~%" (nreverse lines))))

(defun generate-package-accept-keywords ()
  (let (lines)
    (when (or *enable-remote-access* (not *minimal-image*))
      (push ">=net-misc/freerdp-3.17.2-r1 ~amd64" lines))
    (when *enable-dracut-ssh*
      (push "sys-kernel/dracut-crypt-ssh ~amd64" lines))
    (push "sys-kernel/gentoo-sources ~amd64" lines)
    (when (or *enable-uv-ruff* (not *minimal-image*))
      (push "dev-util/ruff ~amd64" lines))
    (when (or *enable-clion* (not *minimal-image*))
      (push "dev-util/clion ~amd64" lines))
    (when (and *enable-nvidia* (member *target-machine* '(:both :workstation)))
      (push "x11-drivers/nvidia-drivers ~amd64" lines))
    (when (and *enable-nvidia-cuda* (member *target-machine* '(:both :workstation)))
      (push "dev-util/nvidia-cuda-toolkit ~amd64" lines))
    (format nil "~{~a~^~%~}~%" (nreverse lines))))

;; Package -> build environment mappings as a flat data table
(defparameter *package-env-table*
  '(("llvm-core/llvm"        . "low-mem")
    ("sys-devel/gcc"         . "low-mem")
    ("dev-lang/rust"         . "low-mem")
    ("www-client/google-chrome" . "low-mem")
    ("www-client/chromium"   . "low-mem")
    ("www-client/firefox"    . "low-mem")
    ("dev-vcs/git"           . "lto-gcc")
    ("app-editors/emacs"     . "lto-gcc")
    ("media-video/ffmpeg"    . "lto-gcc")
    ("media-video/mpv"       . "lto-gcc")
    ("net-misc/freerdp"      . "lto-gcc")))

(defun generate-package-env ()
  (format nil "~{~a~^~%~}~%"
          (mapcar (lambda (e) (format nil "~a ~a" (car e) (cdr e)))
                  *package-env-table*)))

;; --- Helper: emerge RUN with dual host+cache mounts ---
(defun run-emerge (command)
  (let ((mounts-str "type=bind,source=./distfiles,target=/var/cache/distfiles-host,ro \\
--mount=type=bind,source=./binpkgs,target=/var/cache/binpkgs-host,ro \\
--mount=type=cache,target=/var/cache/distfiles-cache \\
--mount=type=cache,target=/var/cache/binpkgs-cache"))
    `(run :mount ,mounts-str
          (and "mkdir -p /var/cache/distfiles /var/cache/binpkgs /var/cache/binhost"
               "cp -rn /var/cache/distfiles-host/. /var/cache/distfiles/ 2>/dev/null || true"
               "cp -rn /var/cache/distfiles-cache/. /var/cache/distfiles/ 2>/dev/null || true"
               "cp -rn /var/cache/binpkgs-host/. /var/cache/binpkgs/ 2>/dev/null || true"
               "cp -rn /var/cache/binpkgs-host/. /var/cache/binhost/ 2>/dev/null || true"
               "cp -rn /var/cache/binpkgs-cache/. /var/cache/binpkgs/ 2>/dev/null || true"
               "cp -rn /var/cache/binpkgs-cache/. /var/cache/binhost/ 2>/dev/null || true"
               ,(format nil "STATUS=0; ~a || STATUS=$?" command)
               "cp -rn /var/cache/distfiles/. /var/cache/distfiles-cache/ 2>/dev/null || true"
               "cp -rn /var/cache/binpkgs/. /var/cache/binpkgs-cache/ 2>/dev/null || true"
               "cp -rn /var/cache/binhost/. /var/cache/binpkgs-cache/ 2>/dev/null || true"
               "[ $STATUS -eq 0 ]"))))

;; --- Inline service & configuration file strings ---
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

;; PipeWire-family OpenRC initd: (var description command depends)
;; Each entry generates one initd script string via format.
(defparameter *pipewire-initd-specs*
  '((*user-pipewire-initd*
     "PipeWire media server" "/usr/bin/pipewire" "dbus")
    (*user-pipewire-pulse-initd*
     "PipeWire PulseAudio compatibility server" "/usr/bin/pipewire-pulse" "pipewire dbus")
    (*user-wireplumber-initd*
     "WirePlumber session manager" "/usr/bin/wireplumber" "pipewire dbus")))

(dolist (spec *pipewire-initd-specs*)
  (destructuring-bind (var description command depends) spec
    (set var (format nil "#!/sbin/openrc-run
description=~s
command=~s
command_background=\"yes\"
pidfile=\"${XDG_RUNTIME_DIR}/~a.pid\"
depend() {
  need ~a
}
" description command (pathname-name (pathname command)) depends))))

;; Autossh reverse-SSH tunnel initd: (var name remote-host port)
(defparameter *reverse-ssh-specs*
  '((*reverse-ssh-eu-initd* "reverse-ssh-eu" "tinyeu" 2332)
    (*reverse-ssh-us-initd* "reverse-ssh-us" "tinyus" 2332)))

(dolist (spec *reverse-ssh-specs*)
  (destructuring-bind (var name host port) spec
    (set var (format nil "#!/sbin/openrc-run
name=~s
description=\"Reverse SSH tunnel to ~a\"
supervisor=\"supervise-daemon\"
command=\"/usr/bin/autossh\"
command_args=\"-M 0 -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -R ~d:localhost:22 ~a\"
command_user=\"kiel\"
supervise_daemon_args=\"-e HOME=/home/kiel\"
depend() {
    use net
    after iwd
    want tailscale
}
" name host port host))))

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

;; --- Helper: mksquashfs RUN command builder ---
;; extra-setup  - list of shell commands run before mksquashfs
;; extra-excludes - list of additional paths to exclude (appended to common set)
(defun make-squashfs-run (output-image echo-msg extra-setup extra-excludes)
  (let* ((common-excludes
          '("usr/src"
            "var/cache/binpkgs"
            "var/cache/distfiles"
            "var/cache/binhost"
            "\"gentoo*squashfs*\""
            "\"gentoo*ext4\""
            "\"usr/lib64/libQt*.a\""
            "usr/share/genkernel/distfiles"
            "usr/src/linux"
            "usr/share/sgml"
            "var/cache/eix/previous.eix"
            "boot"
            "persistent"
            "home/*/.cache"
            "var/log/journal"
            "var/cache/genkernel"
            "var/tmp"
            "initramfs-with-squashfs.img"
            "lost+found"))
         (all-excludes (append common-excludes extra-excludes))
         (setup-str (if extra-setup
                        (format nil " \\~{~%  && ~a \\~}" extra-setup)
                        " \\"))
         (exclude-str (format nil "~{~%       ~a~^ \\~}" all-excludes)))
    `(run ,(format nil "set -e \\
  && echo ~s~a
  && mksquashfs / ~a \\
    -comp zstd \\
    -Xcompression-level 19 \\
    -b 256K \\
    -mem 10G \\
    -xattrs \\
    -noappend \\
    -not-reproducible \\
    -progress \\
    -one-file-system-x \\
    -p \"/dev d 755 0 0\" \\
    -p \"/proc d 555 0 0\" \\
    -p \"/sys d 555 0 0\" \\
    -noI -noX \\
    -wildcards \\
    -e \\~a"
                   echo-msg setup-str output-image exclude-str))))

;; --- Main Dockerfile Meta-Generator ---
(defparameter *gentoo-code*
  `(toplevel
     (directive syntax "docker/dockerfile:1")
     (comment "Base images")
     (from ,(format nil "gentoo/portage:~a" (get-portage-date)) :as portage)
     (comment "Stage3 base (1GB)")
     (comment "https://hub.docker.com/r/gentoo/stage3/tags")
     (from ,(format nil "gentoo/stage3:~a-nomultilib-openrc-~a"
                    *snapshot-platform* (get-stage3-date)) :as base)
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
     (env CHECKREQS_DONOTHING "1")
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
           `((run (and "emerge -pqe --columns @world | awk '{for(i=1;i<=NF;i++) if($i ~ /\\//) {print $i; break}}' > /tmp/world_packages.txt"
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
     
     ,@(when *enable-slstatus*
         `((comment "slstatus (requires git)")
           (workdir "/usr/src")
           (run "git clone https://git.suckless.org/slstatus")
           (workdir "/usr/src/slstatus")
           (copy "config/slstatus_config.h" ".config")
           (run "make -j32")
           (run "make install")
           (run "make clean")))
     
     (run (and "groupadd -f input"
               "useradd -m -G users,wheel,audio,video,input -s /bin/bash kiel"
               #r#for grp in libvirt kvm qemu; do if getent group "${grp}" >/dev/null; then usermod -aG "${grp}" kiel; fi; done#))
     
     (copy :heredoc "/home/kiel/.xinitrc" ,*xinitrc*)
     
     ;; Home config files: data-driven loop
     ,@(loop for (src dst) in '(("config/activate"          "/home/kiel/activate")
                                 ("config/start2"            "/home/kiel/start2")
                                 ("config/start-pipewire.sh" "/home/kiel/start-pipewire.sh"))
             collect `(copy ,src ,dst))
     
     (run (and "chmod +x /home/kiel/activate /home/kiel/start2 /home/kiel/start-pipewire.sh"
               "chown kiel:kiel /home/kiel/activate /home/kiel/start2 /home/kiel/start-pipewire.sh"))
     
     ;; OpenRC init.d files: data-driven loop (dest-path . content-variable)
     ,@(loop for (dest . content) in `(("/etc/init.d/user-runtime"                 . ,*user-runtime-initd*)
                                        ("/etc/profile.d/zz-openrc-user-session.sh" . ,*user-session-sh*)
                                        ("/etc/user/init.d/dbus"                    . ,*user-dbus-initd*)
                                        ("/etc/user/init.d/pipewire"                . ,*user-pipewire-initd*)
                                        ("/etc/user/init.d/pipewire-pulse"          . ,*user-pipewire-pulse-initd*)
                                        ("/etc/user/init.d/wireplumber"             . ,*user-wireplumber-initd*)
                                        ("/etc/resolv.conf"                         . ,*resolv-conf*)
                                        ("/etc/init.d/reverse-ssh-eu"               . ,*reverse-ssh-eu-initd*)
                                        ("/etc/init.d/reverse-ssh-us"               . ,*reverse-ssh-us-initd*))
             collect `(copy :heredoc ,dest ,content))
     
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
     
     ;; Host-config file copies: data-driven loops
     ,@(loop for (src dst) in '(("config/activate" "/usr/local/share/openrc-host-config/activate")
                                 ("config/start2"   "/usr/local/share/openrc-host-config/start2"))
             collect `(copy ,src ,dst))
     ,@(loop for (dest . content) in `(("/usr/local/share/openrc-host-config/reverse-ssh-eu.initd" . ,*reverse-ssh-eu-initd*)
                                        ("/usr/local/share/openrc-host-config/reverse-ssh-us.initd" . ,*reverse-ssh-us-initd*))
             collect `(copy :heredoc ,dest ,content))
     
     (run "fc-cache -fv")
     (copy :heredoc "/etc/conf.d/modules" "modules=\"amdgpu mt7921e\"")
     (copy :heredoc "/etc/conf.d/keymaps" "keymap=\"colemak\"")
     (run :heredoc #r(set -e
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
     
     ;; Squashfs images for each target machine
     ,@(when (member *target-machine* '(:both :workstation))
         `(,(make-squashfs-run
             "/gentoo.squashfs_nv"
             "Preparing NVIDIA squashfs"
             '("test -e /lib/modules/${KVER_RELEASE}/video/nvidia.ko"
               "rm -rf /tmp/fw_original /tmp/fw_nv_root"
               "mkdir -p /tmp/fw_original /tmp/fw_nv_root/usr/lib/firmware"
               "cp -a /usr/lib/firmware/. /tmp/fw_original/"
               #r(modinfo -F firmware /lib/modules/${KVER_RELEASE}/video/nvidia.ko \
        | sort -u \
        | while IFS= read -r rel; do \
            test -n "${rel}"; \
            src="/usr/lib/firmware/${rel}"; \
            dst="/tmp/fw_nv_root/usr/lib/firmware/${rel}"; \
            test -e "${src}"; \
            mkdir -p "$(dirname "${dst}")"; \
            cp -a "${src}" "${dst}"; \
            done)
               "rm -rf /usr/lib/firmware/*"
               "cp -a /tmp/fw_nv_root/usr/lib/firmware/. /usr/lib/firmware/")
             '("tmp/fw_original" "tmp/fw_nv_root"))))

     ,@(when (member *target-machine* '(:both :thinkpad))
         `(,(make-squashfs-run
             "/gentoo.squashfs_e14"
             "Preparing ThinkPad E14 squashfs (remove NVIDIA)"
             '("mkdir -p /tmp/tmpfw/amdgpu /tmp/tmpfw/mediatek /tmp/tmpfw/amd /tmp/tmpfw/rtl_bt /tmp/tmpfw/rtl_nic || true"
               "cp -a /usr/lib/firmware/regulatory.db* /tmp/tmpfw/ 2>/dev/null || true"
               "cp -a /usr/lib/firmware/mediatek /tmp/tmpfw/ 2>/dev/null || true"
               "cp -a /usr/lib/firmware/amdgpu/yellow_carp* /tmp/tmpfw/amdgpu/ 2>/dev/null || true"
               "cp -a /usr/lib/firmware/amdgpu/rembrandt* /tmp/tmpfw/amdgpu/ 2>/dev/null || true"
               "cp -a /usr/lib/firmware/amd /tmp/tmpfw/ 2>/dev/null || true"
               "cp -a /usr/lib/firmware/rtl_nic /tmp/tmpfw/ 2>/dev/null || true"
               "cp -a /usr/lib/firmware/rtl_bt /tmp/tmpfw/ 2>/dev/null || true"
               "rm -rf /usr/lib/firmware/*"
               "mv /tmp/tmpfw/* /usr/lib/firmware/ 2>/dev/null || true"
               "echo \"Stripping NVIDIA/CUDA userspace for E14 squashfs\""
               "rm -rf /opt/cuda /usr/lib64/lib{cuda,nvidia,nv}* /usr/lib64/libnv* 2>/dev/null || true"
               #r(rm -rf /usr/bin/nvidia* \
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
        /usr/lib64/vdpau/libvdpau_nvidia.so* 2>/dev/null || true)
               "rm -rf /nvidia${KVER_RELEASE} 2>/dev/null || true")
             '())))))

;; --- Intermediate stage to export the cache volume content ---
(defparameter *exporter-code*
  `(toplevel
     (from "base" :as builder)
     (from "base" :as cache-exporter)
     ;; Mount the caches and copy them to the exporter root directory
     (run :mount "type=cache,target=/var/cache/distfiles-cache \\
--mount=type=cache,target=/var/cache/binpkgs-cache"
          (and "mkdir -p /distfiles /binpkgs"
               "cp -rn /var/cache/distfiles-cache/. /distfiles/ 2>/dev/null || true"
               "cp -rn /var/cache/binpkgs-cache/. /binpkgs/ 2>/dev/null || true"))))

;; --- Final stage Scratch Exporter ---
(defparameter *final-exporter-code*
  `(toplevel
     (from "scratch")
     ;; Copy squashfs images based on target machine
     ,@(when (member *target-machine* '(:both :workstation))
         `((copy "/gentoo.squashfs_nv" "/" :from builder)))
     ,@(when (member *target-machine* '(:both :thinkpad))
         `((copy "/gentoo.squashfs_e14" "/" :from builder)))
     ;; Fixed build artifacts
     ,@(loop for f in '("/boot/vmlinuz"
                        "/boot/initramfs_squash_sda1-x86_64.img"
                        "/packages.txt"
                        "/packages.tsv"
                        "/packages_obsolete.txt")
             collect `(copy ,f "/" :from builder))
     ;; Cache outputs from exporter stage
     ,@(loop for (src dst) in '(("/distfiles" "/distfiles")
                                 ("/binpkgs"   "/binpkgs"))
             collect `(copy ,src ,dst :from cache-exporter))))

(let ((current-dir (make-pathname :directory (pathname-directory *load-pathname*))))
  ;; Compile all three stages sequentially into a single Dockerfile
  (let ((full-code `(toplevel ,*gentoo-code* ,*exporter-code* ,*final-exporter-code*)))
    (write-df (merge-pathnames "Dockerfile" current-dir) full-code t)
    (format t "Generated Dockerfile in ~a successfully.~%" current-dir)))
