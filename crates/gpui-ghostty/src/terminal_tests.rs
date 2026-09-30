use super::shifted_enter_breaks_line;

fn keystroke(source: &str) -> gpui::Keystroke {
    gpui::Keystroke::parse(source).expect("valid keystroke")
}

#[test]
fn plain_shift_enter_inserts_a_line_break_instead_of_submitting() {
    assert!(shifted_enter_breaks_line(&keystroke("shift-enter")));
    assert!(shifted_enter_breaks_line(&keystroke("shift-ENTER")));
}

#[test]
fn enter_without_shift_still_submits() {
    assert!(!shifted_enter_breaks_line(&keystroke("enter")));
}

#[test]
fn other_keys_and_modifier_combos_are_left_alone() {
    for source in [
        "ctrl-shift-enter",
        "cmd-shift-enter",
        "alt-shift-enter",
        "shift-a",
        "space",
    ] {
        assert!(!shifted_enter_breaks_line(&keystroke(source)), "{source}");
    }
}
