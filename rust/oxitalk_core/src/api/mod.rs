//! The API exposed to Dart.

use flutter_rust_bridge::frb;

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
        assert_eq!(core_version(), "0.1.4");
    }
}
