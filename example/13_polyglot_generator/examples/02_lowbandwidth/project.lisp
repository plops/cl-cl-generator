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
;;; Project intrinsic: the DSL has no int->int casts and length->i64,
;;; so u32 dimensions need an explicit widening (used by blit).
;;; ------------------------------------------------------------------

(define-intrinsic to-i64 ((x :integer)) :i64
  (:rust "$x as i64" :result-op :cast))

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

;;; Library name for the bin split (Cargo derives it from the package
;;; name lbw-client-pg by replacing - with _).
(defparameter *lib-name* "lbw_client_pg")

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
;;; scene: client model of the remote screen (RGBA canvas + text items).
;;; Fixed 640x640. Pure logic (blit, hud) in the DSL; Event/Link are
;;; appended enums (see *append-to*), matching code is raw.
;;; NOTE: Event lives here (not in net) so scene stays self-contained
;;; and testable without the network thread (differs from source7).
;;; ------------------------------------------------------------------

;;; NOTE: methods (blit, pixel, ...) are not module items; their
;;; visibility follows the struct. Only items are exported here.
(defmodule scene (:export scene scene-new hud-text)
  (defstruct scene
    (canvas (vec :u8))
    (texts (vec (rs::type "lbw_common::TextItem")))
    (dirty :bool true)
    (link (rs::type "Link"))
    (tiles :u32 0)
    (tile-bytes :u64 0)

    (defmethod blit ((s :inout) x y w h rgba)
      "Copy a w*h RGBA box at (x, y). Garbage is ignored, never panics."
      (declare (type :u32 x y w h) (type (vec :u8) rgba))
      ;; w/h clamped first: the products below cannot overflow u32 then.
      ;; NOTE: (> cast len), not (< len cast): `x as i64 < (...)` does
      ;; not parse (rustc reads `<` after an `as` type as generics).
      (when (or (> w 640) (> h 640)
                (> (+ x w) 640) (> (+ y h) 640)
                (> (to-i64 (* w h 4)) (length rgba)))
        (return))
      (dotimes (row h)
        (dotimes (k (* w 4))
          ;; dst byte = ((row+y) * 640 + (col+x)) * 4 + k (pixels first!)
          (setf (aref (dot s canvas) (+ (* (+ (* (+ y row) 640) x) 4) k))
                (aref rgba (+ (* row (* w 4)) k)))))
      (setf (dot s dirty) true))

    (defmethod pixel ((s :in) x y)
      "Canvas color at (x, y) as [r g b] (tests/debug)."
      (declare (type :u32 x y) (values (rs::type "[u8; 3]")))
      (rs::raw "{ let i = (_y as usize * 640 + _x as usize) * 4; [self.canvas[i], self.canvas[i + 1], self.canvas[i + 2]] }"))

    (defmethod clear-texts ((s :inout))
      "Drop all text items."
      (rs::raw "self.texts.clear();"))

    (defmethod push-text ((s :inout) ti)
      "Append one text item."
      (declare (type (rs::type "lbw_common::TextItem") ti) (mode :sink ti))
      (rs::raw "self.texts.push(_ti);"))

    (defmethod apply-event ((s :inout) e)
      "Apply a network event to the scene."
      (declare (type (rs::type "Event") e) (mode :sink e))
      (rs::raw "match _e {
    Event::Connected => {
        self.link = Link::Up;
    }
    Event::Disconnected(_why) => {
        if !matches!(self.link, Link::Down(_)) {
            self.link = Link::Down(_why);
        }
    }
    Event::ClearText => {
        self.clear_texts();
    }
    Event::AddText(_t) => {
        self.push_text(_t);
    }
    Event::Tile {
        x,
        y,
        w,
        h,
        rgba,
        bytes,
    } => {
        self.blit(x as u32, y as u32, w, h, &rgba);
        self.tiles += 1;
        self.tile_bytes += bytes as u64;
    }
}")))

  (defun scene-new ()
    "Fresh 640x640 scene (dark background), like source7 Scene::new."
    (declare (values scene))
    (rs::raw "Scene {
    canvas: [24, 24, 32, 255].repeat(640 * 640),
    texts: Vec::new(),
    dirty: true,
    link: Link::Connecting,
    tiles: 0,
    tile_bytes: 0,
}"))

  (defun hud-text (link n-texts tiles tile-bytes)
    "One-line status for the HUD (link text comes from app's match)."
    (declare (type :string link)
             (type :i64 n-texts tiles)
             (type :u64 tile-bytes)
             (values :string))
    (format-string "{} | {} Texte | {} Kacheln ({} B) | F1 HUD"
                   link n-texts tiles tile-bytes)))

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

(defparameter *append-to*
  '(("src/scene.rs" . "/// Connection state for the HUD.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Link {
    Connecting,
    Up,
    Down(String),
}

/// Events the network thread hands to the UI (produced by net,
/// consumed by apply_event; lives here so scene is self-contained).
#[derive(Debug)]
pub enum Event {
    Connected,
    Disconnected(String),
    ClearText,
    AddText(lbw_common::TextItem),
    /// Decoded AV1 box (RGBA8, w times h).
    Tile {
        x: u16,
        y: u16,
        w: u32,
        h: u32,
        rgba: Vec<u8>,
        bytes: usize,
    },
}
")))

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
")
    ("tests/scene.rs" . "use lbw_client_pg::scene::{hud_text, scene_new, Event, Link};
use lbw_common::{Rect, TextItem};

fn item(text: &str) -> TextItem {
    TextItem {
        rect: Rect::new(0, 0, 10, 10),
        fg: [0; 3],
        bg: [255; 3],
        text: text.into(),
    }
}

#[test]
fn clear_and_add_texts() {
    let mut s = scene_new();
    s.apply_event(Event::AddText(item(\"a\")));
    s.apply_event(Event::AddText(item(\"b\")));
    assert_eq!(s.texts.len(), 2);
    s.apply_event(Event::ClearText);
    assert!(s.texts.is_empty());
    s.apply_event(Event::AddText(item(\"c\")));
    assert_eq!(s.texts[0].text, \"c\");
}

#[test]
fn blit_places_tile_and_ignores_garbage() {
    let mut s = scene_new();
    s.dirty = false;
    s.blit(64, 0, 64, 64, &[200, 100, 50, 255].repeat(64 * 64));
    assert!(s.dirty);
    assert_eq!(s.pixel(64, 0), [200, 100, 50]);
    assert_eq!(s.pixel(127, 63), [200, 100, 50]);
    assert_eq!(s.pixel(63, 0), [24, 24, 32]);
    // Outside and too short: ignored.
    s.blit(640, 0, 64, 64, &vec![0; 64 * 64 * 4]);
    s.blit(0, 0, 64, 64, &[0; 10]);
    assert_eq!(s.pixel(0, 0), [24, 24, 32]);
}

#[test]
fn blit_handles_arbitrary_box_sizes() {
    let mut s = scene_new();
    s.blit(100, 100, 16, 92, &[10, 20, 30, 255].repeat(16 * 92));
    assert_eq!(s.pixel(100, 100), [10, 20, 30]);
    assert_eq!(s.pixel(115, 191), [10, 20, 30]);
    assert_eq!(s.pixel(116, 100), [24, 24, 32]);
    assert_eq!(s.pixel(100, 192), [24, 24, 32]);
}

#[test]
fn link_state_follows_events() {
    let mut s = scene_new();
    assert_eq!(s.link, Link::Connecting);
    s.apply_event(Event::Connected);
    assert_eq!(s.link, Link::Up);
    s.apply_event(Event::Disconnected(\"x\".into()));
    assert_eq!(s.link, Link::Down(\"x\".into()));
    s.apply_event(Event::Disconnected(\"y\".into()));
    assert_eq!(s.link, Link::Down(\"x\".into()), \"first disconnect wins\");
}

#[test]
fn tile_updates_counters_and_canvas() {
    let mut s = scene_new();
    s.apply_event(Event::Tile {
        x: 0,
        y: 0,
        w: 2,
        h: 2,
        rgba: vec![1, 2, 3, 255, 4, 5, 6, 255, 7, 8, 9, 255, 10, 11, 12, 255],
        bytes: 99,
    });
    assert_eq!((s.tiles, s.tile_bytes), (1, 99));
    assert_eq!(s.pixel(0, 0), [1, 2, 3]);
    assert_eq!(s.pixel(1, 1), [10, 11, 12]);
}

#[test]
fn hud_line() {
    let h = hud_text(\"online\", 3, 7, 100);
    assert!(h.contains(\"online\"), \"{h}\");
    assert!(h.contains(\"3 Texte\"), \"{h}\");
    assert!(h.contains(\"7 Kacheln\"), \"{h}\");
    assert!(h.contains(\"100 B\"), \"{h}\");
}
")))

(defproject lbw-client-pg (:modules config scene app) (:entry app))
