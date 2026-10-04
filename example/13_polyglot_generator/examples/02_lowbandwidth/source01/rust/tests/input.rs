use lbw_client_pg::input::{btn_table, key_name};
use minifb::{Key, MouseButton};

#[test]
fn every_key_row_maps() {
    assert_eq!(key_name(Key::Enter), Some("Enter"));
    assert_eq!(key_name(Key::Escape), Some("Esc"));
    assert_eq!(key_name(Key::Tab), Some("Tab"));
    assert_eq!(key_name(Key::Backspace), Some("Backspace"));
    assert_eq!(key_name(Key::Delete), Some("Delete"));
    assert_eq!(key_name(Key::Up), Some("Up"));
    assert_eq!(key_name(Key::Down), Some("Down"));
    assert_eq!(key_name(Key::Left), Some("Left"));
    assert_eq!(key_name(Key::Right), Some("Right"));
    assert_eq!(key_name(Key::Home), Some("Home"));
    assert_eq!(key_name(Key::End), Some("End"));
    assert_eq!(key_name(Key::PageUp), Some("PageUp"));
    assert_eq!(key_name(Key::PageDown), Some("PageDown"));
    assert_eq!(key_name(Key::LeftShift), Some("Shift"));
    assert_eq!(key_name(Key::RightShift), Some("Shift"));
    assert_eq!(key_name(Key::LeftCtrl), Some("Control"));
    assert_eq!(key_name(Key::RightCtrl), Some("Control"));
    assert_eq!(key_name(Key::LeftAlt), Some("Alt"));
    assert_eq!(key_name(Key::RightAlt), Some("Alt"));
    assert_eq!(key_name(Key::F12), None);
}

#[test]
fn buttons_carry_x11_numbers() {
    let t = btn_table();
    assert_eq!(t[0], (MouseButton::Left, 1));
    assert_eq!(t[1], (MouseButton::Middle, 2));
    assert_eq!(t[2], (MouseButton::Right, 3));
}
