(eval-when (:compile-toplevel :execute :load-toplevel)
  (let ((current-dir (make-pathname :directory (pathname-directory *load-pathname*))))
    (push (merge-pathnames "../../" current-dir) asdf:*central-registry*))
  (ql:quickload :cl-dockerfile-generator)
  (setf (readtable-case *readtable*) :invert))

(in-package :cl-dockerfile-generator)

;; Define parameters to toggle features
(defparameter *base-image* "ubuntu:26.04")

;; Enable or disable components to build minimal images
(defparameter *install-gcc* t)
(defparameter *install-sbcl* t)
(defparameter *install-emacs* t)
(defparameter *install-python* t)
(defparameter *install-python-libs* t) ; google-antigravity SDK
(defparameter *install-docker-cli* t
  "Install the Docker CLI for use with an optionally mounted host Docker socket.")
(defparameter *enable-tests* t)
(defparameter *python-libs* `(google-antigravity
			      azure-cognitiveservices-speech
			      openai
			      matplotlib
			      numpy
			      pandas
			      scipy
			      tqdm
			      xarray
			      loguru
			      nbdev
			      requests
			      ruff
			      scikit-learn
			      seaborn))
;; Extra Ubuntu packages that are handy in an interactive shell.
;; Add or remove entries here to customize the final image.
(defparameter *ubuntu-packages*
  '("less"
    "file"
    "findutils"
    "tree"
    "man-db"
    "procps"
    "psmisc"
    "iproute2"
    "iputils-ping"
    "dnsutils"
    "ripgrep"
    "fd-find"
    "yq"
    "picocom"
    "usbutils"
    "libusb-1.0-0-dev"
    "lsof"
    "strace"
    "moreutils"
    "tmux"
    "shellcheck"
    "fzf"
    "cmake"
    "ninja-build"
    "bat"
    "git-lfs"
    "openssh-client"
    "dos2unix"
    "parallel"
    "unzip"
    "zip"
    "xz-utils"
    "rsync"))
;; Toggle AI CLI tools
(defparameter *install-agy* t)
(defparameter *install-codex* t)
(defparameter *install-copilot* t)
(defparameter *install-kiro-cli* t)
(defparameter *install-azure-cli* t)
(defparameter *install-teamcity-cli* t)
(defparameter *install-grok* nil)

;; Toggle Rust support
(defparameter *install-rust* t)
(defparameter *rust-cache-volume* t)
(defparameter *install-difftastic* t
  "Requires *install-rust* to be true.")


;; Helper function to copy Astral's uv
(defun uv-copy-stage ()
  `(copy "/uv" "/uvx" "/bin/" :from "ghcr.io/astral-sh/uv:latest"))

(defun make-bash-script (&rest lines)
  (format nil "#!/usr/bin/env bash~%set -euo pipefail~%~{~a~^~%~}" lines))

(defun agent-wrapper-script (real-binary default-flag)
  (make-bash-script
   (format nil "case \" $* \" in~%  *\" ~a \"*) exec ~a \"$@\" ;;~%  *) exec ~a ~a \"$@\" ;;~%esac"
           default-flag real-binary real-binary default-flag)))

(defun kiro-wrapper-script (real-binary)
  (make-bash-script
   "subcommand=\"${1:-}\""
   (format nil "case \"$subcommand\" in~%  init)~%    for arg in \"$@\"; do~%      if [[ $arg == --force ]]; then~%        exec ~a --v3 \"$@\"~%      fi~%    done~%    exec ~a --v3 init --force \"${@:2}\"~%    ;;~%  whoami|settings|version|help|--help|-h|--version)~%    exec ~a \"$@\"~%    ;;~%  chat)~%    exec ~a chat --v3 --trust-all-tools \"${@:2}\"~%    ;;~%  *)~%    exec ~a chat --v3 --trust-all-tools \"$@\"~%    ;;~%esac"
           real-binary real-binary real-binary real-binary real-binary)))

(defun grok-wrapper-script (real-binary)
  (make-bash-script
   (format nil "case \" $* \" in~%  *\" --always-approve \"*) exec ~a \"$@\" ;;~%  *) exec ~a --always-approve \"$@\" ;;~%esac"
           real-binary real-binary)))

