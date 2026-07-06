# syntax=docker/dockerfile:1
# Base images
FROM gentoo/portage:20260706 AS portage
# Stage3 base (1GB)
# https://hub.docker.com/r/gentoo/stage3/tags
FROM gentoo/stage3:nomultilib-20260629 AS base
# https://hub.docker.com/r/gentoo/portage/tags
# Copy full Portage tree (570MB)
COPY --from=portage /var/db/repos/gentoo /var/db/repos/gentoo
# Portage configuration (Dynamic Heredocs)
RUN eselect profile set default/linux/amd64/23.0/no-multilib
COPY <<'EOF' /etc/portage/package.accept_keywords/package.accept_keywords
>=net-misc/freerdp-3.17.2-r1 ~amd64
sys-kernel/dracut-crypt-ssh ~amd64
sys-kernel/gentoo-sources ~amd64

EOF
COPY <<'EOF' /etc/portage/make.conf
COMMON_FLAGS="-O2 -pipe"
CFLAGS="${COMMON_FLAGS}"
CXXFLAGS="${COMMON_FLAGS}"
FCFLAGS="${COMMON_FLAGS}"
FFLAGS="${COMMON_FLAGS}"

LC_MESSAGES=C.UTF-8

USE="-vaapi -doc -cups -opencl -jemalloc -wayland pipewire dbus elogind policykit udev"
VIDEO_CARDS="amdgpu radeonsi"
LLVM_TARGETS="X86 AMDGPU"

ACCEPT_LICENSE="*"

FEATURES="-ipc-sandbox -network-sandbox -pid-sandbox getbinpkg binpkg-request-signature"

GENTOO_MIRRORS="https://pkg.adfinis-on-exoscale.ch/gentoo/ \
    http://pkg.adfinis-on-exoscale.ch/gentoo/ \
    https://ch.mirrors.cicku.me/gentoo/ \
    http://ch.mirrors.cicku.me/gentoo/ \
    https://mirror.init7.net/gentoo/ \
    http://mirror.init7.net/gentoo/ \
    rsync://mirror.init7.net/gentoo/"

EOF
COPY <<'EOF' /etc/portage/package.use
sys-fs/squashfs-tools xattr -debug -lz4 -lzma -lzo zstd
sys-fs/lvm2 lvm
x11-wm/dwm savedconfig -xinerama
sys-libs/minizip-ng compat
media-libs/libpulse X
media-libs/vulkan-loader X
x11-libs/libdrm video_cards_radeon
media-video/pipewire alsa dbus sound-server udev
media-video/wireplumber dbus
media-plugins/alsa-plugins pulseaudio

EOF
COPY <<'EOF' /etc/portage/package.env
sys-devel/llvm low-mem
sys-devel/gcc low-mem
dev-lang/rust low-mem
www-client/google-chrome low-mem
www-client/chromium low-mem
www-client/firefox low-mem
dev-vcs/git lto-gcc
app-editors/emacs lto-gcc
media-video/ffmpeg lto-gcc
media-video/mpv lto-gcc
net-misc/freerdp lto-gcc

EOF
# Portage env files
RUN mkdir -p /etc/portage/env
COPY <<'EOF' /etc/portage/env/low-mem
MAKEOPTS="-j8"
EOF
COPY <<'EOF' /etc/portage/env/lto-gcc
WARNING_FLAGS="-Werror=odr -Werror=lto-type-mismatch -Werror=strict-aliasing"
LTO_FLAGS="-flto ${WARNING_FLAGS}"
CFLAGS="${CFLAGS} ${LTO_FLAGS}"
CXXFLAGS="${CXXFLAGS} ${LTO_FLAGS}"
FCFLAGS="${FCFLAGS} ${LTO_FLAGS}"
FFLAGS="${FFLAGS} ${LTO_FLAGS}"
LDFLAGS="${LDFLAGS} ${LTO_FLAGS}"

EOF
# Keep the world set on PipeWire and let PipeWire provide PulseAudio compatibility.
COPY <<'EOF' /var/lib/portage/world
app-admin/sudo
app-admin/sysklogd
sys-apps/ripgrep
sys-process/htop
x11-base/xorg-server
x11-terms/xterm
x11-wm/dwm
sys-kernel/gentoo-sources
sys-kernel/linux-firmware
sys-kernel/dracut
sys-fs/e2fsprogs
sys-fs/erofs-utils
sys-fs/squashfs-tools
sys-fs/lvm2
sys-fs/btrfs-progs
sys-fs/cryptsetup
app-portage/cpuid2cpuflags
app-portage/eix
app-portage/gentoolkit
dev-vcs/git
net-wireless/iwd
net-wireless/iw
net-misc/dhcpcd
net-misc/autossh
media-video/pipewire
media-video/wireplumber
media-sound/pulsemixer

