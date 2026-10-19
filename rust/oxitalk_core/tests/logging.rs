//! Logging to files, on and off. One test only: the subscriber is global to the process.

use std::{fs, path::Path, time::Duration};

use oxitalk_core::api::logging::{LogLevel, init_logging, set_logging, write_log};

/// Everything written to the log files in `dir` so far.
fn logged(dir: &Path) -> String {
    fs::read_dir(dir)
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|entry| fs::read_to_string(entry.path()).ok())
        .collect()
}

/// The writer flushes on its own thread; waits until `text` shows up.
fn wait_for(dir: &Path, text: &str) -> bool {
    for _ in 0..50 {
        if logged(dir).contains(text) {
            return true;
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    false
}

#[test]
fn logs_only_while_on() -> Result<(), Box<dyn std::error::Error>> {
    let dir = tempfile::tempdir()?;
    init_logging(dir.path().to_string_lossy().into_owned(), false)?;
    write_log(LogLevel::Error, "test".to_owned(), "while off".to_owned());

    set_logging(true);
    write_log(LogLevel::Info, "test".to_owned(), "while on".to_owned());
    assert!(wait_for(dir.path(), "while on"));

    set_logging(false);
    write_log(LogLevel::Error, "test".to_owned(), "off again".to_owned());
    // A line written after this one shows the writer has caught up.
    set_logging(true);
    write_log(LogLevel::Info, "test".to_owned(), "marker".to_owned());
    assert!(wait_for(dir.path(), "marker"));

    let text = logged(dir.path());
    assert!(!text.contains("while off"), "{text}");
    assert!(!text.contains("off again"), "{text}");
    let files: Vec<_> = fs::read_dir(dir.path())?.flatten().collect();
    assert_eq!(files.len(), 1);
    assert!(
        files[0]
            .file_name()
            .to_string_lossy()
            .starts_with("oxitalk."),
        "{files:?}"
    );
    Ok(())
}
