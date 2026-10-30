//! The API exposed to Dart.

use flutter_rust_bridge::frb;

pub mod calls;
pub mod devices;
pub mod directory;
pub mod drafts;
pub mod error;
pub mod jump;
pub mod logging;
pub mod media;
mod media_prep;
pub mod membership;
pub mod mentions;
pub mod moderation;
pub mod notices;
pub mod notifications;
pub mod notify;
pub mod pins;
pub mod profile;
pub mod recovery;
pub mod rich_text;
pub mod room_info;
pub mod room_list;
pub mod room_settings;
pub mod rooms;
pub mod search;
pub mod sections;
pub mod server_info;
pub mod server_updates;
pub mod session;
pub mod sync;
pub mod threads;
pub mod timeline;
pub mod typing;
pub mod users;
pub mod verification;
pub mod voice;

/// Sets up the bridge's default logging and panic handling and installs ring as the TLS
/// provider. Called once by `RustLib.init()`.
#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
    // Fails only if a provider is already installed, which is fine.
    let _ = rustls::crypto::ring::default_provider().install_default();
}

/// The version of this crate, so the app can show which core it runs.
#[frb(sync)]
#[must_use]
pub fn core_version() -> String {
    env!("CARGO_PKG_VERSION").to_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn core_version_is_the_crate_version() {
        assert_eq!(core_version(), "0.1.37");
    }
}
