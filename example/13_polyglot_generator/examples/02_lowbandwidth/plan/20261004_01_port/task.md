# Tasks: Low-Bandwidth-Client im Polyglot-Generator

Serielle Abarbeitung zu `plan.md`. Jede Phase endet mit ihren Gates;
erst bei grünen Gates committen (Format s. `plan.md` §7) und weitergehen.
Alle Pfade relativ zu `example/13_polyglot_generator/`.

## Standard-Gates (jede Phase)

1. **Paren-Check:** `sbcl --non-interactive --eval '(progn (with-open-file
   (s "examples/02_lowbandwidth/project.lisp") (loop (read s nil :eof)
   ... )))'` — bzw. `tools/lisp-check.sh`, falls vorhanden.
   Regel: nach zwei erfolglosen Fix-Versuchen stoppen + fragen.
2. **Generieren:** `sbcl --non-interactive --load
   examples/02_lowbandwidth/gen.lisp` (idempotent: zweiter Lauf → 0 written).
3. **Rust-Gates** in `examples/02_lowbandwidth/source01/rust/`:
   `cargo fmt --all -- --check`, `cargo clippy --all-targets -- -D warnings`.
4. **Tests:** `cargo test` (dev-Profil mit `opt-level = 3` für Deps,
   wie `source7`, sobald AV1 im Spiel ist).

## T0. Recherche und Probes — DONE (2026-10-04)

- Transpiler-Quellen gelesen, `rs::raw`-Probes in `/tmp/pgprobe` grün
  (Build + Clippy + Fmt). Regeln in `plan.md` §4 festgehalten.
- GUI-Entscheid: `minifb` (x11-only) + `font8x8`, CLI hand-geparst.
- DeepWiki befragt: `emoon/rust_minifb` (InputCallback, Key-Namen),
  `plops/cl-cl-generator` (Escape Hatches).
- Ergebnis: `plan.md`, `task.md` (beide heute in `plan/20261004_01_port/`),
  `deps.md` im Beispiel-Wurzelordner.

## T1. Gerüst + `config` (§2–§3, §5 in plan.md)

1. `project.lisp` anlegen: Tabellen (`+key-table+`, `+btn-table+`),
   Helfer-Funktionen, `config`-Modul (DSL), `main`-Entry (dünn).
2. **Vorab-Probe:** Kann `rs::raw` ein `,(...)`-splicedes Argument
   tragen (s. `plan.md` §5, Achtung-Box)? Falls nein: Pattern mit
   `register-module`-Backquote verwenden und Plan korrigieren.
3. `gen.lisp` anlegen: `write-project` (`:targets (:rust)`),
   `Cargo.toml`-Patch (Edition 2024, Deps), `src/lib.rs`-Template,
   `examples/`- und `tests/`-Templates (zunächst `tests/config.rs`).
4. `config`: Struct `Config { connect: String }`, Default
   `127.0.0.1:7878`, `parse-args` mit Usage-Fehler (Exit 2).
5. Gates 1–4. Commit `feat(02_lowbandwidth): gerüst und config-modul`.

## T2. `scene` (reine Logik im DSL)

1. Struct `Scene` (canvas `(vec :u8)`, texts-Vec über Raw-Typ,
   `dirty`, Zähler, `link` als Raw-Typ).
2. DSL: `blit` (elementweise, `dotimes`+`setf`/`aref`), `pixel`-Zugriff,
   `scene-new`-Konstruktor (frei), HUD-Text (`format-string`).
3. Append-Template: `enum Link`; Raw: `apply` (`match`), Text-Helfer.
4. `tests/scene.rs`: `source7`-Tests spiegeln (clear/add, blit-Bounds,
   beliebige Boxen, Link-Zustand).
5. Gates 1–4. Commit `feat(02_lowbandwidth): scene-modul und tests`.

## T3. `av1` (rav1d-Wrapper)

1. Structs `Decoder`/`Rgba` (Raw-Typ-Felder), Methoden-Signaturen im DSL,
   Bodies raw (`unsafe` wie `source7`, eine Stelle).
2. Append-Template: `impl Drop`; `Send`-Frage per Compiler klären
   (s. `plan.md` Vorschlag 3).
3. `tests/av1.rs`: Garbage-ist-Fehler (kein Crash).
4. Gates 1–4. Commit `feat(02_lowbandwidth): av1-decoder und test`.

## T4. `net` + Loopback-Test

1. Struct `Net` (Raw-Typ-Felder), `net-connect` (frei),
   `send`-Methode, `run`/`session`-Schleifen (raw).
2. Append-Template: `enum Event`, `impl Drop`.
3. `tests/loopback.rs`: Stub-Server (Hello/Text/Kachel/Abriss),
   Kachel via `rav1e`-Test-Helper (Einstellungen aus
   `server/src/05_av1.rs` gespiegelt), Reconnect-Erwartung.
4. Gates 1–4 (Loopback braucht `cargo test`, kein Display).
   Commit `feat(02_lowbandwidth): netz-modul und loopback-test`.

## T5. `app` + `main` + `probe`

1. `app`: minifb-Loop (raw): Fenster, RGBA→u32-Upload, Text-Raster
   (`font8x8`, skaliert, `?`-Fallback), HUD, `show-hud` (F1),
   Input-Poll (Maus/Tasten/Unicode-Callback) aus `+key-table+`/
   `+btn-table+` per Splice.
2. `main`-Entry ruft Config→Run auf.
3. `examples/probe.rs`-Template: Smoke-Probe mit `--stay N`.
4. Unit-Anteil: Key-Tabellen-Roundtrip als Test (jede Zeile).
5. Gates 1–4. Commit `feat(02_lowbandwidth): app-loop und probe`.

## T6. Integration und Härtung — DONE (2026-10-04)

1. `cargo upgrade`: keine neueren Versionen (minifb 0.29.0,
   font8x8 0.3.1, rav1d 1.1.0, rav1e 0.8.1, bincode 2.0.1);
   Gates 3–4 danach erneut grün.
2. Echter `source7`-Server (Release, `models/` aus `source7_mvp`):
   unsere `probe` → rc 0, „OK (5 texts, 1 tiles, 557 B)",
   alle OCR-Texte erkannt; Server-Log zeigt unsere Eingaben
   (`MouseMove`/`Button`/`Text("hi")`/`Key Enter`).
3. GUI-Smoke unter `xvfb` (`xwd` + Pixel-Diff): Client-Fenster
   640×640 rendert Szene; Live-Update nach xterm-Move
   (262 039 geänderte px); F1 blendet HUD aus (2 555 px,
   BBox oben) und wieder ein (2 533 px). Hinweis: ohne
   Window-Manager braucht `xdotool` `key --window …`
   (`windowactivate` scheitert an `_NET_ACTIVE_WINDOW`).
4. Binary-Größe gestrippt: 2 200 224 B (2,1 MiB) vs.
   `source7`-Client 3 283 840 B (3,1 MiB) → −33 %;
   Lock-Pakete 143 vs. 240. Details in `../../deps.md`.
5. Commit `test(02_lowbandwidth): integrationsnachweis …`.

## T7. Abschluss — DONE (2026-10-04)

1. Alle Gates final grün, `git status` sauber (nur gewollte Files).
2. `walkthrough.md` in `examples/02_lowbandwidth/plan/20261004_01_port/` schreiben
   (deutsch, Mermaid, Code-Beispiele; Struktur s. `prompt.txt`:
   implementiert / spontane Architektur-Änderungen / Learnings +
   Erweiterungen / neue Pakete fürs Dockerfile).
3. Commit `docs(02_lowbandwidth): walkthrough der client-portierung`.
