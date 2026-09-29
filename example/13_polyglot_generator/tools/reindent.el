;;; reindent.el --- batch re-indentation of Common Lisp files
;;; Usage: emacs --batch -Q -l tools/reindent.el FILE...
;;; Every FILE is re-indented in place with common-lisp-indent-function.

(require 'cl-indent)
(setq-default indent-tabs-mode nil)

;; Indentation of the macros of this project and of the libraries it uses
;; (number = count of distinguished arguments before the body).
(dolist (spec '((test . 1) (def-suite . 1) (defreadtable . 1) (defsystem . 1)
                (define-node . 2) (define-pass . 1) (define-surface-form . 2)
                (define-intrinsic . 2) (define-dsl-macro . 2) (match . 1)
                (ematch . 1) (with-block . 1) (with-indent . 1)
                (define-backend-method . 2) (define-spec . 1)
                (with-backend . 1) (with-emit-context . 1) (defmodule . 1)))
  (put (car spec) 'common-lisp-indent-function (cdr spec)))

(defun pg-reindent-file (file)
  (with-current-buffer (find-file-noselect file)
    (lisp-mode)
    (setq-local lisp-indent-function #'common-lisp-indent-function)
    (setq-local indent-tabs-mode nil)
    (indent-region (point-min) (point-max))
    (delete-trailing-whitespace)
    (save-buffer)
    (kill-buffer)))

(dolist (f command-line-args-left)
  (pg-reindent-file f))
(setq command-line-args-left nil)