EOF
COPY config/dwm-6.8 /etc/portage/savedconfig/x11-wm/dwm-6.8
ENV KVER_PURE=6.18.36
ENV KVER_SOURCE=${KVER_PURE}-gentoo
ENV KVER_RELEASE=${KVER_SOURCE}-dist
RUN df -h
# Recreate the gentoo-sources-6.18.36 ebuild
COPY <<'EOF' /var/db/repos/gentoo/sys-kernel/gentoo-sources/gentoo-sources-6.18.36.ebuild
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

EOF
RUN ebuild /var/db/repos/gentoo/sys-kernel/gentoo-sources/gentoo-sources-6.18.36.ebuild manifest
RUN --mount=type=bind,source=./distfiles,target=/var/cache/distfiles-host,ro \
--mount=type=bind,source=./binpkgs,target=/var/cache/binpkgs-host,ro \
--mount=type=cache,target=/var/cache/distfiles-cache \
--mount=type=cache,target=/var/cache/binpkgs-cache mkdir -p /var/cache/distfiles /var/cache/binpkgs /var/cache/binhost \
 && cp -rn /var/cache/distfiles-host/. /var/cache/distfiles/ 2>/dev/null || true \
 && cp -rn /var/cache/distfiles-cache/. /var/cache/distfiles/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-host/. /var/cache/binpkgs/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-host/. /var/cache/binhost/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-cache/. /var/cache/binpkgs/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-cache/. /var/cache/binhost/ 2>/dev/null || true \
 && emerge =sys-kernel/gentoo-sources-${KVER_PURE} \
 && cp -rn /var/cache/distfiles/. /var/cache/distfiles-cache/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs/. /var/cache/binpkgs-cache/ 2>/dev/null || true \
 && cp -rn /var/cache/binhost/. /var/cache/binpkgs-cache/ 2>/dev/null || true
RUN eselect kernel list
RUN eselect kernel set linux-${KVER_SOURCE}
WORKDIR /usr/src/linux
COPY config/config6.18.18 .config
RUN sed -i \
    -e 's/^CONFIG_LOCALVERSION="-gentoo-dist"/CONFIG_LOCALVERSION="-dist"/' \
    -e 's/^CONFIG_DEBUG_INFO=y/# CONFIG_DEBUG_INFO is not set/' \
    -e 's/^CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT=y/# CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT is not set/' \
    -e 's/^CONFIG_DEBUG_INFO_BTF=y/# CONFIG_DEBUG_INFO_BTF is not set/' \
    -e 's/^CONFIG_DEBUG_INFO_BTF_MODULES=y/# CONFIG_DEBUG_INFO_BTF_MODULES is not set/' \
    .config
RUN make prepare
# compile the kernel
RUN make -j32
RUN make modules_install
RUN depmod -a ${KVER_RELEASE}
RUN make install
# Clean up the locales
RUN printf 'en_US.UTF-8 UTF-8\n' > /etc/locale.gen \
 && locale-gen \
 && env-update \
 && . /etc/profile
ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8
RUN env-update && source /etc/profile
RUN --mount=type=bind,source=./distfiles,target=/var/cache/distfiles-host,ro \
--mount=type=bind,source=./binpkgs,target=/var/cache/binpkgs-host,ro \
--mount=type=cache,target=/var/cache/distfiles-cache \
--mount=type=cache,target=/var/cache/binpkgs-cache mkdir -p /var/cache/distfiles /var/cache/binpkgs /var/cache/binhost \
 && cp -rn /var/cache/distfiles-host/. /var/cache/distfiles/ 2>/dev/null || true \
 && cp -rn /var/cache/distfiles-cache/. /var/cache/distfiles/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-host/. /var/cache/binpkgs/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-host/. /var/cache/binhost/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-cache/. /var/cache/binpkgs/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-cache/. /var/cache/binhost/ 2>/dev/null || true \
 && emerge -1 sys-apps/portage \
 && cp -rn /var/cache/distfiles/. /var/cache/distfiles-cache/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs/. /var/cache/binpkgs-cache/ 2>/dev/null || true \
 && cp -rn /var/cache/binhost/. /var/cache/binpkgs-cache/ 2>/dev/null || true
RUN sed -i \
    -e '/^net-analyzer\/arping\>/d' \
    -e '/^net-misc\/speedtest-cli\>/d' \
    -e '/^sys-process\/progress\>/d' \
    -e '/^sys-process\/sysstat\>/d' \
    /var/lib/portage/world