(defparameter *smoke-tests*
  `((*install-codex* "Codex by running the CLI and asserting it matches the latest npm release"
                     #r(set -eu
codex --version > /tmp/codex-version.txt
grep -Eq '[0-9]+\.[0-9]+\.[0-9]+' /tmp/codex-version.txt
installed_version="$(node -p "require(require('path').join(process.argv[1], '@openai/codex/package.json')).version" "$(npm root -g)" | tr -d '[:space:]')"
latest_version="$(npm view @openai/codex version | tr -d '[:space:]')"
[ -n "$installed_version" ]
[ "$installed_version" = "$latest_version" ]
))
    (*install-kiro-cli* "kiro-cli by invoking the wrapped CLI and helpers"
                        #r(set -eu
kiro-cli --help > /tmp/kiro-cli-help.txt
[ -s /tmp/kiro-cli-help.txt ]
grep -qi "kiro" /tmp/kiro-cli-help.txt

kiro-cli-chat --help > /tmp/kiro-cli-chat-help.txt
[ -s /tmp/kiro-cli-chat-help.txt ]
grep -qi "kiro" /tmp/kiro-cli-chat-help.txt

kiro-cli-term --help > /tmp/kiro-cli-term-help.txt
[ -s /tmp/kiro-cli-term-help.txt ]
grep -qi "kiro" /tmp/kiro-cli-term-help.txt
))
    (*install-grok* "Grok Build by checking the CLI version"
                    #r(set -eu
grok --version
agent --version
))
    (*install-azure-cli* "Azure CLI by checking the installed version"
                        #r(set -eu
az version > /tmp/az-version.json
grep -q '"azure-cli"' /tmp/az-version.json
))
    (*install-docker-cli* "Docker CLI and Buildx by checking their client versions"
                          #r(set -eu
docker --version > /tmp/docker-version.txt
grep -Eq 'Docker version [0-9]+\.[0-9]+' /tmp/docker-version.txt
docker buildx version > /tmp/docker-buildx-version.txt
grep -Eq 'github\.com/docker/buildx v[0-9]+\.[0-9]+' /tmp/docker-buildx-version.txt
))
    (*install-teamcity-cli* "TeamCity CLI by checking the installed version"
                            #r(set -eu
teamcity --version > /tmp/teamcity-version.txt
[ -s /tmp/teamcity-version.txt ]
grep -Eq '[0-9]+\.[0-9]+' /tmp/teamcity-version.txt
))
    (*install-gcc* "GCC by compiling and running a tiny C program"
                   #r(set -eu
tmpdir="$(mktemp -d /tmp/ai-env-gcc.XXXXXX)"
cat > "$tmpdir/test.c" <<'C_EOF'
#include <stdio.h>

int main(void) {
  puts("gcc-ok");
  return 0;
}
C_EOF
gcc "$tmpdir/test.c" -o "$tmpdir/test"
"$tmpdir/test"
))
    (*install-rust* "Rust by compiling and running a tiny program"
                    #r(set -eu
tmpdir="$(mktemp -d /tmp/ai-env-rust.XXXXXX)"
cat > "$tmpdir/test.rs" <<'R_EOF'
fn main() {
    println!("rust-ok");
}
R_EOF
rustc "$tmpdir/test.rs" -o "$tmpdir/test"
"$tmpdir/test"
))
    ((or *install-python* *install-python-libs*) "Python by running a tiny script"
                                                 #r(set -eu
python3 - <<'PY_EOF'
print("python-ok")
PY_EOF
))
    (*install-sbcl* "SBCL by evaluating a simple expression"
                    #r(set -eu
sbcl --non-interactive --eval '(princ (+ 1 2))' --eval '(quit)'
))
    (*install-emacs* "Emacs by opening a file with the configured init"
                     #r(set -eu
tmpdir="$(mktemp -d /tmp/ai-env-emacs-open.XXXXXX)"
cat > "$tmpdir/open-me" <<'T_EOF'
hello
T_EOF
cat > "$tmpdir/check.el" <<'EMACS_EOF'
(find-file "/tmp/ai-env-emacs-open.XXXXXX/open-me")
(unless (and buffer-file-name (eq major-mode 'fundamental-mode))
  (error "Emacs failed to open a plain file"))
EMACS_EOF
sed -i "s#/tmp/ai-env-emacs-open.XXXXXX#$tmpdir#g" "$tmpdir/check.el"
emacs --batch -l /root/.emacs -l "$tmpdir/check.el"
))
    ((and *install-emacs* *install-sbcl*) "Emacs + SLIME by opening and loading a Lisp file"
                                          #r(set -eu
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
))))

(defun test-stage ()
  (loop for (cond-expr desc script) in *smoke-tests*
        when (eval cond-expr)
        collect `(comment ,(format nil "Smoke test ~a" desc))
        and collect `(run :heredoc ,script)))

(defun builder-python-stage ()
  (when *install-python-libs*
    `((comment "====================================================================" )
      (comment "Stage: Python Dependencies (runs in parallel with other builders)")
      (comment "====================================================================" )
      (from ,*base-image* :as builder-python)
      (env DEBIAN_FRONTEND "noninteractive")
      (env UV_COMPILE_BYTECODE "1")
      (env UV_LINK_MODE "copy")
      (comment "Grab the modern uv binary directly from Astral's official release container")
      ,(uv-copy-stage)
      (comment "Install base toolsets required to compile Python extensions")
      (run :mount ("type=cache,target=/var/cache/apt,sharing=locked" "type=cache,target=/var/lib/apt/lists,sharing=locked")
           (and "apt-get update"
                "apt-get install -y --no-install-recommends python3-pip python3-venv python3-dev build-essential ca-certificates"))
      (workdir "/workspace")
      (comment "Install the programmatic Python SDK using uv")
      (run :mount "type=cache,target=/root/.cache/uv"
           (and "uv venv .venv"
                ,(format nil "uv pip install ~{~a~^ ~}" *python-libs*))))))

