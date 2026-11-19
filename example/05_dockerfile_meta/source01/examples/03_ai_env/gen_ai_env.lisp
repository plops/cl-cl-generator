;;;; gen_ai_env.lisp -- generates the Dockerfile of the AI development environment.
;;;;
;;;; Layout of this file:
;;;;   1. Configuration   primitive feature switches and versions (edit these)
;;;;   2. Derived values  functions computed at generation time from the switches
;;;;   3. DSL helpers     small functions that return Dockerfile S-expressions
;;;;   4. Builder stages  independent download/installer stages
;;;;   5. Smoke tests     build-time checks for every enabled feature
;;;;   6. Runner stage    the final image, split into one function per topic
;;;;   7. Entry point     generate-ai-env
;;;;
;;;; Loading this file writes ./Dockerfile unless AI_ENV_NO_AUTOGEN is set.

(eval-when (:compile-toplevel :execute :load-toplevel)
  (let ((current-dir (make-pathname :directory (pathname-directory *load-pathname*))))
    (push (merge-pathnames "../../" current-dir) asdf:*central-registry*))
  (asdf:load-system :cl-dockerfile-generator)
  (setf (readtable-case *readtable*) :invert))

(in-package :cl-dockerfile-generator)

(declaim (optimize (safety 3)
                   (debug 3)
                   (speed 1)))

;;; ===================================================================
;;; 1. Configuration
;;; ===================================================================

;;; --- Base images ----------------------------------------------------

(defparameter *enable-cuda* t
  "When true, configure the image with NVIDIA CUDA support.")

