use lbw_client_pg::config::{default_connect, parse_args, usage_text};

fn argv(words: &[&str]) -> Vec<String> {
    words.iter().map(|s| s.to_string()).collect()
}

#[test]
fn defaults_and_options() {
    let c = parse_args(&argv(&["lbw-client-pg"])).expect("defaults");
    assert_eq!(c.connect, "127.0.0.1:7878");
    assert_eq!(default_connect(), "127.0.0.1:7878");
    let c = parse_args(&argv(&["lbw-client-pg", "--connect", "h:1"])).expect("opt");
    assert_eq!(c.connect, "h:1");
}

#[test]
fn errors_are_none() {
    assert!(parse_args(&argv(&["lbw-client-pg", "--bogus"])).is_none());
    assert!(parse_args(&argv(&["lbw-client-pg", "--connect"])).is_none());
}

#[test]
fn usage_mentions_flag() {
    assert!(usage_text().contains("--connect"));
}