RUN mkdir -p /etc/portage/package.use \
 && touch /etc/portage/package.use/zz-late-world \
 && grep -qxF 'app-text/xmlto text' /etc/portage/package.use/zz-late-world || printf '\napp-text/xmlto text\n' >> /etc/portage/package.use/zz-late-world
RUN emerge -pqe --columns @world | awk '{for(i=1;i<=NF;i++) if($i ~ /\//) {print $i; break}}' > /tmp/world_packages.txt \
 && total_lines=$(wc -l < /tmp/world_packages.txt) \
 && lines_per_stage=$(( (total_lines + 9) / 10 )) \
 && for i in $(seq 1 10); do start=$(( (i - 1) * lines_per_stage + 1 )); end=$(( i * lines_per_stage )); sed -n "${start},${end}p" /tmp/world_packages.txt > "/tmp/world_stage_${i}.txt"; done
RUN --mount=type=bind,source=./distfiles,target=/var/cache/distfiles-host,ro \
--mount=type=bind,source=./binpkgs,target=/var/cache/binpkgs-host,ro \
--mount=type=cache,target=/var/cache/distfiles-cache \
--mount=type=cache,target=/var/cache/binpkgs-cache mkdir -p /var/cache/distfiles /var/cache/binpkgs /var/cache/binhost \
 && cp -rn /var/cache/distfiles-host/. /var/cache/distfiles/ 2>/dev/null || true \
 && cp -rn /var/cache/distfiles-cache/. /var/cache/distfiles/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-host/. /var/cache/binpkgs/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-host/. /var/cache/binhost/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-cache/. /var/cache/binpkgs/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-cache/. /var/cache/binhost/ 2>/dev/null || true \
 && if [ -s /tmp/world_stage_1.txt ]; then emerge --ask=n $(grep -E '.+/.+' /tmp/world_stage_1.txt); fi \
 && cp -rn /var/cache/distfiles/. /var/cache/distfiles-cache/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs/. /var/cache/binpkgs-cache/ 2>/dev/null || true \
 && cp -rn /var/cache/binhost/. /var/cache/binpkgs-cache/ 2>/dev/null || true
RUN --mount=type=bind,source=./distfiles,target=/var/cache/distfiles-host,ro \
--mount=type=bind,source=./binpkgs,target=/var/cache/binpkgs-host,ro \
--mount=type=cache,target=/var/cache/distfiles-cache \
--mount=type=cache,target=/var/cache/binpkgs-cache mkdir -p /var/cache/distfiles /var/cache/binpkgs /var/cache/binhost \
 && cp -rn /var/cache/distfiles-host/. /var/cache/distfiles/ 2>/dev/null || true \
 && cp -rn /var/cache/distfiles-cache/. /var/cache/distfiles/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-host/. /var/cache/binpkgs/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-host/. /var/cache/binhost/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-cache/. /var/cache/binpkgs/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-cache/. /var/cache/binhost/ 2>/dev/null || true \
 && if [ -s /tmp/world_stage_2.txt ]; then emerge --ask=n $(grep -E '.+/.+' /tmp/world_stage_2.txt); fi \
 && cp -rn /var/cache/distfiles/. /var/cache/distfiles-cache/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs/. /var/cache/binpkgs-cache/ 2>/dev/null || true \
 && cp -rn /var/cache/binhost/. /var/cache/binpkgs-cache/ 2>/dev/null || true
RUN --mount=type=bind,source=./distfiles,target=/var/cache/distfiles-host,ro \
--mount=type=bind,source=./binpkgs,target=/var/cache/binpkgs-host,ro \
--mount=type=cache,target=/var/cache/distfiles-cache \
--mount=type=cache,target=/var/cache/binpkgs-cache mkdir -p /var/cache/distfiles /var/cache/binpkgs /var/cache/binhost \
 && cp -rn /var/cache/distfiles-host/. /var/cache/distfiles/ 2>/dev/null || true \
 && cp -rn /var/cache/distfiles-cache/. /var/cache/distfiles/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-host/. /var/cache/binpkgs/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-host/. /var/cache/binhost/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-cache/. /var/cache/binpkgs/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-cache/. /var/cache/binhost/ 2>/dev/null || true \
 && if [ -s /tmp/world_stage_3.txt ]; then emerge --ask=n $(grep -E '.+/.+' /tmp/world_stage_3.txt); fi \
 && cp -rn /var/cache/distfiles/. /var/cache/distfiles-cache/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs/. /var/cache/binpkgs-cache/ 2>/dev/null || true \
 && cp -rn /var/cache/binhost/. /var/cache/binpkgs-cache/ 2>/dev/null || true
