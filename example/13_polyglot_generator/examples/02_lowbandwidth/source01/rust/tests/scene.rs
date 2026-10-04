use lbw_client_pg::scene::{hud_text, scene_new, Event, Link};
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
    s.apply_event(Event::AddText(item("a")));
    s.apply_event(Event::AddText(item("b")));
    assert_eq!(s.texts.len(), 2);
    s.apply_event(Event::ClearText);
    assert!(s.texts.is_empty());
    s.apply_event(Event::AddText(item("c")));
    assert_eq!(s.texts[0].text, "c");
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
    s.apply_event(Event::Disconnected("x".into()));
    assert_eq!(s.link, Link::Down("x".into()));
    s.apply_event(Event::Disconnected("y".into()));
    assert_eq!(s.link, Link::Down("x".into()), "first disconnect wins");
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
    let h = hud_text("online", 3, 7, 100);
    assert!(h.contains("online"), "{h}");
    assert!(h.contains("3 Texte"), "{h}");
    assert!(h.contains("7 Kacheln"), "{h}");
    assert!(h.contains("100 B"), "{h}");
}