(defun builder-agy-stage ()
  (when *install-agy*
    `((comment "====================================================================" )
      (comment "Stage: Antigravity CLI Download")
      (comment "====================================================================" )
      (from ,*base-image* :as builder-agy)
      (env DEBIAN_FRONTEND "noninteractive")
      (run :mount ("type=cache,target=/var/cache/apt,sharing=locked" "type=cache,target=/var/lib/apt/lists,sharing=locked")
           (and "apt-get update"
                "apt-get install -y --no-install-recommends ca-certificates curl"))
      (workdir "/workspace")
      (comment "Download, decompress, and run the Antigravity installation script")
      (run (and "curl -fsSL --compressed https://antigravity.google/cli/install.sh -o install.sh"
                "chmod +x install.sh"
                "./install.sh")))))

(defun builder-copilot-stage ()
  (when *install-copilot*
    `((comment "====================================================================" )
      (comment "Stage: GitHub Copilot CLI Download")
      (comment "====================================================================" )
      (from ,*base-image* :as builder-copilot)
      (env DEBIAN_FRONTEND "noninteractive")
      (run :mount ("type=cache,target=/var/cache/apt,sharing=locked" "type=cache,target=/var/lib/apt/lists,sharing=locked")
           (and "apt-get update"
                "apt-get install -y --no-install-recommends ca-certificates curl"))
      (workdir "/workspace")
      (comment "Download and install GitHub Copilot CLI from the official installer")
      (run (and "curl -fsSL https://gh.io/copilot-install -o copilot-install.sh"
                "PREFIX=/usr/local VERSION=latest bash copilot-install.sh"
                "rm copilot-install.sh")))))

(defun builder-kiro-stage ()
  (when *install-kiro-cli*
    `((comment "====================================================================" )
      (comment "Stage: Kiro CLI Download")
      (comment "====================================================================" )
      (from ,*base-image* :as builder-kiro)
      (env DEBIAN_FRONTEND "noninteractive")
      (run :mount ("type=cache,target=/var/cache/apt,sharing=locked" "type=cache,target=/var/lib/apt/lists,sharing=locked")
           (and "apt-get update"
                "apt-get install -y --no-install-recommends ca-certificates curl unzip"))
      (workdir "/workspace")
      (comment "Install kiro-cli from Amazon using the official zip package")
      (run (and "curl -fsSL https://desktop-release.q.us-east-1.amazonaws.com/latest/kirocli-x86_64-linux.zip -o /tmp/kirocli.zip"
                "unzip -q /tmp/kirocli.zip -d /tmp/kirocli-extracted"
                "chmod +x /tmp/kirocli-extracted/kirocli/install.sh"
                "KIRO_CLI_SKIP_SETUP=1 /tmp/kirocli-extracted/kirocli/install.sh"
                "rm -rf /tmp/kirocli.zip /tmp/kirocli-extracted")))))

(defun builder-teamcity-stage ()
  (when *install-teamcity-cli*
    `((comment "====================================================================" )
      (comment "Stage: TeamCity CLI Download")
      (comment "====================================================================" )
      (from ,*base-image* :as builder-teamcity)
      (env DEBIAN_FRONTEND "noninteractive")
      (run :mount ("type=cache,target=/var/cache/apt,sharing=locked" "type=cache,target=/var/lib/apt/lists,sharing=locked")
           (and "apt-get update"
                "apt-get install -y --no-install-recommends ca-certificates curl"))
      (workdir "/workspace")
      (comment "Install TeamCity CLI from the official JetBrains installer")
      (run (and "curl -fsSL https://jb.gg/tc/install -o /tmp/teamcity-install.sh"
                "bash /tmp/teamcity-install.sh"
                "rm -f /tmp/teamcity-install.sh"
                "command -v teamcity >/dev/null")))))