RUN --mount=type=bind,source=./distfiles,target=/var/cache/distfiles-host,ro \
--mount=type=bind,source=./binpkgs,target=/var/cache/binpkgs-host,ro \
--mount=type=cache,target=/var/cache/distfiles-cache \
--mount=type=cache,target=/var/cache/binpkgs-cache mkdir -p /var/cache/distfiles /var/cache/binpkgs /var/cache/binhost \
 && cp -rn /var/cache/distfiles-host/. /var/cache/distfiles/ 2>/dev/null || true \
 && cp -rn /var/cache/distfiles-cache/. /var/cache/distfiles/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-host/. /var/cache/binpkgs/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-host/. /var/cache/binhost/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-cache/. /var/cache/binpkgs/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-cache/. /var/cache/binhost/ 2>/dev/null || true \
 && if [ -s /tmp/world_stage_4.txt ]; then emerge --ask=n $(grep -E '.+/.+' /tmp/world_stage_4.txt); fi \
 && cp -rn /var/cache/distfiles/. /var/cache/distfiles-cache/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs/. /var/cache/binpkgs-cache/ 2>/dev/null || true \
 && cp -rn /var/cache/binhost/. /var/cache/binpkgs-cache/ 2>/dev/null || true
RUN --mount=type=bind,source=./distfiles,target=/var/cache/distfiles-host,ro \
--mount=type=bind,source=./binpkgs,target=/var/cache/binpkgs-host,ro \
--mount=type=cache,target=/var/cache/distfiles-cache \
--mount=type=cache,target=/var/cache/binpkgs-cache mkdir -p /var/cache/distfiles /var/cache/binpkgs /var/cache/binhost \
 && cp -rn /var/cache/distfiles-host/. /var/cache/distfiles/ 2>/dev/null || true \
 && cp -rn /var/cache/distfiles-cache/. /var/cache/distfiles/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-host/. /var/cache/binpkgs/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-host/. /var/cache/binhost/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-cache/. /var/cache/binpkgs/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-cache/. /var/cache/binhost/ 2>/dev/null || true \
 && if [ -s /tmp/world_stage_5.txt ]; then emerge --ask=n $(grep -E '.+/.+' /tmp/world_stage_5.txt); fi \
 && cp -rn /var/cache/distfiles/. /var/cache/distfiles-cache/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs/. /var/cache/binpkgs-cache/ 2>/dev/null || true \
 && cp -rn /var/cache/binhost/. /var/cache/binpkgs-cache/ 2>/dev/null || true
RUN --mount=type=bind,source=./distfiles,target=/var/cache/distfiles-host,ro \
--mount=type=bind,source=./binpkgs,target=/var/cache/binpkgs-host,ro \
--mount=type=cache,target=/var/cache/distfiles-cache \
--mount=type=cache,target=/var/cache/binpkgs-cache mkdir -p /var/cache/distfiles /var/cache/binpkgs /var/cache/binhost \
 && cp -rn /var/cache/distfiles-host/. /var/cache/distfiles/ 2>/dev/null || true \
 && cp -rn /var/cache/distfiles-cache/. /var/cache/distfiles/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-host/. /var/cache/binpkgs/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-host/. /var/cache/binhost/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-cache/. /var/cache/binpkgs/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-cache/. /var/cache/binhost/ 2>/dev/null || true \
 && if [ -s /tmp/world_stage_6.txt ]; then emerge --ask=n $(grep -E '.+/.+' /tmp/world_stage_6.txt); fi \
 && cp -rn /var/cache/distfiles/. /var/cache/distfiles-cache/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs/. /var/cache/binpkgs-cache/ 2>/dev/null || true \
 && cp -rn /var/cache/binhost/. /var/cache/binpkgs-cache/ 2>/dev/null || true
RUN --mount=type=bind,source=./distfiles,target=/var/cache/distfiles-host,ro \
--mount=type=bind,source=./binpkgs,target=/var/cache/binpkgs-host,ro \
--mount=type=cache,target=/var/cache/distfiles-cache \
--mount=type=cache,target=/var/cache/binpkgs-cache mkdir -p /var/cache/distfiles /var/cache/binpkgs /var/cache/binhost \
 && cp -rn /var/cache/distfiles-host/. /var/cache/distfiles/ 2>/dev/null || true \
 && cp -rn /var/cache/distfiles-cache/. /var/cache/distfiles/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-host/. /var/cache/binpkgs/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-host/. /var/cache/binhost/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-cache/. /var/cache/binpkgs/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-cache/. /var/cache/binhost/ 2>/dev/null || true \
 && if [ -s /tmp/world_stage_7.txt ]; then emerge --ask=n $(grep -E '.+/.+' /tmp/world_stage_7.txt); fi \
 && cp -rn /var/cache/distfiles/. /var/cache/distfiles-cache/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs/. /var/cache/binpkgs-cache/ 2>/dev/null || true \
 && cp -rn /var/cache/binhost/. /var/cache/binpkgs-cache/ 2>/dev/null || true
