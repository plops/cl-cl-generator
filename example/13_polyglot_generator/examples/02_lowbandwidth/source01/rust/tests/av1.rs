use lbw_client_pg::av1::decoder_new;

#[test]
fn garbage_is_an_error_not_a_crash() {
    let mut d = decoder_new().expect("rav1d open");
    assert!(d.decode(&[]).is_err());
    assert!(d.decode(&[0x12, 0x00, 0xff, 0xff, 0x01]).is_err());
}
