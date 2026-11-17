//! Buffers laya's `log` warnings so R can replay them (plan D5).
//!
//! laya sends Python's `warnings.warn` text to the `log` facade at `warn` level with target
//! `laya`. Nothing is printed and R is never called from inside the logger: records go into a
//! thread-local buffer that `envelope` drains into the result after every call.

use log::{Level, LevelFilter, Log, Metadata, Record};
use std::cell::RefCell;
use std::sync::Once;

thread_local! {
    static BUFFER: RefCell<Vec<String>> = const { RefCell::new(Vec::new()) };
}

struct BufferLogger;

impl Log for BufferLogger {
    fn enabled(&self, metadata: &Metadata) -> bool {
        metadata.level() <= Level::Warn && metadata.target().starts_with("laya")
    }

    fn log(&self, record: &Record) {
        if self.enabled(record.metadata()) {
            BUFFER.with(|b| b.borrow_mut().push(record.args().to_string()));
        }
    }

    fn flush(&self) {}
}

static INSTALL: Once = Once::new();
static LOGGER: BufferLogger = BufferLogger;

/// Install the logger once per process. If another logger is already set, keep it.
pub fn install() {
    INSTALL.call_once(|| {
        if log::set_logger(&LOGGER).is_ok() {
            log::set_max_level(LevelFilter::Warn);
        }
    });
}

/// Take every buffered warning from this thread.
pub fn drain() -> Vec<String> {
    BUFFER.with(|b| std::mem::take(&mut *b.borrow_mut()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn buffers_laya_warnings_only() {
        install();
        drain();
        log::warn!(target: "laya", "window capped");
        log::warn!(target: "other", "ignored");
        log::info!(target: "laya", "too quiet");
        assert_eq!(drain(), vec!["window capped".to_string()]);
        assert!(drain().is_empty());
    }
}