RUN --mount=type=bind,source=./distfiles,target=/var/cache/distfiles-host,ro \
--mount=type=bind,source=./binpkgs,target=/var/cache/binpkgs-host,ro \
--mount=type=cache,target=/var/cache/distfiles-cache \
--mount=type=cache,target=/var/cache/binpkgs-cache mkdir -p /var/cache/distfiles /var/cache/binpkgs /var/cache/binhost \
 && cp -rn /var/cache/distfiles-host/. /var/cache/distfiles/ 2>/dev/null || true \
 && cp -rn /var/cache/distfiles-cache/. /var/cache/distfiles/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-host/. /var/cache/binpkgs/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-host/. /var/cache/binhost/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-cache/. /var/cache/binpkgs/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-cache/. /var/cache/binhost/ 2>/dev/null || true \
 && if [ -s /tmp/world_stage_8.txt ]; then emerge --ask=n $(grep -E '.+/.+' /tmp/world_stage_8.txt); fi \
 && cp -rn /var/cache/distfiles/. /var/cache/distfiles-cache/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs/. /var/cache/binpkgs-cache/ 2>/dev/null || true \
 && cp -rn /var/cache/binhost/. /var/cache/binpkgs-cache/ 2>/dev/null || true
RUN --mount=type=bind,source=./distfiles,target=/var/cache/distfiles-host,ro \
--mount=type=bind,source=./binpkgs,target=/var/cache/binpkgs-host,ro \
--mount=type=cache,target=/var/cache/distfiles-cache \
--mount=type=cache,target=/var/cache/binpkgs-cache mkdir -p /var/cache/distfiles /var/cache/binpkgs /var/cache/binhost \
 && cp -rn /var/cache/distfiles-host/. /var/cache/distfiles/ 2>/dev/null || true \
 && cp -rn /var/cache/distfiles-cache/. /var/cache/distfiles/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-host/. /var/cache/binpkgs/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-host/. /var/cache/binhost/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-cache/. /var/cache/binpkgs/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-cache/. /var/cache/binhost/ 2>/dev/null || true \
 && if [ -s /tmp/world_stage_9.txt ]; then emerge --ask=n $(grep -E '.+/.+' /tmp/world_stage_9.txt); fi \
 && cp -rn /var/cache/distfiles/. /var/cache/distfiles-cache/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs/. /var/cache/binpkgs-cache/ 2>/dev/null || true \
 && cp -rn /var/cache/binhost/. /var/cache/binpkgs-cache/ 2>/dev/null || true
RUN --mount=type=bind,source=./distfiles,target=/var/cache/distfiles-host,ro \
--mount=type=bind,source=./binpkgs,target=/var/cache/binpkgs-host,ro \
--mount=type=cache,target=/var/cache/distfiles-cache \
--mount=type=cache,target=/var/cache/binpkgs-cache mkdir -p /var/cache/distfiles /var/cache/binpkgs /var/cache/binhost \
 && cp -rn /var/cache/distfiles-host/. /var/cache/distfiles/ 2>/dev/null || true \
 && cp -rn /var/cache/distfiles-cache/. /var/cache/distfiles/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-host/. /var/cache/binpkgs/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-host/. /var/cache/binhost/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-cache/. /var/cache/binpkgs/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-cache/. /var/cache/binhost/ 2>/dev/null || true \
 && if [ -s /tmp/world_stage_10.txt ]; then emerge --ask=n $(grep -E '.+/.+' /tmp/world_stage_10.txt); fi \
 && cp -rn /var/cache/distfiles/. /var/cache/distfiles-cache/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs/. /var/cache/binpkgs-cache/ 2>/dev/null || true \
 && cp -rn /var/cache/binhost/. /var/cache/binpkgs-cache/ 2>/dev/null || true
