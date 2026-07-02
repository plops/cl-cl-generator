(eval-when (:compile-toplevel :execute :load-toplevel)
  (let ((current-dir (make-pathname :directory (pathname-directory *load-pathname*))))
    (push (merge-pathnames "../../" current-dir) asdf:*central-registry*))
  (ql:quickload :cl-dockerfile-generator))

(in-package :cl-dockerfile-generator)

;; Define parameters to avoid boilerplate
(defparameter *base-image* "ubuntu:26.04")

;; Helper function to avoid duplicating the COPY statement for Astral's uv
(defun uv-copy-stage ()
  `(copy "/uv" "/uvx" "/bin/" :from "ghcr.io/astral-sh/uv:latest"))

(let ((agy-env-code
        `(toplevel
           (comment "=====================================================================")
           (comment "Stage 1: Build Environment & Cache Dependency Compilation")
           (comment "=====================================================================")
           (from ,*base-image* :as builder)
           (env DEBIAN_FRONTEND "noninteractive")
           (env UV_COMPILE_BYTECODE "1")
           (env UV_LINK_MODE "copy")
           
           (comment "Grab the modern uv binary directly from Astral's official release container")
           ,(uv-copy-stage)
           
           (comment "Install base toolsets required to fetch the CLI and compile Python extensions")
           (run (and "apt-get update"
                     "apt-get install -y --no-install-recommends python3-pip python3-venv python3-dev build-essential ca-certificates curl"
                     "rm -rf /var/lib/apt/lists/*"))
           (workdir "/workspace")
           
           (comment "1. Install the programmatic Python SDK using uv")
           (run :mount "type=cache,target=/root/.cache/uv"
                (and "uv venv .venv"
                     "uv pip install --no-cache-dir google-antigravity"))
           
           (comment "2. Safely download, decompress, and run the installation script")
           (run (and "curl -fsSL --compressed https://antigravity.google/cli/install.sh -o install.sh"
                     "chmod +x install.sh"
                     "./install.sh"))
           
           (comment "=====================================================================")
           (comment "Stage 2: Insulated Runtime Runner")
           (comment "=====================================================================")
           (from ,*base-image* :as runner)
           (env DEBIAN_FRONTEND "noninteractive")
           (workdir "/workspace")
           
           (comment "Copy the modern uv binary directly from Astral's official release container")
           ,(uv-copy-stage)
           
           (comment "Install the essential tool belt for agy agents (full Python, GCC compilation tools, Git, Curl, SBCL, Emacs, rlwrap)")
           (run (and "apt-get update"
                     "apt-get install -y --no-install-recommends python3-full build-essential gcc git curl ca-certificates jq sbcl emacs-nox rlwrap"
                     "rm -rf /var/lib/apt/lists/*"))
           
           (comment "Copy the isolated Python environment")
           (copy "/workspace/.venv" "/workspace/.venv" :from builder)
           
           (comment "Copy the actual agy CLI tool from the builder's local path to system binaries")
           (copy "/root/.local/bin/agy" "/usr/local/bin/agy" :from builder)
           
           (comment "Download and install Quicklisp")
           (run (and "curl -O https://beta.quicklisp.org/quicklisp.lisp"
                     "sbcl --non-interactive --load quicklisp.lisp --eval \"(quicklisp-quickstart:install)\""
                     "rm quicklisp.lisp"))
           
           (comment "Append Quicklisp configuration to .sbclrc")
           (run (and "echo '#-quicklisp' >> /root/.sbclrc"
                     "echo '(let ((quicklisp-init (merge-pathnames \"quicklisp/setup.lisp\" (user-homedir-pathname))))' >> /root/.sbclrc"
                     "echo '  (when (probe-file quicklisp-init)' >> /root/.sbclrc"
                     "echo '    (load quicklisp-init)))' >> /root/.sbclrc"))
           
           (comment "Pre-create local-projects symlinks (which resolve dynamically when /workspace/src is mounted)")
           (run (and "mkdir -p /root/quicklisp/local-projects"
                     "ln -s /workspace/src/cl-py-generator /root/quicklisp/local-projects/cl-py-generator"
                     "ln -s /workspace/src/cl-cpp-generator2 /root/quicklisp/local-projects/cl-cpp-generator2"
                     "ln -s /workspace/src/cl-rust-generator /root/quicklisp/local-projects/cl-rust-generator"))
           
           (comment "Pre-fetch and cache Quicklisp systems and common dependencies")
           (run "sbcl --non-interactive --load /root/quicklisp/setup.lisp --eval '(ql:quickload \"quicklisp-slime-helper\")' --eval '(ql:quickload \"alexandria\")' --eval '(ql:quickload \"jonathan\")' --eval '(ql:quickload \"external-program\")' --eval '(ql:quickload \"cl-ppcre\")'")
           
           (comment "Pre-install Emacs packages")
           (run "emacs --batch --eval \"(require 'package)\" --eval \"(add-to-list 'package-archives '(\\\"melpa\\\" . \\\"https://melpa.org/packages/\\\"))\" --eval \"(package-initialize)\" --eval \"(package-refresh-contents)\" --eval \"(dolist (pkg '(cmake-mode company gptel magit markdown-mode orderless paredit slime yaml-mode use-package)) (package-install pkg))\"")
           
           (comment "Copy the modified .emacs configuration from the build context")
           (copy ".emacs" "/root/.emacs")
           
           (comment "Add the Antigravity clean environment tweaks and dangerous CLI alias to .bashrc")
           (run (and "echo 'if [[ -n \"$ANTIGRAVITY_AGENT\" ]]; then export TERM=dumb; export DEBIAN_FRONTEND=noninteractive; unalias -a; export PS1=\"\\$ \"; fi' >> /root/.bashrc"
                     "echo \"alias agy='agy --dangerously-skip-permissions'\" >> /root/.bashrc"))
           
           (env PATH "/workspace/.venv/bin:$PATH")
           (volume "/workspace/src")
           
           (comment "Default to launching a bash shell where 'agy' works out of the box")
           (cmd ("/bin/bash")))))

  (let ((current-dir (make-pathname :directory (pathname-directory *load-pathname*))))
    (write-df (merge-pathnames "Dockerfile" current-dir) agy-env-code t)
    (format t "Generated Dockerfile in ~a successfully.~%" current-dir)))
