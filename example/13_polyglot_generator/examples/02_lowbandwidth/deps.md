# deps.md — Abhängigkeiten von `02_lowbandwidth` (GitHub `org/projekt` für DeepWiki)

Stand: 2026-10-04 (Planung; Versionen nach `cargo upgrade` in T6 aktualisieren).

## Direkte Deps der erzeugten Crate `lbw-client-pg`

| Crate | Version (Plan) | GitHub | Wofür |
|---|---|---|---|
| `minifb` | 0.29.x | `emoon/rust_minifb` | Fenster, Framebuffer (`u32`), Maus/Tasten, Unicode via `InputCallback`. Nur `x11`-Feature (kein Wayland) für kleine Binary |
| `font8x8` | 0.3.1 | — (GitLab: `saibatizoku/font8x8-rs`, kein DeepWiki) | 8×8-Bitmap-Font, 0 transitive Deps; Text-Raster für OCR-Texte + HUD |
| `rav1d` | 1.1.x | `memorysafety/rav1d` | AV1-Decoder (`bitdepth_8`, wie `source7`) |
| `lbw-common` | Pfad-Dep | `plops/cl-cl-generator` (fremdes Repo: `cl-rust-generator`, Pfad `examples/29_lowbandwidth/source7_mvp/common`) | Protokolltypen + Framing + YUV (temporär, bis `common` portiert ist) |

## Dev-Deps (nur Tests, kein Binary-Anteil)

| Crate | Version (Plan) | GitHub | Wofür |
|---|---|---|---|
| `rav1e` | 0.8.x (ohne `asm`) | `xiph/rav1e` | Test-Helper kodiert 64×64-Kachel zur Testzeit (Einstellungen aus `server/src/05_av1.rs` gespiegelt) |

## Transitive (beachtenswert, nicht direkt)

| Crate | Kommt via | Anmerkung |
|---|---|---|
| `serde` / `bincode` | `lbw-common` | `serde-rs/serde`, `bincode-org/bincode` |
| `x11-dl`, `libc`, `tempfile`? | `minifb` (x11) | System: `libx11` unter Ubuntu; `xvfb` nur für Tests |
| `yuv`-eigene | `lbw-common` | reine Rust-Farbkonvertierung, keine Dep |

## Bewusst NICHT übernommen (aus `source7` abgewählt)

| Crate | GitHub | Grund |
|---|---|---|
| `macroquad` | `not-fl3/macroquad` | `async`-Main + Derive nicht im DSL ausdrückbar; schwerer Baum; ersetzt durch `minifb` + `font8x8` |
| `clap` | `clap-rs/clap` | Derive nicht im DSL; ein CLI-Flag → Hand-Parsing (15 Zeilen) |
| `lbw-server` (dev) | — | Zöge `ort`/`enigo` in Dev-Deps; ersetzt durch `rav1e`-Test-Helper |

## DeepWiki-Abfragen (bereits gestellt, Ergebnisse in `plan.md` eingeflossen)

- `emoon/rust_minifb`: Fenster, `update_with_buffer`, Maus/Tasten, `InputCallback`/`add_char`, `Key`-Namen.
- `plops/cl-cl-generator`: Polyglot-Escape-Hatches (`target-case`, `raw`, `rs::`, `defextern`, `define-dsl-macro`), `--targets`.