RUN gcc-config -l
# Temporarily install package analysis tools
RUN --mount=type=bind,source=./distfiles,target=/var/cache/distfiles-host,ro \
--mount=type=bind,source=./binpkgs,target=/var/cache/binpkgs-host,ro \
--mount=type=cache,target=/var/cache/distfiles-cache \
--mount=type=cache,target=/var/cache/binpkgs-cache mkdir -p /var/cache/distfiles /var/cache/binpkgs /var/cache/binhost \
 && cp -rn /var/cache/distfiles-host/. /var/cache/distfiles/ 2>/dev/null || true \
 && cp -rn /var/cache/distfiles-cache/. /var/cache/distfiles/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-host/. /var/cache/binpkgs/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-host/. /var/cache/binhost/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-cache/. /var/cache/binpkgs/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-cache/. /var/cache/binhost/ 2>/dev/null || true \
 && emerge --ask=n app-portage/genlop app-portage/gentoolkit \
 && cp -rn /var/cache/distfiles/. /var/cache/distfiles-cache/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs/. /var/cache/binpkgs-cache/ 2>/dev/null || true \
 && cp -rn /var/cache/binhost/. /var/cache/binpkgs-cache/ 2>/dev/null || true
RUN qlist -Iv sys-devel/gcc \
 && echo "Generating package statistics..." \
 && for pkg in $(qlist -I); do \
      SIZE=$(qsize -m "$pkg" | awk '{print $5$6}'); \
      TIME=$(genlop -t "$pkg" | grep "merge time" | tail -n 1 | sed 's/.*merge time: //'); \
      echo "$pkg | Size: ${SIZE:-N/A} | Build Time: ${TIME:-N/A}"; \
    done > /packages.txt
RUN --mount=type=bind,source=./distfiles,target=/var/cache/distfiles-host,ro \
--mount=type=bind,source=./binpkgs,target=/var/cache/binpkgs-host,ro \
--mount=type=cache,target=/var/cache/distfiles-cache \
--mount=type=cache,target=/var/cache/binpkgs-cache mkdir -p /var/cache/distfiles /var/cache/binpkgs /var/cache/binhost \
 && cp -rn /var/cache/distfiles-host/. /var/cache/distfiles/ 2>/dev/null || true \
 && cp -rn /var/cache/distfiles-cache/. /var/cache/distfiles/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-host/. /var/cache/binpkgs/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-host/. /var/cache/binhost/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-cache/. /var/cache/binpkgs/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-cache/. /var/cache/binhost/ 2>/dev/null || true \
 && emerge -C app-portage/genlop app-portage/gentoolkit || true \
 && cp -rn /var/cache/distfiles/. /var/cache/distfiles-cache/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs/. /var/cache/binpkgs-cache/ 2>/dev/null || true \
 && cp -rn /var/cache/binhost/. /var/cache/binpkgs-cache/ 2>/dev/null || true
# Sudo policy
RUN mkdir -p /etc/sudoers.d
COPY <<'EOF' /etc/sudoers.d/wheel
%wheel ALL=(ALL:ALL) NOPASSWD: ALL
EOF
RUN groupadd -f input \
 && useradd -m -G users,wheel,audio,video,input -s /bin/bash kiel \
 && for grp in libvirt kvm qemu; do if getent group "${grp}" >/dev/null; then usermod -aG "${grp}" kiel; fi; done
COPY <<'EOF' /home/kiel/.xinitrc
xrandr --output DP-0 --scale 1x1 --rotate left; xrandr --output DP-2 --scale 1x1 --rotate right; xrandr --output DP-2 --right-of DP-0

# xrandr --output DP-0 --scale 2x2; xrandr --output DP-2 --scale 2x2 --pos 2160x0
# xrandr --output DP-0 --scale 2x2; xrandr --output DP-2 --scale 2x2 --below DP-0 --pos 0x3840

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"
export PULSE_SERVER="${PULSE_SERVER:-unix:${XDG_RUNTIME_DIR}/pulse/native}"

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

EOF
COPY config/activate /home/kiel/activate
COPY config/start2 /home/kiel/start2
COPY config/start-pipewire.sh /home/kiel/start-pipewire.sh
RUN chmod +x /home/kiel/activate /home/kiel/start2 /home/kiel/start-pipewire.sh \
 && chown kiel:kiel /home/kiel/activate /home/kiel/start2 /home/kiel/start-pipewire.sh
COPY <<'EOF' /etc/init.d/user-runtime
#!/sbin/openrc-run
description="Prepare XDG runtime directories for lingering OpenRC user sessions"
depend() {
  need localmount
  before user.kiel
}
start() {
  ebegin "Preparing XDG runtime directory for kiel"
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
  chown -h kiel:kiel \
    /home/kiel/.config/rc/runlevels/default/dbus \
    /home/kiel/.config/rc/runlevels/default/pipewire \
    /home/kiel/.config/rc/runlevels/default/pipewire-pulse \
    /home/kiel/.config/rc/runlevels/default/wireplumber
  eend $?
}

