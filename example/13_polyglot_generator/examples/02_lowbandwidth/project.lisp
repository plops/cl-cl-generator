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
;;; av1: AV1 decoder (rav1d) for still-picture tiles. Structs and
;;; signatures in the DSL, bodies raw (unsafe is fenced here, like in
;;; source7). Drop + use lines are appended (see *append-to*).
;;; ------------------------------------------------------------------

(defmodule av1 (:export decoder rgba decoder-new)
  (defconst +eagain+ :i32 -11)

  (defstruct rgba
    (w :u32 0) (h :u32 0) (data (vec :u8)))

  (defstruct decoder
    (ctx (rs::type "Option<Dav1dContext>"))

    (defmethod decode ((d :inout) obu)
      "Decode one tile (raw OBUs of a still picture) to RGBA8."
      (declare (type (vec :u8) obu)
               (values (rs::type "Result<Rgba, String>")))
      ;; _obu: raw-only param (rule 2); other locals are raw-owned.
      (rs::raw "if _obu.is_empty() {
    return Err(\"leere Kachel\".into());
}
// Dav1dContext is a Copy handle (raw Arc pointer).
let ctx = self.ctx;
let mut data = Dav1dData::default();
// SAFETY: data is valid to write; the buffer holds _obu.len() bytes.
unsafe {
    let p = dav1d_data_create(Some(NonNull::from(&mut data)), _obu.len());
    if p.is_null() {
        return Err(\"dav1d_data_create\".into());
    }
    std::ptr::copy_nonoverlapping(_obu.as_ptr(), p, _obu.len());
}
let mut pic = Dav1dPicture::default();
let mut got = false;
// Send until everything is consumed, fetching pictures in between.
for _ in 0..16 {
    if data.sz > 0 {
        // SAFETY: ctx comes from dav1d_open; data is valid.
        let r = unsafe { dav1d_send_data(ctx, Some(NonNull::from(&mut data))) };
        if r.0 != 0 && r.0 != EAGAIN {
            // SAFETY: data is valid.
            unsafe { dav1d_data_unref(Some(NonNull::from(&mut data))) };
            return Err(format!(\"dav1d_send_data: {}\", r.0));
        }
    }
    // SAFETY: ctx valid, pic writable.
    let r = unsafe { dav1d_get_picture(ctx, Some(NonNull::from(&mut pic))) };
    if r.0 == 0 {
        got = true;
        break;
    }
    if r.0 != EAGAIN {
        // SAFETY: data is valid.
        unsafe { dav1d_data_unref(Some(NonNull::from(&mut data))) };
        return Err(format!(\"dav1d_get_picture: {}\", r.0));
    }
    if data.sz == 0 {
        break;
    }
}
// SAFETY: data is valid (maybe already empty).
unsafe { dav1d_data_unref(Some(NonNull::from(&mut data))) };
if !got {
    return Err(\"kein Bild dekodiert\".into());
}
let out = picture_to_rgba(&pic);
// SAFETY: pic was filled by dav1d_get_picture.
unsafe { dav1d_picture_unref(Some(NonNull::from(&mut pic))) };
out")))

  (defun decoder-new ()
    "Open rav1d (1 thread is enough for 640x640)."
    (declare (values (rs::type "Result<Decoder, String>")))
    (rs::raw "{
    let mut s = std::mem::MaybeUninit::<Dav1dSettings>::uninit();
    // SAFETY: s is valid to write; initialized afterwards.
    let mut s = unsafe {
        dav1d_default_settings(NonNull::new(s.as_mut_ptr()).unwrap());
        s.assume_init()
    };
    s.n_threads = 1;
    s.max_frame_delay = 1;
    let mut ctx: Option<Dav1dContext> = None;
    // SAFETY: pointers to local, valid values.
    let r = unsafe { dav1d_open(Some(NonNull::from(&mut ctx)), Some(NonNull::from(&mut s))) };
    if r.0 != 0 || ctx.is_none() {
        return Err(format!(\"dav1d_open: {}\", r.0));
    }
    Ok(Decoder { ctx })
}"))

  (defun picture-to-rgba (pic)
    "Convert a decoded dav1d picture to RGBA8 (private helper)."
    (declare (type (rs::type "Dav1dPicture") pic)
             (values (rs::type "Result<Rgba, String>")))
    ;; _pic: raw-only param (rule 2); other locals are raw-owned.
    (rs::raw "{
    let (w, h) = (_pic.p.w as usize, _pic.p.h as usize);
    if _pic.p.bpc != 8 || _pic.p.layout != DAV1D_PIXEL_LAYOUT_I420 {
        return Err(format!(
            \"nicht unterstützt: bpc {} layout {}\",
            _pic.p.bpc, _pic.p.layout
        ));
    }
    let (ys, cs) = (_pic.stride[0] as usize, _pic.stride[1] as usize);
    let (ch, cw) = (h.div_ceil(2), w.div_ceil(2));
    let plane = |i: usize, len: usize| -> Result<&[u8], String> {
        let p = _pic.data[i].ok_or(\"fehlende Ebene\")?;
        // SAFETY: dav1d guarantees stride-times-rows valid bytes per plane.
        Ok(unsafe { std::slice::from_raw_parts(p.as_ptr() as *const u8, len) })
    };
    let y = plane(0, ys * (h - 1) + w)?;
    let u = plane(1, cs * (ch - 1) + cw)?;
    let v = plane(2, cs * (ch - 1) + cw)?;
    let mut data = vec![0u8; w * h * 4];
    lbw_common::yuv::yuv420_to_rgba(y, ys, u, v, cs, w, h, &mut data);
    Ok(Rgba {
        w: w as u32,
        h: h as u32,
        data,
    })
}")))

;;; ------------------------------------------------------------------
;;; net: connection to the server with automatic reconnect. A network
;;; thread connects (backoff 0.5s to 5s), sends Hello, reads frames,
;;; decodes AV1 tiles and hands events to the UI. Struct and signatures
;;; in the DSL, bodies raw (threads/channels). Drop + use lines are
;;; appended (see *append-to*); short type names resolve through them.
;;; ------------------------------------------------------------------

(defmodule net (:export net net-connect)
  (defstruct net
    (events (rs::type "Receiver<Event>"))
    (out (rs::type "Sender<ClientMsg>"))
    (stop (rs::type "Arc<AtomicBool>"))

    (defmethod send ((n :in) m)
      "Send a message (lost while disconnected)."
      (declare (type (rs::type "ClientMsg") m) (mode :sink m))
      (rs::raw "let _ = self.out.send(_m);")))

  (defun net-connect (addr)
    "Connect to ADDR (reconnect runs in the background)."
    (declare (type :string addr) (values net))
    (rs::raw "let (ev_tx, events) = channel();
let (out, out_rx) = channel();
let stop = Arc::new(AtomicBool::new(false));
thread::spawn({
    let addr = _addr.to_owned();
    let stop = stop.clone();
    move || run_loop(addr, ev_tx, out_rx, stop)
});
Net { events, out, stop }"))

  (defun run-loop (addr ev out stop)
    "Network thread: connect with backoff, run sessions until stopped."
    (declare (type :string addr) (mode :sink addr)
             (type (rs::type "Sender<Event>") ev) (mode :sink ev)
             (type (rs::type "Receiver<ClientMsg>") out) (mode :sink out)
             (type (rs::type "Arc<AtomicBool>") stop) (mode :sink stop))
    (rs::raw "let mut decoder = match decoder_new() {
    Ok(d) => d,
    Err(e) => {
        let _ = _ev.send(Event::Disconnected(format!(\"rav1d: {e}\")));
        return;
    }
};
let mut backoff = Duration::from_millis(500);
while !_stop.load(Ordering::Relaxed) {
    match TcpStream::connect(_addr.as_str()) {
        Ok(s) => {
            backoff = Duration::from_millis(500);
            session_loop(s, &_ev, &_out, &_stop, &mut decoder);
            if _stop.load(Ordering::Relaxed) {
                break;
            }
            let _ = _ev.send(Event::Disconnected(\"getrennt\".into()));
        }
        Err(e) => {
            let _ = _ev.send(Event::Disconnected(format!(\"kein Server ({e})\")));
        }
    }
    // Backoff in slices so drop reacts fast.
    let steps = backoff.as_millis().div_ceil(100);
    for _ in 0..steps {
        if _stop.load(Ordering::Relaxed) {
            return;
        }
        thread::sleep(Duration::from_millis(100));
    }
    backoff = (backoff * 2).min(Duration::from_secs(5));
}"))

  (defun session-loop (s ev out stop dec)
    "One TCP session: hello, input flush, frame pump."
    (declare (type (rs::type "TcpStream") s) (mode :sink s)
             (type (rs::type "Sender<Event>") ev)
             (type (rs::type "Receiver<ClientMsg>") out)
             (type (rs::type "Arc<AtomicBool>") stop)
             (type (rs::type "Decoder") dec) (mode :inout dec))
    (rs::raw "if _s.set_read_timeout(Some(Duration::from_millis(50))).is_err() {
    return;
}
let mut rd = match _s.try_clone() {
    Ok(r) => r,
    Err(_) => return,
};
let mut wr = _s;
if write_msg(&mut wr, &ClientMsg::Hello { version: PROTO_VERSION }).is_err() {
    return;
}
let mut fr = FrameReader::new();
loop {
    if _stop.load(Ordering::Relaxed) {
        return;
    }
    while let Ok(m) = _out.try_recv() {
        if write_msg(&mut wr, &m).is_err() {
            return;
        }
    }
    match fr.read(&mut rd) {
        Ok(Read1::Frame(b)) => match decode_msg::<ServerMsg>(&b) {
            Ok(ServerMsg::Hello) => {
                let _ = _ev.send(Event::Connected);
            }
            Ok(ServerMsg::ClearText) => {
                let _ = _ev.send(Event::ClearText);
            }
            Ok(ServerMsg::AddText(t)) => {
                let _ = _ev.send(Event::AddText(t));
            }
            Ok(ServerMsg::Tile { x, y, data }) => match _dec.decode(&data) {
                Ok(rgba) => {
                    let _ = _ev.send(Event::Tile {
                        x,
                        y,
                        w: rgba.w,
                        h: rgba.h,
                        rgba: rgba.data,
                        bytes: data.len(),
                    });
                }
                Err(e) => eprintln!(\"[net] AV1: {e}\"),
            },
            Err(e) => {
                eprintln!(\"[net] Protokoll: {e}\");
                return;
            }
        },
        Ok(Read1::Idle) => {}
        Err(_) => return,
    }
}")))

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
")
    ("src/av1.rs" . "use rav1d::include::dav1d::data::Dav1dData;
use rav1d::include::dav1d::dav1d::{Dav1dContext, Dav1dSettings};
use rav1d::include::dav1d::headers::DAV1D_PIXEL_LAYOUT_I420;
use rav1d::include::dav1d::picture::Dav1dPicture;
use rav1d::src::lib::{
    dav1d_close, dav1d_data_create, dav1d_data_unref, dav1d_default_settings, dav1d_get_picture,
    dav1d_open, dav1d_picture_unref, dav1d_send_data,
};
use std::ptr::NonNull;

impl Drop for Decoder {
    fn drop(&mut self) {
        // SAFETY: ctx comes from dav1d_open and is closed exactly once here.
        unsafe { dav1d_close(Some(NonNull::from(&mut self.ctx))) };
    }
}
")
    ("src/net.rs" . "use crate::av1::{decoder_new, Decoder};
use crate::scene::Event;
use lbw_common::framing::{decode_msg, write_msg, FrameReader, Read1};
use lbw_common::{ClientMsg, ServerMsg, PROTO_VERSION};
use std::net::TcpStream;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

impl Drop for Net {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
    }
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
")
    ("tests/av1.rs" . "use lbw_client_pg::av1::decoder_new;

#[test]
fn garbage_is_an_error_not_a_crash() {
    let mut d = decoder_new().expect(\"rav1d open\");
    assert!(d.decode(&[]).is_err());
    assert!(d.decode(&[0x12, 0x00, 0xff, 0xff, 0x01]).is_err());
}
")
    ("tests/loopback.rs" . "//! Loopback: net against a stub server (hello, text, real AV1 tile,
//! teardown + reconnect). No display, no models.

use std::net::TcpListener;
use std::time::{Duration, Instant};

use lbw_client_pg::net::{net_connect, Net};
use lbw_client_pg::scene::Event;
use lbw_common::framing::{write_msg, FrameReader};
use lbw_common::{ClientMsg, Rect, ServerMsg, TextItem};

/// AV1 tile encoder for tests. Settings mirrored from the source7
/// server (server/src/05_av1.rs) so the loopback needs no lbw-server
/// dev-dependency; keep the two in sync when the server changes.
fn encode_rgb(rgb: &[u8], w: usize, h: usize, quantizer: usize) -> Result<Vec<u8>, String> {
    use lbw_common::yuv::rgb_to_yuv420;
    use rav1e::color::{ChromaSampling, PixelRange};
    use rav1e::prelude::*;
    if w < 16 || h < 16 || !w.is_multiple_of(2) || !h.is_multiple_of(2) {
        return Err(format!(\"bad box {w}x{h}\"));
    }
    let yuv = rgb_to_yuv420(rgb, w, h);
    let mut enc = EncoderConfig::with_speed_preset(10);
    enc.width = w;
    enc.height = h;
    enc.bit_depth = 8;
    enc.chroma_sampling = ChromaSampling::Cs420;
    enc.pixel_range = PixelRange::Full;
    enc.still_picture = true;
    enc.low_latency = true;
    enc.quantizer = quantizer.min(255);
    enc.min_quantizer = quantizer.min(255) as u8;
    enc.max_key_frame_interval = 1;
    let cfg = Config::new().with_encoder_config(enc).with_threads(4);
    let mut ctx: Context<u8> = cfg.new_context().map_err(|e| format!(\"rav1e: {e:?}\"))?;
    let mut frame = ctx.new_frame();
    frame.planes[0].copy_from_raw_u8(&yuv.y, w, 1);
    frame.planes[1].copy_from_raw_u8(&yuv.u, yuv.cw(), 1);
    frame.planes[2].copy_from_raw_u8(&yuv.v, yuv.cw(), 1);
    ctx.send_frame(frame)
        .map_err(|e| format!(\"send_frame: {e:?}\"))?;
    ctx.flush();
    let mut out = Vec::new();
    loop {
        match ctx.receive_packet() {
            Ok(pkt) => out.extend_from_slice(&pkt.data),
            Err(EncoderStatus::Encoded) => {}
            Err(EncoderStatus::LimitReached) => break,
            Err(e) => return Err(format!(\"receive_packet: {e:?}\")),
        }
    }
    if out.is_empty() {
        return Err(\"rav1e produced no packet\".into());
    }
    Ok(out)
}

fn item() -> TextItem {
    TextItem {
        rect: Rect::new(8, 8, 32, 16),
        fg: [0; 3],
        bg: [255; 3],
        text: \"hi\".into(),
    }
}

/// Stub: read hello, send hello + text + tile, then read `expect`
/// client messages and return them. Closing drops the client to EOF.
fn stub(
    listener: TcpListener,
    tile: Vec<u8>,
    expect: usize,
) -> std::thread::JoinHandle<Vec<ClientMsg>> {
    std::thread::spawn(move || {
        let (mut s, _) = listener.accept().unwrap();
        let mut fr = FrameReader::new();
        s.set_read_timeout(Some(Duration::from_secs(10))).unwrap();
        assert!(matches!(
            fr.read_msg::<ClientMsg>(&mut s).unwrap(),
            Some(ClientMsg::Hello { version: 1 })
        ));
        write_msg(&mut s, &ServerMsg::Hello).unwrap();
        write_msg(&mut s, &ServerMsg::ClearText).unwrap();
        write_msg(&mut s, &ServerMsg::AddText(item())).unwrap();
        write_msg(
            &mut s,
            &ServerMsg::Tile {
                x: 0,
                y: 0,
                data: tile,
            },
        )
        .unwrap();
        let mut got = Vec::new();
        while got.len() < expect {
            match fr.read_msg::<ClientMsg>(&mut s).unwrap() {
                Some(m) => got.push(m),
                None => panic!(\"timeout waiting for client messages\"),
            }
        }
        got
    })
}

fn recv_until(net: &Net, until: Instant, want: &mut dyn FnMut(Event) -> bool) {
    while Instant::now() < until {
        if let Ok(e) = net.events.recv_timeout(Duration::from_millis(200))
            && want(e)
        {
            return;
        }
    }
}

#[test]
fn hello_text_tile_and_reconnect() {
    let rgb = [40u8, 80, 160].repeat(64 * 64);
    let tile = encode_rgb(&rgb, 64, 64, 180).unwrap();

    let listener = TcpListener::bind(\"127.0.0.1:0\").unwrap();
    let port = listener.local_addr().unwrap().port();
    let addr = format!(\"127.0.0.1:{port}\");
    let sent = vec![
        ClientMsg::MouseMove { x: 10, y: 20 },
        ClientMsg::Button {
            button: 1,
            down: true,
        },
        ClientMsg::Button {
            button: 1,
            down: false,
        },
        ClientMsg::Text(\"ab\".into()),
    ];
    let stub1 = stub(listener, tile, sent.len());

    let net = net_connect(&addr);

    // First connection: hello, clear, text, tile.
    let (mut connected, mut clear, mut texts, mut tiles) = (0, 0, 0, 0);
    recv_until(&net, Instant::now() + Duration::from_secs(10), &mut |e| {
        match e {
            Event::Connected => connected += 1,
            Event::Disconnected(_) => {}
            Event::ClearText => clear += 1,
            Event::AddText(t) => {
                assert_eq!(t.text, \"hi\");
                texts += 1;
            }
            Event::Tile {
                x,
                y,
                w,
                h,
                rgba,
                bytes,
            } => {
                assert_eq!((x, y), (0, 0));
                assert_eq!((w, h), (64, 64));
                assert_eq!(rgba.len(), 64 * 64 * 4);
                assert!(bytes > 0);
                // Flat tile: source color everywhere, alpha 255.
                assert!(rgba.chunks(4).all(|p| p[3] == 255));
                for (got, want) in rgba[0..3].iter().zip([40, 80, 160]) {
                    assert!(got.abs_diff(want) <= 3, \"{rgba:?}\");
                }
                tiles += 1;
            }
        }
        connected >= 1 && clear >= 1 && texts >= 1 && tiles >= 1
    });
    assert_eq!((connected, clear, texts, tiles), (1, 1, 1, 1));

    // Other direction: send must arrive complete at the server.
    for m in &sent {
        net.send(m.clone());
    }
    assert_eq!(stub1.join().unwrap(), sent);

    // Notice the teardown, reconnect.
    let mut down = false;
    recv_until(&net, Instant::now() + Duration::from_secs(5), &mut |e| {
        if matches!(e, Event::Disconnected(_)) {
            down = true;
            return true;
        }
        false
    });
    assert!(down, \"teardown must arrive as event\");

    let listener2 = TcpListener::bind(&addr).unwrap();
    let tile2 = encode_rgb(&rgb, 64, 64, 180).unwrap();
    let stub2 = stub(listener2, tile2, 0);
    let mut reconnected = false;
    recv_until(&net, Instant::now() + Duration::from_secs(10), &mut |e| {
        if matches!(e, Event::Connected) {
            reconnected = true;
            return true;
        }
        false
    });
    assert!(reconnected, \"client must reconnect\");
    stub2.join().unwrap();
    drop(net);
}
")))

(defproject lbw-client-pg (:modules config scene av1 net app) (:entry app))
