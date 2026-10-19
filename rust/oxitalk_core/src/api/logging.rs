//! Diagnostic logs: the SDK's and the app's, in daily files the user can turn on and off.
//!
//! The SDK logs IDs and states, not message contents or keys.

use std::sync::{Mutex, OnceLock, PoisonError};

use flutter_rust_bridge::frb;
use tracing_appender::{
    non_blocking::WorkerGuard,
    rolling::{RollingFileAppender, Rotation},
};
use tracing_subscriber::{EnvFilter, Registry, layer::SubscriberExt, reload};

use super::error::CoreError;

/// What is logged while logging is on: the SDK at info, verification and our own code in detail.
const FILTER: &str = "info,matrix_sdk::encryption=debug,matrix_sdk_crypto::verification=debug,oxitalk=debug,oxitalk_core=debug";

/// How many daily files are kept.
const KEPT_FILES: usize = 7;

struct Logging {
    filter: reload::Handle<EnvFilter, Registry>,
    /// Flushes the file writer when dropped; kept for the life of the process.
    _guard: WorkerGuard,
}

static LOGGING: OnceLock<Logging> = OnceLock::new();
static INIT: Mutex<()> = Mutex::new(());

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LogLevel {
    Error,
    Warn,
    Info,
    Debug,
}

/// Sets up logging to `oxitalk.<date>.log` files in `dir`, keeping a week of them, and turns it
/// on or off. Later calls only turn it on or off.
///
/// # Errors
///
/// [`CoreError::Internal`] if the directory can't be used.
#[frb(sync)]
pub fn init_logging(dir: String, enabled: bool) -> Result<(), CoreError> {
    let _init = INIT.lock().unwrap_or_else(PoisonError::into_inner);
    if LOGGING.get().is_none() {
        let appender = RollingFileAppender::builder()
            .rotation(Rotation::DAILY)
            .filename_prefix("oxitalk")
            .filename_suffix("log")
            .max_log_files(KEPT_FILES)
            .build(&dir)
            .map_err(|error| CoreError::internal(&error))?;
        let (writer, guard) = tracing_appender::non_blocking(appender);
        let (filter, handle) = reload::Layer::new(filter_for(false));
        let subscriber = Registry::default().with(filter).with(
            tracing_subscriber::fmt::layer()
                .with_writer(writer)
                .with_ansi(false),
        );
        tracing::subscriber::set_global_default(subscriber)
            .map_err(|error| CoreError::internal(&error))?;
        // Only this function sets it, under the lock.
        let _ = LOGGING.set(Logging {
            filter: handle,
            _guard: guard,
        });
    }
    set_logging(enabled);
    Ok(())
}

/// Turns logging on or off; nothing happens before [`init_logging`].
#[frb(sync)]
pub fn set_logging(enabled: bool) {
    if let Some(logging) = LOGGING.get() {
        // Fails only if the subscriber is gone, which it never is.
        let _ = logging.filter.reload(filter_for(enabled));
    }
    if enabled {
        tracing::info!(version = env!("CARGO_PKG_VERSION"), "logging on");
    }
}

/// Writes a line from the app into the log.
#[frb(sync)]
pub fn write_log(level: LogLevel, target: String, message: String) {
    match level {
        LogLevel::Error => tracing::error!(target: "oxitalk", %target, "{message}"),
        LogLevel::Warn => tracing::warn!(target: "oxitalk", %target, "{message}"),
        LogLevel::Info => tracing::info!(target: "oxitalk", %target, "{message}"),
        LogLevel::Debug => tracing::debug!(target: "oxitalk", %target, "{message}"),
    }
}

fn filter_for(enabled: bool) -> EnvFilter {
    EnvFilter::new(if enabled { FILTER } else { "off" })
}