EOF
COPY <<'EOF' /etc/profile.d/zz-openrc-user-session.sh
#!/bin/sh
uid="$(id -u 2>/dev/null || printf '')"
if [ -n "${uid}" ] && [ "${uid}" -ge 1000 ] 2>/dev/null; then
  : "${XDG_RUNTIME_DIR:=/run/user/${uid}}"
  export XDG_RUNTIME_DIR
  if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
  fi
  if [ -z "${PULSE_SERVER:-}" ]; then
    export PULSE_SERVER="unix:${XDG_RUNTIME_DIR}/pulse/native"
  fi
fi

EOF
COPY <<'EOF' /etc/user/init.d/dbus
#!/sbin/openrc-run
description="User D-Bus session bus"
command="/usr/bin/dbus-daemon"
command_args="--session --address=unix:path=${XDG_RUNTIME_DIR}/bus --nofork --nopidfile --nosyslog"
command_background="yes"
pidfile="${XDG_RUNTIME_DIR}/dbus-session.pid"

EOF
COPY <<'EOF' /etc/user/init.d/pipewire
#!/sbin/openrc-run
description="PipeWire media server"
command="/usr/bin/pipewire"
command_background="yes"
pidfile="${XDG_RUNTIME_DIR}/pipewire.pid"
depend() {
  need dbus
}

EOF
COPY <<'EOF' /etc/user/init.d/pipewire-pulse
#!/sbin/openrc-run
description="PipeWire PulseAudio compatibility server"
command="/usr/bin/pipewire-pulse"
command_background="yes"
pidfile="${XDG_RUNTIME_DIR}/pipewire-pulse.pid"
depend() {
  need pipewire dbus
}

EOF
COPY <<'EOF' /etc/user/init.d/wireplumber
#!/sbin/openrc-run
description="WirePlumber session manager"
command="/usr/bin/wireplumber"
command_background="yes"
pidfile="${XDG_RUNTIME_DIR}/wireplumber.pid"
depend() {
  need pipewire dbus
}

EOF
COPY <<'EOF' /etc/resolv.conf
nameserver 1.1.1.1
nameserver 8.8.8.8

EOF
COPY <<'EOF' /etc/init.d/reverse-ssh-eu
#!/sbin/openrc-run
name="reverse-ssh-eu"
description="Reverse SSH tunnel to tinyeu"
supervisor="supervise-daemon"
command="/usr/bin/autossh"
command_args="-M 0 -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -R 2332:localhost:22 tinyeu"
command_user="kiel"
supervise_daemon_args="-e HOME=/home/kiel"
depend() {
    use net
    after iwd
    want tailscale
}

EOF
COPY <<'EOF' /etc/init.d/reverse-ssh-us
#!/sbin/openrc-run
name="reverse-ssh-us"
description="Reverse SSH tunnel to tinyus"
supervisor="supervise-daemon"
command="/usr/bin/autossh"
command_args="-M 0 -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -R 2332:localhost:22 tinyus"
command_user="kiel"
supervise_daemon_args="-e HOME=/home/kiel"
depend() {
    use net
    after iwd
    want tailscale
}

EOF
RUN chmod +x /etc/init.d/reverse-ssh-* \
 && rc-update add sshd default \
 && rc-update add reverse-ssh-eu default \
 && rc-update add reverse-ssh-us default
USER kiel
ENV HOME=/home/kiel
# Install Emacs packages from MELPA in batch mode
USER root
RUN mkdir -p /usr/local/share/openrc-host-config
COPY config/activate /usr/local/share/openrc-host-config/activate
COPY config/start2 /usr/local/share/openrc-host-config/start2
COPY <<'EOF' /usr/local/share/openrc-host-config/reverse-ssh-eu.initd
#!/sbin/openrc-run
name="reverse-ssh-eu"
description="Reverse SSH tunnel to tinyeu"
supervisor="supervise-daemon"
command="/usr/bin/autossh"
command_args="-M 0 -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -R 2332:localhost:22 tinyeu"
command_user="kiel"
supervise_daemon_args="-e HOME=/home/kiel"
depend() {
    use net
    after iwd
    want tailscale
}

EOF
COPY <<'EOF' /usr/local/share/openrc-host-config/reverse-ssh-us.initd
#!/sbin/openrc-run
name="reverse-ssh-us"
description="Reverse SSH tunnel to tinyus"
supervisor="supervise-daemon"
command="/usr/bin/autossh"
command_args="-M 0 -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -R 2332:localhost:22 tinyus"
command_user="kiel"
supervise_daemon_args="-e HOME=/home/kiel"
depend() {
    use net
    after iwd
    want tailscale
}

