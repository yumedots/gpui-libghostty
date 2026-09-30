use gpui::{ClipboardItem, Image, ImageFormat};

use super::paste_text;

#[test]
fn text_clipboards_paste_their_text() {
    let item = ClipboardItem::new_string("hello".into());
    assert_eq!(paste_text(&item), "hello");
}

#[test]
fn image_clipboards_paste_a_temp_file_path() {
    let item = ClipboardItem::new_image(&Image {
        format: ImageFormat::Png,
        bytes: vec![1, 2, 3],
        id: 7,
    });

    let path = paste_text(&item);
    assert!(path.ends_with(".png"), "unexpected path {path}");
    assert!(
        path.contains("farcaster-pastes"),
        "unexpected path {path}"
    );
    assert_eq!(std::fs::read(&path).expect("stored image"), vec![1, 2, 3]);
}

#[test]
fn empty_clipboards_paste_nothing() {
    let item = ClipboardItem::new_string(String::new());
    assert_eq!(paste_text(&item), "");
}