;; Suggested for `uv pip install cuml`: :runtime (1.81 GB)
;; Pre-built RAPIDS wheels package their own math/cuml libraries, needing only the runtime.
(defparameter *cuda-flavor* :cudnn-devel
  "CUDA image variant (amd64 compressed sizes for 13.4.1):
   - :cudnn-devel   : 4.74 GB | AI dev (NVCC, CUDA headers, cuDNN headers & libs)
   - :devel         : 4.25 GB | GPU dev (NVCC, CUDA headers - needed if compiling cuML from source)
   - :cudnn-runtime : 2.29 GB | Deep Learning inference (CUDA runtime + cuDNN)
   - :runtime       : 1.81 GB | Optimal for uv/pip pre-built wheels (CUDA runtime)
   - :base          : 211 MB  | Minimal driver-linking only (usually too stripped for cuML)
   * Note: TensorRT flavors are omitted as they are arm64-only in this release.")

;; https://hub.docker.com/r/nvidia/cuda/tags
(defparameter *cuda-version* "13.3.1" ;; "13.5.0"
  "NVIDIA CUDA version tag.")

(defparameter *cuda-ubuntu-version* "ubuntu26.04"
  "Ubuntu base release for CUDA images.")

(defparameter *ubuntu-image* "ubuntu:26.04"
  "Plain Ubuntu image used when CUDA is disabled.")

(defparameter *base-image* nil
  "Base image of the runner and Python builder. NIL means: computed by COMPUTE-BASE-IMAGE.")

(defparameter *builder-base-image* "ubuntu:26.04"
  "Minimal base image for CLI builder stages to save build time and memory.")

;;; --- Languages, firmware and system tools ---------------------------

(defparameter *install-gcc* t
  "GCC, build-essential and the C/C++ developer packages in *GCC-UBUNTU-PACKAGES*.")
(defparameter *install-sbcl* t
  "SBCL and rlwrap.")
(defparameter *install-quicklisp* t
  "Install Quicklisp when SBCL is enabled; disable for a small validation image.")
(defparameter *install-emacs* nil
  "Terminal Emacs with MELPA packages and the .emacs from the build context.")
(defparameter *install-python* t
  "System Python 3 (python3-full).")
(defparameter *install-python-libs* t
  "Separate uv-built virtual environment /workspace/.venv containing PYTHON-LIBS.")
(defparameter *install-rust* t
  "Stable Rust toolchain via rustup.")
(defparameter *install-probe-rs* t
  "probe-rs embedded debugging tools. Requires *INSTALL-RUST*.")
(defparameter *install-difftastic* t
  "difftastic, configured as git's external diff. Requires *INSTALL-RUST*.")
(defparameter *rust-cache-volume* t
  "Declare /root/.cargo as a VOLUME (setup02_run.sh mounts a named volume there).")
(defparameter *install-conan* t
  "Install the Conan C/C++ package manager as an isolated uv tool.")
(defparameter *install-docker-cli* t
  "Install the Docker CLI for use with an optionally mounted host Docker socket.")

;; https://gitlab.arm.com/tooling/gnu-toolchains-for-arm/
(defparameter *install-arm-none-eabi* t
  "Install the Arm GNU bare-metal toolchain used by the fountain firmware.")
(defparameter *arm-none-eabi-version* "15.3.rel2"
  "Pinned Arm GNU toolchain release.")
(defparameter *install-jlink* t
  "Install the SEGGER J-Link command-line tools used to flash and debug firmware.")
(defparameter *jlink-version* "9.92"
  "Pinned SEGGER J-Link release.")

;;; --- AI agent CLIs --------------------------------------------------

(defparameter *install-agy* nil
  "Google Antigravity CLI with a permissive wrapper.")
(defparameter *install-codex* t
  "Latest npm Codex CLI with a wrapper that bypasses approvals and sandboxing.")
(defparameter *install-copilot* t
  "GitHub Copilot CLI with an --allow-all wrapper.")
(defparameter *install-claude* t
  "Install Anthropic's Claude Code CLI (native build). Credentials and state
live in CLAUDE_CONFIG_DIR=/root/.claude, which setup02_run.sh bind-mounts from the host.")
(defparameter *install-kiro-cli* t
  "Kiro CLI with a wrapper that forces `init --force`.")
(defparameter *install-kirocrew* nil
  "Install KiroCrew and its managed Python runtime. Requires *INSTALL-KIRO-CLI*.")
(defparameter *kirocrew-version* "0.7.2"
  "Signed KiroCrew release verified by the gateway and CLI integration tests.")
(defparameter *install-grok* nil
  "Grok Build CLI with an --always-approve wrapper.")
(defparameter *install-muse* t
  "Install Meta's Muse Code CLI with a --yolo wrapper.")
(defparameter *install-devin-cli* nil
  "Devin CLI with a --permission-mode bypass wrapper.")

;;; --- Cloud, CI and code-quality tools -------------------------------

(defparameter *install-azure-cli* nil
  "Azure CLI from Microsoft's apt repository.")
(defparameter *install-teamcity-cli* nil
  "TeamCity CLI from JetBrains' installer.")
;; Code-quality tools used by Habit Hooks.
(defparameter *install-habit-hooks* nil
  "Habit Hooks with all optional integrations (uv tool).")
(defparameter *install-deptry* nil
  "Deptry (uv tool).")
(defparameter *install-jscpd* nil
  "JSCPD copy/paste detector (global npm package).")
(defparameter *install-archify* nil
  "Install the Archify Codex skill and a Chrome for Testing browser for visual checks.")
(defparameter *archify-chrome-build* "stable"
  "Chrome for Testing channel or exact version used by Archify (for example, stable or 140.0.7339.80).")

;;; --- Tests ----------------------------------------------------------

(defparameter *enable-tests* t
  "Run build-time smoke tests for every enabled component that has a test entry.")

;;; --- Package lists --------------------------------------------------

(defparameter *python-libs*
  '(numpy pandas loguru requests ruff)
  "Python packages installed into /workspace/.venv.
Candidates: google-antigravity azure-cognitiveservices-speech huggingface_hub openai
matplotlib scipy tqdm xarray nbdev scikit-learn seaborn.")

(defparameter *python-cuda-libs* '(polars pyarrow)
  "Additional Python packages installed when *ENABLE-CUDA* is true.")

(defparameter *gcc-ubuntu-packages*
  '("clang-format" "clang-tidy" "ninja-build" "cmake" "build-essential" "pkg-config" "gdb")
  "C/C++ developer packages installed when *INSTALL-GCC* is true. Candidate: clangd.")

;; Extra Ubuntu packages that are handy in an interactive shell.
;; Candidates: dnsutils lsof strace shellcheck bat dos2unix rsync
(defparameter *ubuntu-packages*
  '("less" "file" "findutils" "tree" "man-db" "procps" "psmisc" "iproute2" "iputils-ping"
    "ripgrep" "fd-find" "yq" "picocom" "git" "usbutils" "sudo" "libusb-1.0-0-dev"
    "moreutils" "tmux" "fzf" "git-lfs" "openssh-client" "parallel" "unzip" "zip" "xz-utils")
  "Interactive and firmware-development Ubuntu packages of the runner image.")

;; Shared libraries needed by the Chrome for Testing binary used by Archify.
;; Keep this list conditional: it is a significant part of the Archify opt-out.
(defparameter *archify-browser-packages*
  '("fonts-liberation" "libasound2t64" "libatk-bridge2.0-0t64" "libatk1.0-0t64"
    "libatspi2.0-0t64" "libcairo2" "libcups2t64" "libdbus-1-3" "libdrm2" "libexpat1"
    "libfontconfig1" "libgbm1" "libglib2.0-0t64" "libnspr4" "libnss3" "libpango-1.0-0"
    "libudev1" "libx11-6" "libxcb1" "libxcomposite1" "libxdamage1" "libxext6" "libxfixes3"
    "libxkbcommon0" "libxrandr2"))

(defparameter *quicklisp-local-projects*
  '("cl-py-generator" "cl-cpp-generator2" "cl-rust-generator")
  "Repositories below /workspace/src that are symlinked into Quicklisp's local-projects.")

(defparameter *quicklisp-systems*
  '("quicklisp-slime-helper" "alexandria" "jonathan" "external-program" "cl-ppcre")
  "Quicklisp systems pre-fetched into the image.")

(defparameter *emacs-packages*
  '(compat cmake-mode company gptel magit markdown-mode orderless paredit slime yaml-mode use-package)
  "MELPA/ELPA packages pre-installed for Emacs.")

;;; ===================================================================
;;; 2. Derived values (computed at generation time)
;;; ===================================================================

(defun compute-base-image ()
  "Docker base image string for the current CUDA configuration."
  (if *enable-cuda*
      (format nil "nvidia/cuda:~a-~(~a~)-~a"
              *cuda-version* *cuda-flavor* *cuda-ubuntu-version*)
      *ubuntu-image*))

(defun base-image ()
  (or *base-image* (compute-base-image)))

(defun python-libs ()
  (append *python-libs* (when *enable-cuda* *python-cuda-libs*)))

(defun runner-apt-packages ()
  "Packages of the main apt layer. REMOVE-DUPLICATES keeps the last occurrence."
  (remove-duplicates (append '("curl" "ca-certificates" "git" "jq")
                             (when *install-gcc* *gcc-ubuntu-packages*)
                             *ubuntu-packages*)
                     :test #'string=))

(defun arm-none-eabi-toolchain ()
  (format nil "arm-gnu-toolchain-~a-x86_64-arm-none-eabi" *arm-none-eabi-version*))

(defun jlink-version-code ()
  (format nil "V~a" (remove #\. *jlink-version*)))

(defun jlink-directory ()
  (format nil "JLink_Linux_~a_x86_64" (jlink-version-code)))

(defun dependency-package-groups ()
  "Component dependencies, each group installed in its own apt layer for caching."
  `((,(or *install-gcc* *install-rust*) "build-essential" "gcc")
    (,*install-sbcl* "sbcl" "rlwrap")
    (,*install-emacs* "emacs-nox")
    (,(or *install-python* *install-python-libs*) "python3-full")
    (,(or *install-codex* *install-jscpd* *install-archify*) "nodejs" "npm")
    (,(or *install-azure-cli* *install-docker-cli*) "gnupg")
    (,*install-azure-cli* "lsb-release")
    (,*install-archify* ,@*archify-browser-packages*)))

;;; ===================================================================
;;; 3. DSL helpers
;;; ===================================================================

(defparameter *apt-cache-mounts*
  '("type=cache,target=/var/cache/apt,sharing=locked"
    "type=cache,target=/var/lib/apt/lists,sharing=locked"))

(defparameter *uv-cache-mount* "type=cache,target=/root/.cache/uv")
(defparameter *npm-cache-mount* "type=cache,target=/root/.npm")

(defun apt-get-install (packages)
  (format nil "apt-get install -y --no-install-recommends ~{~a~^ ~}" packages))

(defun apt-run (&rest commands)
  "RUN with the shared apt cache mounts."
  `(run :mount ,*apt-cache-mounts* (and ,@commands)))

(defun apt-install (packages)
  (apt-run "apt-get update" (apt-get-install packages)))

(defun stage-header (title &optional (width 68))
  (let ((rule (make-string width :initial-element #\=)))
    `((comment ,rule) (comment ,title) (comment ,rule))))

(defun uv-copy ()
  "Copy Astral's uv from its official release container."
  `(copy "/uv" "/uvx" "/bin/" :from "ghcr.io/astral-sh/uv:latest"))

(defun uv-tool-install (spec comment)
  `((comment ,comment)
    (run :mount ,*uv-cache-mount* ,(format nil "uv tool install ~a" spec))))

(defun npm-global-install (spec comment)
  `((comment ,comment)
    (run :mount ,*npm-cache-mount* ,(format nil "npm install -g ~a" spec))))

(defun bin-path (name) (format nil "/usr/local/bin/~a" name))
(defun real-path (name) (format nil "/usr/local/bin/~a.real" name))

(defun bash-script (&rest lines)
  "A bash script with strict mode. Each line ends with a newline."
  (format nil "#!/usr/bin/env bash~%set -euo pipefail~%~{~a~%~}" lines))

(defun exec-wrapper (real-binary &optional default-args)
  "Wrapper script that runs REAL-BINARY with DEFAULT-ARGS prepended."
  (bash-script (format nil "exec ~a ~@[~a ~]\"$@\"" real-binary default-args)))

(defun install-wrapper (name script)
  "Write SCRIPT to /usr/local/bin/NAME and make it executable."
  `((copy :heredoc ,(bin-path name) ,script)
    (run ,(format nil "chmod +x ~a" (bin-path name)))))

(defun wrap-binary (name script &key comment)
  "Move /usr/local/bin/NAME to NAME.real and install SCRIPT as NAME."
  `(,@(when comment `((comment ,comment)))
    (run ,(format nil "mv ~a ~a" (bin-path name) (real-path name)))
    ,@(install-wrapper name script)))

(defun installer-builder-stage (stage title &key (packages '("ca-certificates" "curl"))
                                                 (workdir "/workspace") comment commands)
  "Builder stage on *BUILDER-BASE-IMAGE* that runs an upstream installer."
  `(,@(stage-header title)
    (from ,*builder-base-image* :as ,stage)
    (env DEBIAN_FRONTEND "noninteractive")
    ,(apt-install packages)
    ,@(when workdir `((workdir ,workdir)))
    (comment ,comment)
    (run (and ,@commands))))

;;; --- Wrapper scripts with more than an exec line --------------------

(defun kirocrew-wrapper-script (real-binary)
  (format nil #r^#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  "")
    exec ~a gateway --approval yolo --no-open
    ;;
  gateway)
    shift
    gateway_args=()
    while (($#)); do
      case "$1" in
        --approval) shift; (($#)) && shift ;;
        --approval=*) shift ;;
        *) gateway_args+=("$1"); shift ;;
      esac
    done
    exec ~a gateway --approval yolo "${gateway_args[@]}"
    ;;
  *)
    exec ~a "$@"
    ;;
esac
^ real-binary real-binary real-binary))

(defun kiro-cli-wrapper-script (real-binary)
  (bash-script "case \"${1:-}\" in"
               (format nil "  init) exec ~a init --force \"${@:2}\" ;;" real-binary)
               (format nil "  *) exec ~a \"$@\" ;;" real-binary)
               "esac"))

;;; ===================================================================
;;; 4. Builder stages
;;; ===================================================================

(defun builder-python-stage ()
  (when *install-python-libs*
    `(,@(stage-header "Stage: Python Dependencies (runs in parallel with other builders)")
      (from ,(base-image) :as builder-python)
      (env DEBIAN_FRONTEND "noninteractive")
      (env UV_COMPILE_BYTECODE "1")
      (env UV_LINK_MODE "copy")
      (comment "Grab the modern uv binary directly from Astral's official release container")
      ,(uv-copy)
      (comment "Install base toolsets required to compile Python extensions")
      ,(apt-install '("python3-pip" "python3-venv" "python3-dev" "build-essential" "ca-certificates"))
      (workdir "/workspace")
      (comment "Install the programmatic Python SDK using uv")
      (run :mount ,*uv-cache-mount*
           (and "uv venv .venv"
                ,(format nil "uv pip install ~{~(~a~)~^ ~}" (python-libs)))))))

(defun builder-stages ()
  "All installer builder stages of enabled features, in Dockerfile order."
  (append
   (builder-python-stage)
   (when *install-agy*
     (installer-builder-stage
      'builder-agy "Stage: Antigravity CLI Download"
      :comment "Download, decompress, and run the Antigravity installation script"
      :commands '("curl -fsSL --compressed https://antigravity.google/cli/install.sh -o install.sh"
                  "chmod +x install.sh"
                  "./install.sh")))
   (when *install-copilot*
     (installer-builder-stage
      'builder-copilot "Stage: GitHub Copilot CLI Download"
      :comment "Download and install GitHub Copilot CLI from the official installer"
      :commands '("curl -fsSL https://gh.io/copilot-install -o copilot-install.sh"
                  "PREFIX=/usr/local VERSION=latest bash copilot-install.sh"
                  "rm copilot-install.sh")))
   (when *install-claude*
     (installer-builder-stage
      'builder-claude "Stage: Claude Code CLI Download"
      :comment "Install Claude Code with Anthropic's native installer and resolve the launcher symlink to a standalone binary"
      :commands '("curl -fsSL https://claude.ai/install.sh -o claude-install.sh"
                  "bash claude-install.sh"
                  "cp -L /root/.local/bin/claude /usr/local/bin/claude"
                  "/usr/local/bin/claude --version"
                  "rm claude-install.sh")))
   (when *install-kiro-cli*
     (installer-builder-stage
      'builder-kiro "Stage: Kiro CLI Download"
      :packages '("ca-certificates" "curl" "unzip")
      :comment "Install kiro-cli from Amazon using the official zip package"
      :commands '("curl -fsSL https://desktop-release.q.us-east-1.amazonaws.com/latest/kirocli-x86_64-linux.zip -o /tmp/kirocli.zip"
                  "unzip -q /tmp/kirocli.zip -d /tmp/kirocli-extracted"
                  "chmod +x /tmp/kirocli-extracted/kirocli/install.sh"
                  "KIRO_CLI_SKIP_SETUP=1 /tmp/kirocli-extracted/kirocli/install.sh"
                  "rm -rf /tmp/kirocli.zip /tmp/kirocli-extracted")))
   ;; KiroCrew publishes signed wheels outside PyPI. Its official installer verifies the
   ;; signed channel manifest and wheel digest and provisions a pinned CPython runtime.
   (when *install-kirocrew*
     (installer-builder-stage
      'builder-kirocrew "Stage: KiroCrew signed wheel installation"
      :packages '("ca-certificates" "curl" "openssl" "python3-full")
      :workdir nil
      :comment "Use KiroCrew's official signed-channel installer; it verifies the release manifest and wheel checksum"
      :commands (list "curl -fsSL https://download.crew.kiro.dev/cli.sh -o /tmp/kirocrew-install.sh"
                      (format nil "KIROCREW_HOME=/root/.kiro/crew-yolo KIROCREW_VENV=/opt/kirocrew-venv KIROCREW_PYTHON_DIR=/opt/kirocrew-python sh /tmp/kirocrew-install.sh --managed-python --version ~a" *kirocrew-version*)
                      "ln -s /root/.local/bin/kirocrew /usr/local/bin/kirocrew"
                      "rm -f /tmp/kirocrew-install.sh")))
   (when *install-teamcity-cli*
     (installer-builder-stage
      'builder-teamcity "Stage: TeamCity CLI Download"
      :comment "Install TeamCity CLI from the official JetBrains installer"
      :commands '("curl -fsSL https://jb.gg/tc/install -o /tmp/teamcity-install.sh"
                  "bash /tmp/teamcity-install.sh"
                  "rm -f /tmp/teamcity-install.sh"
                  "command -v teamcity >/dev/null")))))

;;; ===================================================================
;;; 5. Smoke tests
;;; ===================================================================

(defun smoke-tests ()
  "List of (ENABLED DESCRIPTION SCRIPT), evaluated at generation time."
  (list
   #+nil
   (list *install-codex*
         "Codex by running the CLI and asserting it matches the latest npm release"
         #r|set -eu
codex --version > /tmp/codex-version.txt
grep -Eq '[0-9]+\.[0-9]+\.[0-9]+' /tmp/codex-version.txt
|)
   #+nil
   (list *install-kiro-cli* "kiro-cli by invoking the wrapped CLI and helpers"
         #r|set -eu
kiro-cli --help > /tmp/kiro-cli-help.txt
[ -s /tmp/kiro-cli-help.txt ]
grep -qi "kiro" /tmp/kiro-cli-help.txt
|)
   #+nil
   (list *install-grok* "Grok Build by checking the CLI version"
         #r|set -eu
grok --version
agent --version
|)
   #+nil
   (list *install-muse* "Meta Muse Code by checking the CLI version"
         #r|set -eu
muse --version > /tmp/muse-version.txt
[ -s /tmp/muse-version.txt ]
grep -Eq '[0-9]+\.[0-9]+\.[0-9]+-R[0-9]+' /tmp/muse-version.txt
|)
   #+nil
   (list *install-azure-cli* "Azure CLI by checking the installed version"
         #r|set -eu
az version > /tmp/az-version.json
grep -q '"azure-cli"' /tmp/az-version.json
|)
   #+nil
   (list *install-docker-cli* "Docker CLI and Buildx by checking their client versions"
         #r|set -eu
docker --version > /tmp/docker-version.txt
grep -Eq 'Docker version [0-9]+\.[0-9]+' /tmp/docker-version.txt
docker buildx version > /tmp/docker-buildx-version.txt
grep -Eq 'github\.com/docker/buildx v[0-9]+\.[0-9]+' /tmp/docker-buildx-version.txt
|)
   #+nil
   (list *install-arm-none-eabi* "Arm GNU bare-metal toolchain by compiling a Cortex-M7 object"
         #r|set -eu
tmpdir="$(mktemp -d /tmp/ai-env-arm-none-eabi.XXXXXX)"
cat > "$tmpdir/test.c" <<'C_EOF'
void Reset_Handler(void) {}
C_EOF
arm-none-eabi-gcc -mcpu=cortex-m7 -mthumb -ffreestanding -c "$tmpdir/test.c" -o "$tmpdir/test.o"
arm-none-eabi-readelf -h "$tmpdir/test.o" > "$tmpdir/readelf.txt"
grep -Eq 'Machine.+ARM' "$tmpdir/readelf.txt"
rm -rf "$tmpdir"
|)
   #+nil
   (list *install-jlink* "SEGGER J-Link command-line tools by checking their pinned version"
         (format nil #r|set -eu
JLinkGDBServerCLExe -version > /tmp/jlink-version.txt
grep -F '~a ' /tmp/jlink-version.txt
command -v JLinkExe >/dev/null
| (jlink-version-code)))
   #+nil
   (list *install-teamcity-cli* "TeamCity CLI by checking the installed version"
         #r|set -eu
teamcity --version > /tmp/teamcity-version.txt
[ -s /tmp/teamcity-version.txt ]
grep -Eq '[0-9]+\.[0-9]+' /tmp/teamcity-version.txt
|)
   #+nil
   (list *install-habit-hooks* "Habit Hooks by checking the CLI help"
         #r|set -eu
habit-hooks --help > /tmp/habit-hooks-help.txt
[ -s /tmp/habit-hooks-help.txt ]
|)
   #+nil
   (list *install-deptry* "Deptry by checking the CLI version"
         #r|set -eu
deptry --version
|)
   #+nil
   (list *install-jscpd* "JSCPD by checking the CLI version"
         #r|set -eu
jscpd --version
|)
   #+nil
   (list *install-archify* "Archify and its headless Chrome runtime"
         #r|set -eu
archify_dir=/root/.agents/skills/archify
test -f "$archify_dir/SKILL.md"
test -f "$archify_dir/bin/archify.mjs"
node "$archify_dir/bin/archify.mjs" doctor
test -x "$ARCHIFY_CHROME"
"$ARCHIFY_CHROME" --headless --no-sandbox --disable-gpu --dump-dom about:blank > /tmp/archify-chrome.html
grep -qi '<html' /tmp/archify-chrome.html
tmpdir="$(mktemp -d /tmp/ai-env-archify.XXXXXX)"
node "$archify_dir/bin/archify.mjs" demo "$tmpdir"
test -s "$tmpdir/archify-demo.html"
rm -rf "$tmpdir"
|)
   ;; FIXME: the C/CUDA/Rust programs below lost their semicolons.
   #+nil
   (list *enable-cuda* "CUDA nvcc compiler by compiling and verifying a test CUDA kernel"
         (format nil "set -eu~%if command -v nvcc >/dev/null 2>&1 ; then~%  nvcc --version~%  tmpdir=\"$(mktemp -d /tmp/ai-env-cuda.XXXXXX)\"~%  cat > \"$tmpdir/test.cu\" <<'CU_EOF'~%~%~%#include <stdio.h>~%~%__global__ void test_kernel(void) {}~%~%int main(void) {~%  test_kernel<<<1, 1>>>()~%  puts(\"cuda-build-ok\")~%  return 0~%}~%~%CU_EOF~%  nvcc \"$tmpdir/test.cu\" -o \"$tmpdir/test\"~%  rm -rf \"$tmpdir\"~%fi"))
   #+nil
   (list *install-gcc* "GCC by compiling and running a tiny C program"
         (format nil "set -eu~%tmpdir=\"$(mktemp -d /tmp/ai-env-gcc.XXXXXX)\"~%cat > \"$tmpdir/test.c\" <<'C_EOF'~%~%~%#include <stdio.h>~%~%int main(void) {~%  puts(\"gcc-ok\")~%  return 0~%}~%~%C_EOF~%gcc \"$tmpdir/test.c\" -o \"$tmpdir/test\"~%\"$tmpdir/test\""))
   #+nil
   (list *install-rust* "Rust by compiling and running a tiny program"
         (format nil "set -eu~%tmpdir=\"$(mktemp -d /tmp/ai-env-rust.XXXXXX)\"~%cat > \"$tmpdir/test.rs\" <<'R_EOF'~%~%~%fn main() {~%  println!(\"rust-ok\")~%}~%~%R_EOF~%rustc \"$tmpdir/test.rs\" -o \"$tmpdir/test\"~%\"$tmpdir/test\""))
   #+nil
   (list (or *install-python* *install-python-libs*) "Python by running a tiny script"
         (format nil "set -eu~%python3 - <<'PY_EOF'~%~%~%print(\"python-ok\")~%~%PY_EOF"))
   #+nil
   (list *install-sbcl* "SBCL by evaluating a simple expression"
         "set -eu
sbcl --non-interactive --eval '(princ (+ 1 2))' --eval '(quit)'")
   #+nil
   (list *install-emacs* "Emacs by opening a file with the configured init"
         (format nil "set -eu~%tmpdir=\"$(mktemp -d /tmp/ai-env-emacs-open.XXXXXX)\"~%cat > \"$tmpdir/open-me\" <<'T_EOF'~%~%~%hello~%~%T_EOF~%cat > \"$tmpdir/check.el\" <<'EMACS_EOF'~%~%~%(find-file \"/tmp/ai-env-emacs-open.XXXXXX/open-me\")~%~%(unless (and buffer-file-name (eq major-mode 'fundamental-mode))~%~%  (error \"Emacs failed to open a plain file\"))~%~%EMACS_EOF~%sed -i \"s#/tmp/ai-env-emacs-open.XXXXXX#$tmpdir#g\" \"$tmpdir/check.el\"~%emacs --batch -l /root/.emacs -l \"$tmpdir/check.el\""))
   #+nil
   (list (and *install-emacs* *install-sbcl*) "Emacs + SLIME by opening and loading a Lisp file"
         #r|set -eu
tmpdir="$(mktemp -d /tmp/ai-env-slime.XXXXXX)"
cat > "$tmpdir/example.lisp" <<'LISP_EOF'
(+ 1 2)
LISP_EOF
cat > "$tmpdir/slime-check.el" <<'SLIME_EOF'
(require 'slime)
(setq inferior-lisp-program "sbcl")
(slime-setup '(slime-repl))
(slime)
(let ((deadline (+ (float-time) 120)))
  (while (and (not (slime-connected-p)) (< (float-time) deadline))
    (sleep-for 0.2))
  (unless (slime-connected-p)
    (error "SLIME connection timed out")))
(find-file "/tmp/ai-env-slime.XXXXXX/example.lisp")
(slime-load-file "/tmp/ai-env-slime.XXXXXX/example.lisp")
(unless (= 3 (slime-eval '(cl:+ 1 2)))
  (error "SLIME evaluation returned the wrong value"))
SLIME_EOF
sed -i "s#/tmp/ai-env-slime.XXXXXX#$tmpdir#g" "$tmpdir/slime-check.el"
emacs --batch -l /root/.emacs -l "$tmpdir/slime-check.el"
|)
   (list *install-kirocrew* "KiroCrew CLI and its chat/gateway commands"
         #r|set -eu
kirocrew --help > /tmp/kirocrew-help.txt
grep -q 'chat' /tmp/kirocrew-help.txt
grep -q 'gateway' /tmp/kirocrew-help.txt
kirocrew chat --help > /tmp/kirocrew-chat-help.txt
grep -q 'Interactive mode' /tmp/kirocrew-chat-help.txt
kirocrew gateway --help > /tmp/kirocrew-gateway-help.txt
grep -q -- '--port' /tmp/kirocrew-gateway-help.txt
|)
   (list *install-kiro-cli* "Kiro CLI ACP command"
         #r|set -eu
kiro-cli acp --help > /tmp/kiro-cli-acp-help.txt
grep -qi 'acp' /tmp/kiro-cli-acp-help.txt
|)))

(defun test-stage ()
  (loop for (enabled description script) in (smoke-tests)
        when enabled
          collect `(comment ,(format nil "Smoke test ~a" description))
          and collect `(run :heredoc ,script)))

;;; ===================================================================
;;; 6. Runner stage
;;; ===================================================================

(defun runner-base ()
  `(,@(stage-header "Stage 2: Insulated Runtime Runner" 69)
    (from ,(base-image) :as runner)
    (env DEBIAN_FRONTEND "noninteractive")
    ,@(when *install-kirocrew*
        `((env KIROCREW_BIND "0.0.0.0"
               KIROCREW_HOME "/root/.kiro/crew-yolo"
               KIROCREW_KIRO_BIN ,(real-path "kiro-cli"))))
    ,@(when *enable-cuda*
        `((comment "Configure NVIDIA Container Toolkit runtime and CUDA development paths")
          (env NVIDIA_VISIBLE_DEVICES "all"
               NVIDIA_DRIVER_CAPABILITIES "compute,utility"
               CUDA_HOME "/usr/local/cuda"
               CUDA_PATH "/usr/local/cuda"
               CUDACXX "/usr/local/cuda/bin/nvcc"
               PATH "/usr/local/cuda/bin:$PATH"
               LD_LIBRARY_PATH "/usr/local/cuda/lib64:$LD_LIBRARY_PATH")))
    (workdir "/workspace")
    ;; The run script supplies the host UID/GID. Keep /root traversable so
    ;; bind-mounted credential directories remain usable by that user.
    (run "chmod 755 /root")))

(defun runner-kirocrew ()
  (when *install-kirocrew*
    `((comment "Copy the signed KiroCrew installation and its managed Python 3.12 runtime")
      ,@(loop for dir in '("/opt/kirocrew-venv" "/opt/kirocrew-venv-current" "/opt/kirocrew-python")
              collect `(copy ,dir ,dir :from builder-kirocrew :link t))
      (copy "/root/.local/bin/kirocrew" ,(bin-path "kirocrew") :from builder-kirocrew :link t :chmod "755")
      ,@(wrap-binary "kirocrew" (kirocrew-wrapper-script (real-path "kirocrew")))
      (env KIROCREW_BIND "0.0.0.0"))))

(defun runner-apt ()
  `((comment "Copy the modern uv binary directly from Astral's official release container")
    ,(uv-copy)
    (env UV_TOOL_BIN_DIR "/usr/local/bin")
    (comment "Install the essential tool belt for agents")
    ,(apt-install (runner-apt-packages))
    (comment "Install component dependencies in separate layers for caching")
    ,@(loop for (enabled . packages) in (dependency-package-groups)
            when enabled collect (apt-install packages))))

(defun runner-quality-tools ()
  "Code-quality CLIs, independent of any mounted project's manifests."
  (append
   (when *install-habit-hooks*
     (uv-tool-install "'habit-hooks[all]'" "Install Habit Hooks with all optional integrations"))
   (when *install-deptry*
     (uv-tool-install "deptry" "Install Deptry as an isolated CLI tool"))
   (when *install-conan*
     (uv-tool-install "conan" "Install Conan as an isolated CLI tool"))
   (when *install-jscpd*
     (npm-global-install "jscpd" "Install JSCPD globally so it is available in every mounted project"))))

(defun runner-archify ()
  (when *install-archify*
    `((comment "Install Archify for Codex and provision Chrome for visual checks")
      (arg ARCHIFY_CHROME_BUILD ,*archify-chrome-build*)
      (run :mount ,*npm-cache-mount*
           (and "npx -y skills add tt-a1i/archify --skill archify --agent codex --global --copy --yes"
                "npx -y @puppeteer/browsers install \"chrome@${ARCHIFY_CHROME_BUILD}\" --path /opt/archify-browser"
                "chrome_path=\"$(find /opt/archify-browser -type f -path '*/chrome-linux*/chrome' -perm -111 -print -quit)\""
                "test -n \"$chrome_path\""
                "ln -s \"$chrome_path\" /usr/local/bin/archify-chrome"))
      (env ARCHIFY_CHROME "/usr/local/bin/archify-chrome"
           ARCHIFY_CHROME_NO_SANDBOX "1"))))

(defun runner-rust ()
  (when *install-rust*
    `((comment "Install rustup and stable Rust toolchain")
      (run (and "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable"
                "chmod -R a+w /root/.rustup"))
      (env PATH "/root/.cargo/bin:$PATH")
      ,@(when *install-difftastic*
          `((comment "Install difftastic syntax-aware diff tool")
            (run :mount ("type=cache,target=/root/.cargo/registry" "type=cache,target=/root/.cargo/git")
                 (and "cargo install difftastic"
                      "ln -sf /root/.cargo/bin/difft /usr/local/bin/difft"))
            (comment "Configure Git to use difftastic as default diff tool")
            (run "git config --global diff.external difft")))
      ,@(when *install-probe-rs*
          `((comment "Install probe-rs")
            (run (and "curl --proto '=https' --tlsv1.2 -LsSf https://github.com/probe-rs/probe-rs/releases/latest/download/probe-rs-tools-installer.sh | sh"
                      "chmod -R a+w /root/.cargo/bin/probe-rs")))))))

(defun runner-python ()
  (when *install-python-libs*
    `((comment "Copy the isolated Python environment")
      (copy "/workspace/.venv" "/workspace/.venv" :from builder-python :link t)
      (env PATH "/workspace/.venv/bin:$PATH"))))

(defun runner-agy ()
  (when *install-agy*
    `((comment "Copy the actual agy CLI tool from the builder's local path to system binaries")
      (copy "/root/.local/bin/agy" ,(bin-path "agy") :from builder-agy :link t :chmod "755")
      ,@(wrap-binary "agy" (exec-wrapper (real-path "agy") "--dangerously-skip-permissions")
                     :comment "Rename the original binary and install a wrapper that skips permissions by default")
      (comment "Add the Antigravity clean environment tweaks to .bashrc")
      (run (and #r|echo 'if [[ -n "$ANTIGRAVITY_AGENT" ]]; then export TERM=dumb; export DEBIAN_FRONTEND=noninteractive; unalias -a; export PS1="\$ "; fi' >> /root/.bashrc|
                #r|echo "alias agy='agy --dangerously-skip-permissions'" >> /root/.bashrc|)))))

(defun runner-codex ()
  (when *install-codex*
    `(,@(npm-global-install "@openai/codex@$(npm view @openai/codex version)"
                            "Install the newest Codex release directly in the runner image")
      ,@(wrap-binary "codex" (exec-wrapper (real-path "codex") "--dangerously-bypass-approvals-and-sandbox --no-daemon")
                     :comment "Rename the original binary and install a wrapper that bypasses approvals and sandboxing by default"))))

(defun runner-copilot ()
  (when *install-copilot*
    `((copy ,(bin-path "copilot") ,(bin-path "copilot") :from builder-copilot :link t :chmod "755")
      ,@(wrap-binary "copilot" (exec-wrapper (real-path "copilot") "--allow-all")
                     :comment "Rename the original binary and install a wrapper that allows all actions by default"))))

(defun runner-claude ()
  (when *install-claude*
    `((copy ,(bin-path "claude") ,(real-path "claude") :from builder-claude :link t :chmod "755")
      (comment "Keep all Claude state (incl. .claude.json and .credentials.json) in one bind-mountable directory.")
      (comment "IS_SANDBOX allows --dangerously-skip-permissions as root; the binary is image-managed, so no self-updates.")
      (env CLAUDE_CONFIG_DIR "/root/.claude"
           IS_SANDBOX "1"
           DISABLE_AUTOUPDATER "1")
      (comment "Install a wrapper that skips permission prompts by default")
      ,@(install-wrapper "claude" (exec-wrapper (real-path "claude") "--dangerously-skip-permissions")))))

(defun runner-kiro-cli ()
  (when *install-kiro-cli*
    `((copy "/root/.local/bin/kiro-cli" ,(bin-path "kiro-cli") :from builder-kiro :link t :chmod "755")
      ,@(wrap-binary "kiro-cli" (kiro-cli-wrapper-script (real-path "kiro-cli"))
                     :comment "Rename the original binary and install a wrapper that skips confirmation for init"))))

(defun runner-teamcity ()
  (when *install-teamcity-cli*
    `((comment "Copy TeamCity CLI from the builder image")
      (copy ,(bin-path "teamcity") ,(bin-path "teamcity") :from builder-teamcity :link t :chmod "755"))))

(defun runner-agent-clis ()
  (let ((forms (append (runner-codex) (runner-copilot) (runner-claude)
                       (runner-kiro-cli) (runner-teamcity))))
    (when forms
      `((comment "Install or copy other AI CLI tools") ,@forms))))

(defun runner-azure-cli ()
  (when *install-azure-cli*
    `((comment "Install Azure CLI from Microsoft's official apt repository")
      ,(apt-run "mkdir -p /etc/apt/keyrings"
                "curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg"
                "chmod go+r /etc/apt/keyrings/microsoft.gpg"
                "arch=\"$(dpkg --print-architecture)\""
                "suite=\"$(. /etc/os-release && printf '%s' \"${UBUNTU_CODENAME:-$VERSION_CODENAME}\")\""
                "repo_suite=\"$suite\""
                "if ! curl -fsI \"https://packages.microsoft.com/repos/azure-cli/dists/${repo_suite}/Release\" >/dev/null; then repo_suite=\"noble\"; fi"
                "printf '%s\\n' 'Types: deb' 'URIs: https://packages.microsoft.com/repos/azure-cli/' \"Suites: ${repo_suite}\" 'Components: main' \"Architectures: ${arch}\" 'Signed-By: /etc/apt/keyrings/microsoft.gpg' > /etc/apt/sources.list.d/azure-cli.sources"
                "apt-get update"
                (apt-get-install '("azure-cli"))))))

(defun runner-docker-cli ()
  (when *install-docker-cli*
    `((comment "Install Docker CLI for an optionally mounted host Docker socket")
      ,(apt-run "install -m 0755 -d /etc/apt/keyrings"
                "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg"
                "chmod a+r /etc/apt/keyrings/docker.gpg"
                "suite=\"$(. /etc/os-release && printf '%s' \"${UBUNTU_CODENAME:-$VERSION_CODENAME}\")\""
                "printf '%s\\n' 'Types: deb' 'URIs: https://download.docker.com/linux/ubuntu' \"Suites: ${suite}\" 'Components: stable' 'Signed-By: /etc/apt/keyrings/docker.gpg' > /etc/apt/sources.list.d/docker.sources"
                "apt-get update"
                (apt-get-install '("docker-ce-cli" "docker-buildx-plugin"))))))

(defun download-and-extract (comment url archive tar-flags path-dir &key curl-options)
  "Download URL to ARCHIVE, unpack it into /opt and prepend PATH-DIR to PATH."
  `((comment ,comment)
    (run (and ,(format nil "curl -fL ~@[~a ~]~a -o ~a" curl-options url archive)
              ,(format nil "tar ~a ~a -C /opt" tar-flags archive)
              ,(format nil "rm ~a" archive)))
    (env PATH ,(format nil "~a:$PATH" path-dir))))

(defun runner-firmware ()
  (append
   (when *install-arm-none-eabi*
     (download-and-extract
      "Install the Arm GNU bare-metal toolchain used by fountain firmware"
      (format nil "https://gitlab.arm.com/api/v4/projects/tooling%2Fgnu-toolchains-for-arm/packages/generic/gnu-toolchain/~a/~a.tar.xz"
              *arm-none-eabi-version* (arm-none-eabi-toolchain))
      "/tmp/arm-none-eabi.tar.xz" "-xJf"
      (format nil "/opt/~a/bin" (arm-none-eabi-toolchain))))
   (when *install-jlink*
     (download-and-extract
      "Install SEGGER J-Link tools (the download accepts SEGGER's license terms)"
      (format nil "https://www.segger.com/downloads/jlink/~a.tgz" (jlink-directory))
      "/tmp/jlink.tgz" "-xzf"
      (format nil "/opt/~a" (jlink-directory))
      :curl-options "--data 'accept_license_agreement=accepted&non_eu_market=true'"))))

(defun runner-quicklisp ()
  (when (and *install-sbcl* *install-quicklisp*)
    `((comment "Download and install Quicklisp")
      (run (and "curl -O https://beta.quicklisp.org/quicklisp.lisp"
                #r|sbcl --non-interactive --load quicklisp.lisp --eval "(quicklisp-quickstart:install)"|
                "rm quicklisp.lisp"))
      (comment "Configure Quicklisp in .sbclrc")
      (copy :heredoc "/root/.sbclrc"
            #r|#-quicklisp
(let ((quicklisp-init (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname))))
  (when (probe-file quicklisp-init)
    (load quicklisp-init)))
|)
      (comment "Pre-create local-projects symlinks (which resolve dynamically when /workspace/src is mounted)")
      (run (and "mkdir -p /root/quicklisp/local-projects"
                ,@(loop for project in *quicklisp-local-projects*
                        collect (format nil "ln -s /workspace/src/~a /root/quicklisp/local-projects/~a"
                                        project project))))
      (comment "Pre-fetch and cache Quicklisp systems and common dependencies")
      (run ,(format nil "sbcl --non-interactive --load /root/quicklisp/setup.lisp~{ --eval '(ql:quickload \"~a\")'~}"
                    *quicklisp-systems*)))))

(defun runner-grok ()
  (when *install-grok*
    `((comment "Install Grok Build from the official x.ai installer")
      (run (and "curl -fsSL https://x.ai/cli/install.sh -o grok-install.sh"
                "bash grok-install.sh"
                "rm grok-install.sh"))
      (comment "Move the installed Grok binaries out of ~/.grok so they survive optional auth volume mounts")
      (run ,(format nil "cp /root/.grok/bin/grok ~a" (real-path "grok")))
      (run ,(format nil "cp /root/.grok/bin/agent ~a" (real-path "agent")))
      (copy :heredoc ,(bin-path "grok") ,(exec-wrapper (real-path "grok") "--always-approve"))
      (copy :heredoc ,(bin-path "agent") ,(exec-wrapper (real-path "agent")))
      (run ,(format nil "chmod +x ~{~a~^ ~}"
                    (list (bin-path "grok") (real-path "grok") (bin-path "agent") (real-path "agent")))))))

(defun runner-muse ()
  (when *install-muse*
    `((comment "Install Meta Muse Code from the official installer")
      (run (and "curl -fsSL https://dev.meta.ai/install.sh | MUSE_INSTALL_DIR=/usr/local/bin bash"
                "command -v muse"))
      (run ,(format nil "cp ~a ~a" (bin-path "muse") (real-path "muse")))
      (copy :heredoc ,(bin-path "muse") ,(exec-wrapper (real-path "muse") "--yolo"))
      (run ,(format nil "chmod +x ~a ~a" (bin-path "muse") (real-path "muse"))))))

(defun runner-devin ()
  (when *install-devin-cli*
    `((comment "Install Devin CLI from the official installer")
      (run "curl -fsSL https://cli.devin.ai/install.sh | XDG_DATA_HOME=/usr/local/share bash || true # tries to run `devin setup` which fails")
      (run ,(format nil "mv /usr/local/share/devin/cli/_versions/current/bin/devin ~a" (real-path "devin")))
      (copy :heredoc ,(bin-path "devin") ,(exec-wrapper (real-path "devin") "--permission-mode bypass"))
      (run ,(format nil "chmod +x ~a ~a" (bin-path "devin") (real-path "devin"))))))

(defun runner-emacs ()
  ;; FIXME: the generated package-install --eval string lacks its closing double quote.
  (when (and *install-sbcl* *install-emacs*)
    `((comment "Pre-install Emacs packages")
      (run ,(format nil "emacs --batch --eval \"(require 'package)\" --eval \"(add-to-list 'package-archives '(\\\"melpa\\\" . \\\"https://melpa.org/packages/\\\"))\" --eval \"(package-initialize)\" --eval \"(package-refresh-contents)\" --eval \"(setq custom-file null-device)\" --eval \"(dolist (pkg '(~{~(~a~)~^ ~})) (setq package-selected-packages nil) (package-install pkg))"
                    *emacs-packages*))
      (comment "Recompile installed Emacs packages with their dependencies available")
      (run #r|emacs --batch --eval "(require 'package)" --eval "(package-initialize)" --eval "(byte-recompile-directory package-user-dir 0 t)"|)
      (comment "Copy the modified .emacs configuration from the build context if present")
      (comment "Note: In real usage, ensure .emacs exists in the build context directory")
      (copy ".emacs" "/root/.emacs" :link t))))

(defun runner-stage ()
  "The final image. The order of the parts is the Docker layer (cache) order."
  (append (runner-base)
          (runner-kirocrew)
          (runner-apt)
          (runner-quality-tools)
          (runner-archify)
          (runner-rust)
          (runner-python)
          (runner-agy)
          (runner-agent-clis)
          (runner-azure-cli)
          (runner-docker-cli)
          (runner-firmware)
          (runner-quicklisp)
          (runner-grok)
          (runner-muse)
          (runner-devin)
          (runner-emacs)
          (when *enable-tests* (test-stage))
          `((comment "Default to launching a bash shell")
            (cmd ("/bin/bash")))))

;;; ===================================================================
;;; 7. Entry point
;;; ===================================================================

(defparameter *ai-env-directory*
  (make-pathname :directory (pathname-directory (or *load-truename* *default-pathname-defaults*)))
  "Directory of this generator; the default Dockerfile is written here.")

(defun generate-ai-env (&optional (output-path (merge-pathnames "Dockerfile" *ai-env-directory*)))
  "Write the Dockerfile for the current configuration to OUTPUT-PATH."
  (write-df output-path
            `(toplevel
               ,@(builder-stages)
               ,@(runner-stage))
            t))

(let ((path (generate-ai-env)))
  (format t "Generated Dockerfile in ~a successfully.~%" (directory-namestring path)))
