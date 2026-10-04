//! Headless smoke client: connects, waits for text + tile, sends
//! inputs and reports success. With a second argument it stays N more
//! seconds connected and reports totals (throughput check). Usage:
//! `cargo run --release -p lbw-client-pg --example probe -- ADDR [N]`

use std::time::{Duration, Instant};

use lbw_client_pg::net::net_connect;
use lbw_client_pg::scene::{scene_new, Event};
use lbw_common::ClientMsg;

fn main() {
    let mut args = std::env::args().skip(1);
    let addr = args.next().unwrap_or_else(|| "127.0.0.1:7878".into());
    let stay: u64 = args.next().and_then(|s| s.parse().ok()).unwrap_or(0);
    let net = net_connect(&addr);
    let mut scene = scene_new();
    let deadline = Instant::now() + Duration::from_secs(60);
    let mut sent_input = false;
    let mut connected = false;
    while Instant::now() < deadline {
        match net.events.recv_timeout(Duration::from_millis(500)) {
            Ok(Event::Connected) => {
                connected = true;
                println!("probe: connected");
            }
            Ok(e) => scene.apply_event(e),
            Err(_) => {}
        }
        let got_text = !scene.texts.is_empty();
        let got_tile = scene.tiles > 0;
        if connected && got_tile && !sent_input {
            net.send(ClientMsg::MouseMove { x: 100, y: 100 });
            net.send(ClientMsg::Button {
                button: 1,
                down: true,
            });
            net.send(ClientMsg::Button {
                button: 1,
                down: false,
            });
            net.send(ClientMsg::Text("hi".into()));
            net.send(ClientMsg::Key {
                key: "Enter".into(),
                down: true,
            });
            net.send(ClientMsg::Key {
                key: "Enter".into(),
                down: false,
            });
            sent_input = true;
            println!("probe: inputs sent");
        }
        if connected && got_text && got_tile && sent_input {
            // The net thread needs one loop iteration (<=50 ms) to flush
            // the inputs just sent, or they die with the process before
            // the server sees them.
            std::thread::sleep(Duration::from_secs(1));
            println!(
                "probe: OK ({} texts, {} tiles, {} B)",
                scene.texts.len(),
                scene.tiles,
                scene.tile_bytes
            );
            for t in scene.texts.iter().take(5) {
                println!("probe: text {:?} {:?}", t.rect, t.text);
            }
            if stay == 0 {
                return;
            }
            let end = Instant::now() + Duration::from_secs(stay);
            while Instant::now() < end {
                if let Ok(e) = net.events.recv_timeout(Duration::from_millis(500)) {
                    scene.apply_event(e);
                }
            }
            println!(
                "probe: after {stay}s: {} texts, {} tiles, {} B ({} B/s)",
                scene.texts.len(),
                scene.tiles,
                scene.tile_bytes,
                scene.tile_bytes / stay.max(1)
            );
            return;
        }
    }
    eprintln!(
        "probe: TIMEOUT (connected={connected} texts={} tiles={})",
        scene.texts.len(),
        scene.tiles
    );
    std::process::exit(1);
}
