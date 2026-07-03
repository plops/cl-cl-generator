;; Minimal Emacs configuration for Common Lisp / SLIME

(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(package-initialize)

;; Configure SLIME with SBCL
(setq inferior-lisp-program "sbcl")