EOF
RUN fc-cache -fv
COPY <<'EOF' /etc/conf.d/modules
modules="amdgpu mt7921e"
EOF
COPY <<'EOF' /etc/conf.d/keymaps
keymap="colemak"
EOF
RUN <<'EOF'
set -e
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
chown -R kiel:kiel /home/kiel/.config
EOF
RUN rm -rf /var/tmp/portage/*
RUN emerge -C dev-lang/go-bootstrap dev-lang/go dev-util/cargo-c virtual/rust dev-lang/rust-bin || true
WORKDIR /
RUN --mount=type=bind,source=./distfiles,target=/var/cache/distfiles-host,ro \
--mount=type=bind,source=./binpkgs,target=/var/cache/binpkgs-host,ro \
--mount=type=cache,target=/var/cache/distfiles-cache \
--mount=type=cache,target=/var/cache/binpkgs-cache mkdir -p /var/cache/distfiles /var/cache/binpkgs /var/cache/binhost \
 && cp -rn /var/cache/distfiles-host/. /var/cache/distfiles/ 2>/dev/null || true \
 && cp -rn /var/cache/distfiles-cache/. /var/cache/distfiles/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-host/. /var/cache/binpkgs/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-host/. /var/cache/binhost/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-cache/. /var/cache/binpkgs/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-cache/. /var/cache/binhost/ 2>/dev/null || true \
 && emerge --ask=n sys-fs/e2fsprogs sys-fs/erofs-utils || true \
 && cp -rn /var/cache/distfiles/. /var/cache/distfiles-cache/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs/. /var/cache/binpkgs-cache/ 2>/dev/null || true \
 && cp -rn /var/cache/binhost/. /var/cache/binpkgs-cache/ 2>/dev/null || true
COPY config/mount-overlayfs.sh /usr/lib/dracut/modules.d/70overlayfs
RUN chmod +x /usr/lib/dracut/modules.d/70overlayfs/*.sh
RUN dracut \
-m "kernel-modules base dmsquash-live dm udev-rules crypt lvm overlayfs" \
--filesystems "squashfs erofs vfat ext4 overlay btrfs" \
--add-drivers "libnvdimm nd_pmem nd_btt nd_blk dax device_dax dax_pmem dax_pmem_core nd_e820" \
--kver=${KVER_RELEASE} \
--install "stat blockdev" \
--force \
/boot/initramfs_squash_sda1-x86_64.img
RUN --mount=type=bind,source=./distfiles,target=/var/cache/distfiles-host,ro \
--mount=type=bind,source=./binpkgs,target=/var/cache/binpkgs-host,ro \
--mount=type=cache,target=/var/cache/distfiles-cache \
--mount=type=cache,target=/var/cache/binpkgs-cache mkdir -p /var/cache/distfiles /var/cache/binpkgs /var/cache/binhost \
 && cp -rn /var/cache/distfiles-host/. /var/cache/distfiles/ 2>/dev/null || true \
 && cp -rn /var/cache/distfiles-cache/. /var/cache/distfiles/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-host/. /var/cache/binpkgs/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-host/. /var/cache/binhost/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-cache/. /var/cache/binpkgs/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-cache/. /var/cache/binhost/ 2>/dev/null || true \
 && emerge --ask=n --oneshot app-portage/genlop \
 && cp -rn /var/cache/distfiles/. /var/cache/distfiles-cache/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs/. /var/cache/binpkgs-cache/ 2>/dev/null || true \
 && cp -rn /var/cache/binhost/. /var/cache/binpkgs-cache/ 2>/dev/null || true
RUN set -e \
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
&& emerge -C app-portage/genlop || true
RUN df -h
RUN eix-update
RUN eix-test-obsolete > /packages_obsolete.txt || true
RUN set -e \
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
      var/cache/binhost \
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
    || true

FROM base AS builder
FROM base AS cache-exporter
RUN --mount=type=cache,target=/var/cache/distfiles-cache \
--mount=type=cache,target=/var/cache/binpkgs-cache mkdir -p /distfiles /binpkgs \
 && cp -rn /var/cache/distfiles-cache/. /distfiles/ 2>/dev/null || true \
 && cp -rn /var/cache/binpkgs-cache/. /binpkgs/ 2>/dev/null || true

FROM scratch
COPY --from=builder /gentoo.squashfs_e14 /
COPY --from=builder /boot/vmlinuz /
COPY --from=builder /boot/initramfs_squash_sda1-x86_64.img /
COPY --from=builder /packages.txt /
COPY --from=builder /packages.tsv /
COPY --from=builder /packages_obsolete.txt /
COPY --from=cache-exporter /distfiles /distfiles
COPY --from=cache-exporter /binpkgs /binpkgs

