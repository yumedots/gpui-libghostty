use std::{
    sync::atomic::{AtomicU64, Ordering},
    time::{SystemTime, UNIX_EPOCH},
};

use gpui::{ClipboardEntry, ClipboardItem};

static SEQUENCE: AtomicU64 = AtomicU64::new(0);

pub(crate) fn paste_text(item: &ClipboardItem) -> String {
    let text = item.text().unwrap_or_default();
    if !text.is_empty() {
        return text;
    }
    item.entries
        .iter()
        .filter_map(|entry| match entry {
            ClipboardEntry::Image(image) if !image.bytes.is_empty() => store_image(image),
            ClipboardEntry::String(_) | ClipboardEntry::ExternalPaths(_) | ClipboardEntry::Image(_) => {
                None
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

fn store_image(image: &gpui::Image) -> Option<String> {
    let directory = std::env::temp_dir().join("farcaster-pastes");
    std::fs::create_dir_all(&directory).ok()?;
    let stamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let sequence = SEQUENCE.fetch_add(1, Ordering::Relaxed);
    let path = directory.join(format!(
        "paste-{}-{stamp}-{sequence}.{}",
        std::process::id(),
        image.format.extension()
    ));
    std::fs::write(&path, &image.bytes).ok()?;
    Some(path.display().to_string())
}

#[cfg(test)]
#[path = "image_paste_tests.rs"]
mod tests;
