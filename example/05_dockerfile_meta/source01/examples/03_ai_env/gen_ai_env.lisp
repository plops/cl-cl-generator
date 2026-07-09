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
;; Toggle AI CLI tools
(defparameter *install-agy* t)
(defparameter *install-codex* t)
(defparameter *install-copilot* t)
(defparameter *install-kiro-cli* t)

;; Toggle Rust support
(defparameter *install-rust* t)
(defparameter *rust-cache-volume* t)


;; Helper function to copy Astral's uv
(defun uv-copy-stage ()
  `(copy "/uv" "/uvx" "/bin/" :from "ghcr.io/astral-sh/uv:latest"))

(defun builder-stage ()
  (when (or *install-python-libs* *install-agy*)
    `((comment "=====================================================================")
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
      
      ,@(when *install-python-libs*
          `((comment "1. Install the programmatic Python SDK using uv")
            (run :mount "type=cache,target=/root/.cache/uv"
                 (and "uv venv .venv"
                      ,(format nil "uv pip install --no-cache-dir ~{~a~^ ~}" *python-libs*)))))
      
      ,@(when *install-agy*
          `((comment "2. Safely download, decompress, and run the installation script")
            (run (and "curl -fsSL --compressed https://antigravity.google/cli/install.sh -o install.sh"
                      "chmod +x install.sh"
                      "./install.sh")))))))

(defun runner-stage ()
  (let ((apt-packages '("curl" "ca-certificates" "git" "jq")))
    (when (or *install-gcc* *install-rust*)
      (setf apt-packages (append apt-packages '("build-essential" "gcc"))))
    (when *install-sbcl*
      (setf apt-packages (append apt-packages '("sbcl" "rlwrap"))))
    (when *install-emacs*
      (setf apt-packages (append apt-packages '("emacs-nox"))))
    (when (or *install-python* *install-python-libs*)
      (setf apt-packages (append apt-packages '("python3-full"))))
    
    `((comment "=====================================================================")
      (comment "Stage 2: Insulated Runtime Runner")
      (comment "=====================================================================")
      (from ,*base-image* :as runner)
      (env DEBIAN_FRONTEND "noninteractive")
      (workdir "/workspace")
      
      (comment "Copy the modern uv binary directly from Astral's official release container")
      ,(uv-copy-stage)
      
      (comment "Install the essential tool belt for agents")
      (run (and "apt-get update"
                ,(format nil "apt-get install -y --no-install-recommends ~{~a~^ ~}" apt-packages)
                "rm -rf /var/lib/apt/lists/*"))
      
      ;; Install Rustup and the stable Rust toolchain if enabled
      ,@(when *install-rust*
          `((comment "Install rustup and stable Rust toolchain")
            (run (and "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable"
                      "chmod -R a+w /root/.rustup"))
            (env PATH "/root/.cargo/bin:$PATH")))
      
      ;; 1. Copy Python virtualenv if python libs are enabled
      ,@(when *install-python-libs*
          `((comment "Copy the isolated Python environment")
            (copy "/workspace/.venv" "/workspace/.venv" :from builder)
            (env PATH "/workspace/.venv/bin:$PATH")))
      
      ;; 2. Copy agy if enabled
      ,@(when *install-agy*
          `((comment "Copy the actual agy CLI tool from the builder's local path to system binaries")
            (copy "/root/.local/bin/agy" "/usr/local/bin/agy" :from builder)
            (comment "Add the Antigravity clean environment tweaks and dangerous CLI alias to .bashrc")
            (run (and #r#echo 'if [[ -n "$ANTIGRAVITY_AGENT" ]]; then export TERM=dumb; export DEBIAN_FRONTEND=noninteractive; unalias -a; export PS1="\$ "; fi' >> /root/.bashrc#
                      #r#echo "alias agy='agy --dangerously-skip-permissions'" >> /root/.bashrc#))))
      
      ;; 3. Copy other CLI tools if enabled
      ,@(when (or *install-codex* *install-copilot* *install-kiro-cli*)
          (let ((copy-instructions '())
                (chmod-commands '()))
            (when *install-codex*
              (push `(copy "bin/codex" "/usr/local/bin/codex") copy-instructions)
              (push "chmod +x /usr/local/bin/codex" chmod-commands))
            (when *install-copilot*
              (push `(copy "bin/copilot" "/usr/local/bin/copilot") copy-instructions)
              (push "chmod +x /usr/local/bin/copilot" chmod-commands))
            (when *install-kiro-cli*
              (push `(copy "bin/kiro-cli" "/usr/local/bin/kiro-cli") copy-instructions)
              (push "chmod +x /usr/local/bin/kiro-cli" chmod-commands))
            `((comment "Copy other AI CLI tools from the build context")
              ,@(reverse copy-instructions)
              (comment "Ensure executive permissions for copied CLI tools")
              (run (and ,@(reverse chmod-commands))))))
      
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
      
      ;; 5. Setup Emacs if Emacs is enabled
      ,@(when (and *install-sbcl* *install-emacs*)
          `((comment "Pre-install Emacs packages")
            (run #r#emacs --batch --eval "(require 'package)" --eval "(add-to-list 'package-archives '(\"melpa\" . \"https://melpa.org/packages/\"))" --eval "(package-initialize)" --eval "(package-refresh-contents)" --eval "(dolist (pkg '(cmake-mode company gptel magit markdown-mode orderless paredit slime yaml-mode use-package)) (package-install pkg))"#)
            
            (comment "Copy the modified .emacs configuration from the build context if present")
            (comment "Note: In real usage, ensure .emacs exists in the build context directory")
            (copy ".emacs" "/root/.emacs")))
      
      ;; 6. Define Volumes for sharing configs, logins, caches, and source files
      (volume ,(let ((vols '("/workspace/src" "/root/.config" "/root/.cache" "/root/.gemini")))
                 (if (and *install-rust* *rust-cache-volume*)
                     (append vols '("/root/.cargo"))
                     vols)))
      
      (comment "Default to launching a bash shell")
      (cmd ("/bin/bash")))))

(let ((all-code
        `(toplevel
           ,@(builder-stage)
           ,@(runner-stage))))
  (let ((current-dir (make-pathname :directory (pathname-directory *load-pathname*))))
    (write-df (merge-pathnames "Dockerfile" current-dir) all-code t)
    (format t "Generated Dockerfile in ~a successfully.~%" current-dir)))
