;;;; project.lisp --- lbw-client-pg: low-bandwidth remote desktop client.
;;;;
;;;; Port of cl-rust-generator's source7_mvp/client to the polyglot
;;;; generator. Rust output only: see gen.lisp. Layout:
;;;;   tables ................ shared input tables (+key-table+, +btn-table+)
;;;;   config, scene, ... ..... DSL modules (signatures + pure logic in DSL,
;;;;                            threads/unsafe/enums as rs::raw or append below)
;;;;   *cargo-toml* ........... full Cargo.toml (replaces the generated one)
;;;;   *append-to* ............ rust appended to generated files (enums, Drop)
;;;;   *extra-files* ........... examples/ and tests/ written from templates
;;;;   (defproject ...) ........ module list + entry
;;;;
;;;; Conventions for rs::raw (verified by probe, see plan.md section 4):
;;;;   (1) double colon: rs::raw / rs::type
;;;;   (2) raw-only PARAMS are spelled _name in raw
;;;;   (3) raw-only LOCALS are spelled name (declare raw-mutated ones in raw)
;;;;   (4) :sink params need (move x) at DSL call sites
;;;;   (5) (vec T) params become &[T]

(in-package :polyglot-user)
(in-dsl)

;;; ------------------------------------------------------------------
;;; Tables: single source for client input mapping (source7 05_app.rs).
;;; +key-table+: rows (server-name minifb-key). Server names are the
;;; protocol strings; minifb-key is a minifb::Key variant.
;;; ------------------------------------------------------------------

(defparameter +key-table+
  '(("Enter" Enter) ("Esc" Escape) ("Tab" Tab)
    ("Backspace" Backspace) ("Delete" Delete)
    ("Up" Up) ("Down" Down) ("Left" Left) ("Right" Right)
    ("Home" Home) ("End" End)
    ("PageUp" PageUp) ("PageDown" PageDown)
    ("Shift" LeftShift) ("Shift" RightShift)
    ("Control" LeftCtrl) ("Control" RightCtrl)
    ("Alt" LeftAlt) ("Alt" RightAlt)))

;;; +btn-table+: rows (minifb-Button X11-number).
(defparameter +btn-table+
  '((Left 1) (Middle 2) (Right 3)))

;;; ------------------------------------------------------------------
;;; *cargo-toml*: replaces source01/rust/Cargo.toml (the generator
;;; emits a dependency-free manifest, we need minifb/font8x8/rav1d
;;; plus the temporary lbw-common path dependency).
;;; ------------------------------------------------------------------

(defparameter *cargo-toml*
  "[package]
name = \"lbw-client-pg\"
version = \"0.1.0\"
edition = \"2024\"
authors = [\"Wol Pumba <wolpumba@gmail.com>\"]
license = \"MIT\"

[dependencies]
lbw-common = { path = \"../../../../../../../cl-rust-generator/examples/29_lowbandwidth/source7_mvp/common\" }
minifb = { version = \"0.29\", default-features = false, features = [\"x11\"] }
font8x8 = \"0.3\"
rav1d = { version = \"1.1.0\", default-features = false, features = [\"bitdepth_8\"] }

[dev-dependencies]
# Test helper encodes 64x64 tiles itself (settings mirrored from
# source7 server/src/05_av1.rs), so tests need no lbw-server dep.
rav1e = { version = \"0.8.1\", default-features = false, features = [\"threading\"] }

# Debug builds: optimize dependencies (rav1d/rav1e are ~20x slower
# without it), like the source7 workspace does.
[profile.dev.package.\"*\"]
opt-level = 3
")

;;; ------------------------------------------------------------------
;;; config: command line of the client (hand-parsed, no clap: one flag).
;;; parse-args returns nil on error (main prints usage + exits 2);
;;; --help prints usage and exits 0 directly.
;;; ------------------------------------------------------------------

(defmodule config (:export config default-connect usage-text parse-args)
  (defstruct config (connect :string ""))

  (defun default-connect ()
    "Default server address (typical end of an ssh -L forward)."
    (declare (values :string))
    "127.0.0.1:7878")

  (defun usage-text ()
    "CLI usage, printed on --help and on parse errors."
    (declare (values :string))
    "lbw-client-pg: minimal low-bandwidth remote desktop client (640x640)
usage: lbw-client-pg [--connect ADDR]")

  (defun parse-args (args)
    "Parse argv (argv[0] first). Nil on error; --help exits(0)."
    (declare (type (vec :string) args) (values (optional config)))
    (let ((connect (default-connect))
          (bad false)
          (i 1))
      (while (< i (length args))
        ;; No let-binding of the arg: borrowing String needs explicit
        ;; clone, direct comparison is zero-copy.
        (cond ((= (aref args i) "--connect")
               (incf i)
               (if (< i (length args))
                   (setf connect (clone (aref args i)))
                   (setf bad true)))
              ((or (= (aref args i) "--help") (= (aref args i) "-h"))
               (print-line (usage-text))
               (rs::raw "std::process::exit(0);"))
              (t (setf bad true)))
        (incf i))
      (if bad nil (some (make-config :connect (move connect)))))))

;;; ------------------------------------------------------------------
;;; app: entry module. T1: parse config and print it (T5: run client).
;;; ------------------------------------------------------------------

(defmodule app (:import config)
  (defun main ()
    (let ((args (rs::raw "std::env::args().collect::<Vec<String>>()")))
      (declare (type (vec :string) args))
      (if-let (cfg (parse-args args))
          (print-line (dot cfg connect))
        (progn
          (print-line (usage-text))
          (rs::raw "std::process::exit(2);"))))))

;;; ------------------------------------------------------------------
;;; *append-to*: alist (generated-file . rust-text) appended by gen.lisp.
;;; T1: nothing (enums/Drop arrive with net/av1 in T3-T4).
;;; ------------------------------------------------------------------

(defparameter *append-to* nil)

;;; ------------------------------------------------------------------
;;; *extra-files*: alist (path . content) written by gen.lisp below
;;; source01/rust/ (examples/ and tests/ live here as templates).
;;; ------------------------------------------------------------------

(defparameter *extra-files*
  '(("rustfmt.toml" . "# Style 2021: the generator formats with rustfmt --edition 2021.
style_edition = \"2021\"
")
    ("tests/config.rs" . "use lbw_client_pg::config::{default_connect, parse_args, usage_text};

fn argv(words: &[&str]) -> Vec<String> {
    words.iter().map(|s| s.to_string()).collect()
}

#[test]
fn defaults_and_options() {
    let c = parse_args(&argv(&[\"lbw-client-pg\"])).expect(\"defaults\");
    assert_eq!(c.connect, \"127.0.0.1:7878\");
    assert_eq!(default_connect(), \"127.0.0.1:7878\");
    let c = parse_args(&argv(&[\"lbw-client-pg\", \"--connect\", \"h:1\"])).expect(\"opt\");
    assert_eq!(c.connect, \"h:1\");
}

#[test]
fn errors_are_none() {
    assert!(parse_args(&argv(&[\"lbw-client-pg\", \"--bogus\"])).is_none());
    assert!(parse_args(&argv(&[\"lbw-client-pg\", \"--connect\"])).is_none());
}

#[test]
fn usage_mentions_flag() {
    assert!(usage_text().contains(\"--connect\"));
}
")))

(defproject lbw-client-pg (:modules config app) (:entry app))
