(eval-when (:compile-toplevel :execute :load-toplevel)
  (let ((current-dir (make-pathname :directory (pathname-directory *load-pathname*))))
    (push (merge-pathnames "../../" current-dir) asdf:*central-registry*))
  (ql:quickload :cl-dockerfile-generator))

(in-package :cl-dockerfile-generator)

;; Helper function to compile copy operations for config files
(defun copy-config-files (files dest-dir)
  (loop for file in files
        collect `(copy ,(format nil "config/~a" file) ,(format nil "~a/~a" dest-dir file))))

;; Helper function for copying service configuration files
(defun copy-services (services)
  (loop for (src dest) in services
        collect `(copy ,(format nil "config/~a" src) ,dest)))

(defparameter *kver* "6.18.36")

(let ((gentoo-code
        `(toplevel
           (directive syntax "docker/dockerfile:1")
           (comment "Base images")
           (from "gentoo/portage:20260624" :as portage)
           (comment "Stage3 base (1GB)")
           (comment "https://hub.docker.com/r/gentoo/stage3/tags")
           (from "gentoo/stage3:nomultilib-20260622" :as base)
           (comment "https://hub.docker.com/r/gentoo/portage/tags")
           (comment "Copy full Portage tree (570MB)")
           (copy "/var/db/repos/gentoo" "/var/db/repos/gentoo" :from portage)
           
           (comment "Portage configuration")
           (run "eselect profile set default/linux/amd64/23.0/no-multilib")
           (copy "config/package.accept_keywords" "/etc/portage/package.accept_keywords/package.accept_keywords")
           
           (comment "Repository tooling and package configuration")
           ,@(copy-config-files '("make.conf" "package.use" "package.env" "env") "/etc/portage")
           
           (comment "Keep the world set on PipeWire and let PipeWire provide PulseAudio compatibility.")
           (copy "config/world" "/var/lib/portage/world")
           (copy "config/dwm-6.8" "/etc/portage/savedconfig/x11-wm/dwm-6.8")
           
           (env KVER_PURE ,*kver*)
           (env KVER_SOURCE "${KVER_PURE}-gentoo")
           (env KVER_RELEASE "${KVER_SOURCE}-dist")
           (run "df -h")
           
           (comment "Recreate the gentoo-sources-6.18.36 ebuild")
           (run (seq #r(cat <<'EOF' > /var/db/repos/gentoo/sys-kernel/gentoo-sources/gentoo-sources-6.18.36.ebuild
EAPI="8"
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
EOF)))
           (run "ebuild /var/db/repos/gentoo/sys-kernel/gentoo-sources/gentoo-sources-6.18.36.ebuild manifest")
           (run "emerge =sys-kernel/gentoo-sources-${KVER_PURE}")
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
           (run "emerge -1 sys-apps/portage")
           (run #r(sed -i \
    -e '/^net-analyzer\/arping\>/d' \
    -e '/^net-misc\/speedtest-cli\>/d' \
    -e '/^sys-process\/progress\>/d' \
    -e '/^sys-process\/sysstat\>/d' \
    /var/lib/portage/world))
           (run (and "mkdir -p /etc/portage/package.use"
                     "touch /etc/portage/package.use/zz-late-world"
                     "grep -qxF 'app-text/xmlto text' /etc/portage/package.use/zz-late-world || printf '\\napp-text/xmlto text\\n' >> /etc/portage/package.use/zz-late-world"))
           (run "emerge -uDN @world")
           (run "gcc-config -l")
           
           (comment "Temporarily install package analysis tools")
           (run (and "emerge --ask=n app-portage/genlop app-portage/gentoolkit"
                     "qlist -Iv sys-devel/gcc"
                     #r#echo "Generating package statistics..."#
                     #r(for pkg in $(qlist -I); do \
      SIZE=$(qsize -m "$pkg" | awk '{print $5$6}'); \
      TIME=$(genlop -t "$pkg" | grep "merge time" | tail -n 1 | sed 's/.*merge time: //'); \
      echo "$pkg | Size: ${SIZE:-N/A} | Build Time: ${TIME:-N/A}"; \
    done > /packages.txt)
                     "emerge -C app-portage/genlop app-portage/gentoolkit"))
           
           (comment "Sudo policy")
           (run "mkdir -p /etc/sudoers.d")
           (run #r#echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel#)
           
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
           
           (copy "config/xinitrc" "/home/kiel/.xinitrc")
           
           ,@(copy-services '(("activate" "/home/kiel/activate")
                              ("start2" "/home/kiel/start2")
                              ("start-pipewire.sh" "/home/kiel/start-pipewire.sh")))
           
           (run (and "chmod +x /home/kiel/activate /home/kiel/start2 /home/kiel/start-pipewire.sh"
                     "chown kiel:kiel /home/kiel/activate /home/kiel/start2 /home/kiel/start-pipewire.sh"))
           
           ,@(copy-services '(("user-runtime.initd" "/etc/init.d/user-runtime")
                              ("zz-openrc-user-session.sh" "/etc/profile.d/zz-openrc-user-session.sh")
                              ("user-dbus.initd" "/etc/user/init.d/dbus")
                              ("user-pipewire.initd" "/etc/user/init.d/pipewire")
                              ("user-pipewire-pulse.initd" "/etc/user/init.d/pipewire-pulse")
                              ("user-wireplumber.initd" "/etc/user/init.d/wireplumber")
                              ("resolv.conf" "/etc/")
                              ("reverse-ssh-eu.initd" "/etc/init.d/reverse-ssh-eu")
                              ("reverse-ssh-us.initd" "/etc/init.d/reverse-ssh-us")))
           
           (run (and "chmod +x /etc/init.d/reverse-ssh-*"
                     "rc-update add sshd default"
                     "rc-update add reverse-ssh-eu default"
                     "rc-update add reverse-ssh-us default"))
           
           (user kiel)
           (env HOME "/home/kiel")
           
           (comment "Install Emacs packages from MELPA in batch mode")
           (run #r(emacs --batch \
    --eval "(require 'package)" \
    --eval "(add-to-list 'package-archives '(\"melpa\" . \"https://melpa.org/packages/\") t)" \
    --eval "(package-initialize)" \
    --eval "(package-refresh-contents)" \
    --eval "(dolist (pkg '(magit paredit slime)) (package-install pkg))"))
           
           (user root)
           (run "mkdir -p /usr/local/share/openrc-host-config")
           
           ,@(copy-services '(("activate" "/usr/local/share/openrc-host-config/activate")
                              ("start2" "/usr/local/share/openrc-host-config/start2")
                              ("reverse-ssh-eu.initd" "/usr/local/share/openrc-host-config/reverse-ssh-eu.initd")
                              ("reverse-ssh-us.initd" "/usr/local/share/openrc-host-config/reverse-ssh-us.initd")))
           
           (run "fc-cache -fv")
           (run #r(printf '%s\n' \
      'modules="amdgpu mt7921e"' \
      > /etc/conf.d/modules \
 && printf '%s\n' \
      'keymap="colemak"' \
      > /etc/conf.d/keymaps \
 && if grep -q '^rc_logger=' /etc/rc.conf 2>/dev/null; then \
      sed -i 's/^rc_logger=.*/rc_logger="YES"/' /etc/rc.conf; \
    else \
      printf '%s\n' 'rc_logger="YES"' >> /etc/rc.conf; \
    fi \
 && if grep -q '^rc_log_path=' /etc/rc.conf 2>/dev/null; then \
      sed -i 's|^rc_log_path=.*|rc_log_path="/var/log/rc.log"|' /etc/rc.conf; \
    else \
      printf '%s\n' 'rc_log_path="/var/log/rc.log"' >> /etc/rc.conf; \
    fi \
 && if grep -q '^rc_verbose=' /etc/rc.conf 2>/dev/null; then \
      sed -i 's/^rc_verbose=.*/rc_verbose="YES"/' /etc/rc.conf; \
    else \
      printf '%s\n' 'rc_verbose="YES"' >> /etc/rc.conf; \
    fi \
 && if grep -q '^rc_autostart_user=' /etc/rc.conf 2>/dev/null; then \
      sed -i 's/^rc_autostart_user=.*/rc_autostart_user="NO"/' /etc/rc.conf; \
    else \
      printf '%s\n' 'rc_autostart_user="NO"' >> /etc/rc.conf; \
    fi \
 && if ! grep -q '^s0:12345:respawn:/sbin/agetty 115200 ttyS0 vt100$' /etc/inittab; then \
      printf '%s\n' 's0:12345:respawn:/sbin/agetty 115200 ttyS0 vt100' >> /etc/inittab; \
    fi \
 && if ! grep -qx 'ttyS0' /etc/securetty; then \
      printf '%s\n' 'ttyS0' >> /etc/securetty; \
    fi \
 && chmod 0755 /etc/init.d/user-runtime /etc/profile.d/zz-openrc-user-session.sh \
      /etc/user/init.d/dbus /etc/user/init.d/pipewire /etc/user/init.d/pipewire-pulse /etc/user/init.d/wireplumber \
 && install -d -m 0755 /run/user \
 && install -d -o kiel -g kiel -m 0700 /run/user/1000 \
 && test -e /etc/init.d/user \
 && ln -sf /etc/init.d/user /etc/init.d/user.kiel \
 && install -d -o kiel -g kiel -m 0755 /home/kiel/.config/rc/runlevels/default \
 && ln -sf /etc/user/init.d/dbus /home/kiel/.config/rc/runlevels/default/dbus \
 && rc-update add udev sysinit \
 && rc-update add udev-trigger sysinit \
 && rc-update add udev-settle sysinit \
 && rc-update add modules boot \
 && rc-update add keymaps boot \
 && rc-update add user-runtime default \
 && rc-update add user.kiel default \
 && rc-update add dbus default \
 && rc-update add iwd default \
 && chown -R kiel:kiel /home/kiel/.config))
           
           (run "rm -rf /var/tmp/portage/*")
           (run "emerge -C dev-lang/rust-bin virtual/rust dev-lang/go dev-lang/go-bootstrap dev-util/cargo-c || true")
           (workdir "/")
           (run "emerge --ask=n sys-fs/e2fsprogs sys-fs/erofs-utils || true")
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
           
           (run #r(set -e \
 && emerge --ask=n --oneshot app-portage/genlop \
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
           
           (run #r(set -e \
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
 && rm -rf /tmp/fw_original /tmp/fw_nv_root))
           
           (run #r(set -e \
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
    || true)))))

  (let ((current-dir (make-pathname :directory (pathname-directory *load-pathname*))))
    (write-df (merge-pathnames "Dockerfile" current-dir) gentoo-code t)
    (format t "Generated Dockerfile in ~a successfully.~%" current-dir)))