(defparameter *dependency-packages*
  `(((or *install-gcc* *install-rust*) "build-essential" "gcc")
    (*install-sbcl* "sbcl" "rlwrap")
    (*install-emacs* "emacs-nox")
    ((or *install-python* *install-python-libs*) "python3-full")
    (*install-codex* "nodejs" "npm")
    ((or *install-azure-cli* *install-docker-cli*) "gnupg")
    (*install-azure-cli* "lsb-release")))

(defun runner-stage ()
  `((comment "=====================================================================")
    (comment "Stage 2: Insulated Runtime Runner")
    (comment "=====================================================================")
    (from ,*base-image* :as runner)
    (env DEBIAN_FRONTEND "noninteractive")
    (workdir "/workspace")
    
    (comment "Copy the modern uv binary directly from Astral's official release container")
    ,(uv-copy-stage)
    
    (comment "Install the essential tool belt for agents")
    (run :mount ("type=cache,target=/var/cache/apt,sharing=locked" "type=cache,target=/var/lib/apt/lists,sharing=locked")
         (and "apt-get update"
              ,(format nil "apt-get install -y --no-install-recommends ~{~a~^ ~}" (append '("curl" "ca-certificates" "git" "jq") *ubuntu-packages*))))
    
    (comment "Install component dependencies in separate layers for caching")
    ,@(loop for (cond-expr . pkgs) in *dependency-packages*
            when (eval cond-expr)
            collect `(run :mount ("type=cache,target=/var/cache/apt,sharing=locked" "type=cache,target=/var/lib/apt/lists,sharing=locked")
                          ,(format nil "apt-get install -y --no-install-recommends ~{~a~^ ~}" pkgs)))
    
    ;; Install Rustup and the stable Rust toolchain if enabled
    ,@(when *install-rust*
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
                (run "git config --global diff.external difft")))))
    
    ;; 1. Copy Python virtualenv if python libs are enabled
    ,@(when *install-python-libs*
        `((comment "Copy the isolated Python environment")
          (copy "/workspace/.venv" "/workspace/.venv" :from builder-python :link t)
          (env PATH "/workspace/.venv/bin:$PATH")))
    
    ;; 2. Copy agy if enabled
    ,@(when *install-agy*
        `((comment "Copy the actual agy CLI tool from the builder's local path to system binaries")
          (copy "/root/.local/bin/agy" "/usr/local/bin/agy" :from builder-agy :link t :chmod "755")
          (comment "Rename the original binary and install a wrapper that skips permissions by default")
          (run "mv /usr/local/bin/agy /usr/local/bin/agy.real")
          (copy :heredoc "/usr/local/bin/agy"
                ,(agent-wrapper-script "/usr/local/bin/agy.real" "--dangerously-skip-permissions"))
          (run "chmod +x /usr/local/bin/agy")
          (comment "Add the Antigravity clean environment tweaks to .bashrc")
          (run (and #r#echo 'if [[ -n "$ANTIGRAVITY_AGENT" ]]; then export TERM=dumb; export DEBIAN_FRONTEND=noninteractive; unalias -a; export PS1="\$ "; fi' >> /root/.bashrc#
                    #r#echo "alias agy='agy --dangerously-skip-permissions'" >> /root/.bashrc#))))
    
    ;; 3. Install and wrap other CLI tools if enabled
    ,@(when (or *install-codex* *install-copilot* *install-kiro-cli* *install-teamcity-cli*)
        `((comment "Install or copy other AI CLI tools")
          ,@(when *install-codex*
             `((comment "Install the newest Codex release directly in the runner image")
               (run :mount "type=cache,target=/root/.npm"
                    "npm install -g @openai/codex@$(npm view @openai/codex version)")
               (comment "Rename the original binary and install a wrapper that bypasses approvals and sandboxing by default")
               (run "mv /usr/local/bin/codex /usr/local/bin/codex.real")
               (copy :heredoc "/usr/local/bin/codex"
                     ,(agent-wrapper-script "/usr/local/bin/codex.real" "--dangerously-bypass-approvals-and-sandbox"))
               (run "chmod +x /usr/local/bin/codex")))
          ,@(when *install-copilot*
             `((copy "/usr/local/bin/copilot" "/usr/local/bin/copilot" :from builder-copilot :link t :chmod "755")
               (comment "Rename the original binary and install a wrapper that allows all actions by default")
               (run "mv /usr/local/bin/copilot /usr/local/bin/copilot.real")
               (copy :heredoc "/usr/local/bin/copilot"
                     ,(agent-wrapper-script "/usr/local/bin/copilot.real" "--allow-all"))
               (run "chmod +x /usr/local/bin/copilot")))
          ,@(when *install-kiro-cli*
              `((copy "/root/.local/bin/kiro-cli" "/usr/local/bin/kiro-cli" :from builder-kiro :link t :chmod "755")
                (copy "/root/.local/bin/kiro-cli-chat" "/usr/local/bin/kiro-cli-chat" :from builder-kiro :link t :chmod "755")
                (copy "/root/.local/bin/kiro-cli-term" "/usr/local/bin/kiro-cli-term" :from builder-kiro :link t :chmod "755")
                (comment "Rename the original binary and install a wrapper that skips confirmation for init")
                (run "mv /usr/local/bin/kiro-cli /usr/local/bin/kiro-cli.real")
                (copy :heredoc "/usr/local/bin/kiro-cli"
                      ,(kiro-wrapper-script "/usr/local/bin/kiro-cli.real"))
                (run "chmod +x /usr/local/bin/kiro-cli")))
          ,@(when *install-teamcity-cli*
              `((comment "Copy TeamCity CLI from the builder image")
                (copy "/usr/local/bin/teamcity" "/usr/local/bin/teamcity" :from builder-teamcity :link t :chmod "755")))))

    ,@(when *install-azure-cli*
        `((comment "Install Azure CLI from Microsoft's official apt repository")
          (run :mount ("type=cache,target=/var/cache/apt,sharing=locked" "type=cache,target=/var/lib/apt/lists,sharing=locked")
               (and "mkdir -p /etc/apt/keyrings"
                    "curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg"
                    "chmod go+r /etc/apt/keyrings/microsoft.gpg"
                    "arch=\"$(dpkg --print-architecture)\""
                    "suite=\"$(. /etc/os-release && printf '%s' \"${UBUNTU_CODENAME:-$VERSION_CODENAME}\")\""
                    "repo_suite=\"$suite\""
                    "if ! curl -fsI \"https://packages.microsoft.com/repos/azure-cli/dists/${repo_suite}/Release\" >/dev/null; then repo_suite=\"noble\"; fi"
                    "printf '%s\\n' 'Types: deb' 'URIs: https://packages.microsoft.com/repos/azure-cli/' \"Suites: ${repo_suite}\" 'Components: main' \"Architectures: ${arch}\" 'Signed-By: /etc/apt/keyrings/microsoft.gpg' > /etc/apt/sources.list.d/azure-cli.sources"
                    "apt-get update"
                    "apt-get install -y --no-install-recommends azure-cli"))))

    ,@(when *install-docker-cli*
        `((comment "Install Docker CLI for an optionally mounted host Docker socket")
          (run :mount ("type=cache,target=/var/cache/apt,sharing=locked" "type=cache,target=/var/lib/apt/lists,sharing=locked")
               (and "install -m 0755 -d /etc/apt/keyrings"
                    "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg"
                    "chmod a+r /etc/apt/keyrings/docker.gpg"
                    "suite=\"$(. /etc/os-release && printf '%s' \"${UBUNTU_CODENAME:-$VERSION_CODENAME}\")\""
                    "printf '%s\\n' 'Types: deb' 'URIs: https://download.docker.com/linux/ubuntu' \"Suites: ${suite}\" 'Components: stable' 'Signed-By: /etc/apt/keyrings/docker.gpg' > /etc/apt/sources.list.d/docker.sources"
                    "apt-get update"
                    "apt-get install -y --no-install-recommends docker-ce-cli docker-buildx-plugin"))))

    ;; 4. Setup Quicklisp and Lisp dependencies if SBCL is enabled
    ,@(when *install-sbcl*
        `((comment "Download and install Quicklisp")
          (run (and "curl -O https://beta.quicklisp.org/quicklisp.lisp"
                    #r#sbcl --non-interactive --load quicklisp.lisp --eval "(quicklisp-quickstart:install)"#
                    "rm quicklisp.lisp"))
          
          (comment "Configure Quicklisp in .sbclrc")
          (copy :heredoc "/root/.sbclrc"
                #r(#-quicklisp
 (let ((quicklisp-init (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname))))
   (when (probe-file quicklisp-init)
     (load quicklisp-init)))
 ))
          
          (comment "Pre-create local-projects symlinks (which resolve dynamically when /workspace/src is mounted)")
          (run (and "mkdir -p /root/quicklisp/local-projects"
                    "ln -s /workspace/src/cl-py-generator /root/quicklisp/local-projects/cl-py-generator"
                    "ln -s /workspace/src/cl-cpp-generator2 /root/quicklisp/local-projects/cl-cpp-generator2"
                    "ln -s /workspace/src/cl-rust-generator /root/quicklisp/local-projects/cl-rust-generator"))
          
          (comment "Pre-fetch and cache Quicklisp systems and common dependencies")
          (run #r#sbcl --non-interactive --load /root/quicklisp/setup.lisp --eval '(ql:quickload "quicklisp-slime-helper")' --eval '(ql:quickload "alexandria")' --eval '(ql:quickload "jonathan")' --eval '(ql:quickload "external-program")' --eval '(ql:quickload "cl-ppcre")'#)))

    ,@(when *install-grok*
        `((comment "Install Grok Build from the official x.ai installer")
          (run (and "curl -fsSL https://x.ai/cli/install.sh -o grok-install.sh"
                   "bash grok-install.sh"
                   "rm grok-install.sh"))
          (comment "Move the installed Grok binaries out of ~/.grok so they survive optional auth volume mounts")
          (run "cp /root/.grok/bin/grok /usr/local/bin/grok.real")
          (run "cp /root/.grok/bin/agent /usr/local/bin/agent.real")
          (copy :heredoc "/usr/local/bin/grok"
                ,(grok-wrapper-script "/usr/local/bin/grok.real"))
          (copy :heredoc "/usr/local/bin/agent"
                #r(#!/usr/bin/env bash
set -euo pipefail
exec /usr/local/bin/agent.real "$@"
))
          (run "chmod +x /usr/local/bin/grok /usr/local/bin/grok.real /usr/local/bin/agent /usr/local/bin/agent.real")))

    ;; 6. Setup Emacs if Emacs is enabled
    ,@(when (and *install-sbcl* *install-emacs*)
        `((comment "Pre-install Emacs packages")
          (run #r#emacs --batch --eval "(require 'package)" --eval "(add-to-list 'package-archives '(\"melpa\" . \"https://melpa.org/packages/\"))" --eval "(package-initialize)" --eval "(package-refresh-contents)" --eval "(dolist (pkg '(compat cmake-mode company gptel magit markdown-mode orderless paredit slime yaml-mode use-package)) (package-install pkg))"#)
          (comment "Recompile installed Emacs packages with their dependencies available")
          (run #r#emacs --batch --eval "(require 'package)" --eval "(package-initialize)" --eval "(byte-recompile-directory package-user-dir 0 t)"#)
          (comment "Copy the modified .emacs configuration from the build context if present")
          (comment "Note: In real usage, ensure .emacs exists in the build context directory")
          (copy ".emacs" "/root/.emacs" :link t)))

    ,@(when *enable-tests*
        (test-stage))
    
    ;; 7. Define Volumes for sharing configs, logins, caches, and source files
    (volume ,(let ((vols '("/workspace/src" "/root/.config" "/root/.config/tc" "/root/.cache" "/root/.gemini" "/root/.grok" "/root/.codex" "/root/.azure")))
               (if (and *install-rust* *rust-cache-volume*)
                   (append vols '("/root/.cargo"))
                   vols)))
    
    (comment "Default to launching a bash shell")
    (cmd ("/bin/bash"))))

(let ((all-code
        `(toplevel
           ,@(builder-python-stage)
           ,@(builder-agy-stage)
           ,@(builder-copilot-stage)
           ,@(builder-kiro-stage)
           ,@(builder-teamcity-stage)
           ,@(runner-stage))))
  (let ((current-dir (make-pathname :directory (pathname-directory *load-pathname*))))
    (write-df (merge-pathnames "Dockerfile" current-dir) all-code t)
    (format t "Generated Dockerfile in ~a successfully.~%" current-dir)))
