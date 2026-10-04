//! Loopback: net against a stub server (hello, text, real AV1 tile,
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
        return Err(format!("bad box {w}x{h}"));
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
    let mut ctx: Context<u8> = cfg.new_context().map_err(|e| format!("rav1e: {e:?}"))?;
    let mut frame = ctx.new_frame();
    frame.planes[0].copy_from_raw_u8(&yuv.y, w, 1);
    frame.planes[1].copy_from_raw_u8(&yuv.u, yuv.cw(), 1);
    frame.planes[2].copy_from_raw_u8(&yuv.v, yuv.cw(), 1);
    ctx.send_frame(frame)
        .map_err(|e| format!("send_frame: {e:?}"))?;
    ctx.flush();
    let mut out = Vec::new();
    loop {
        match ctx.receive_packet() {
            Ok(pkt) => out.extend_from_slice(&pkt.data),
            Err(EncoderStatus::Encoded) => {}
            Err(EncoderStatus::LimitReached) => break,
            Err(e) => return Err(format!("receive_packet: {e:?}")),
        }
    }
    if out.is_empty() {
        return Err("rav1e produced no packet".into());
    }
    Ok(out)
}

fn item() -> TextItem {
    TextItem {
        rect: Rect::new(8, 8, 32, 16),
        fg: [0; 3],
        bg: [255; 3],
        text: "hi".into(),
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
                None => panic!("timeout waiting for client messages"),
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

    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let port = listener.local_addr().unwrap().port();
    let addr = format!("127.0.0.1:{port}");
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
        ClientMsg::Text("ab".into()),
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
                assert_eq!(t.text, "hi");
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
                    assert!(got.abs_diff(want) <= 3, "{rgba:?}");
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
    assert!(down, "teardown must arrive as event");

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
    assert!(reconnected, "client must reconnect");
    stub2.join().unwrap();
    drop(net);
}
