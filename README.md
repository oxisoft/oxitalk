# OxiTalk

An open-source [Matrix](https://matrix.org) client for iOS, Android, macOS, Windows and Linux,
built with Flutter on top of [matrix-rust-sdk](https://github.com/matrix-org/matrix-rust-sdk),
the engine behind Element X.

> **Status: early proof of concept.** Nothing here is usable yet.

## Layout

```
apps/oxitalk/        Flutter app
rust/                Cargo workspace
rust/oxitalk_core/   Rust core: the Matrix facade the app calls through flutter_rust_bridge
scripts/ci.sh        every check CI runs on Linux
test-infra/          Synapse test homeserver (compose) for the Rust integration tests
```

## Building

Requirements: Flutter (exact version in `apps/oxitalk/pubspec.yaml`), rustup (the toolchain
in `rust/rust-toolchain.toml` installs itself), `flutter_rust_bridge_codegen` 2.13.0, and for
Android the NDK version pinned in `apps/oxitalk/android/app/build.gradle.kts`.

```sh
cd apps/oxitalk
flutter run            # the Rust core is built by the Flutter build hook
```

After changing the Rust API, regenerate the bindings with `flutter_rust_bridge_codegen generate`
in `apps/oxitalk`.

## Releasing

Pushing a tag `v<version>` that matches `version:` in `apps/oxitalk/pubspec.yaml` builds the
iOS and macOS apps and uploads them to TestFlight (`.github/workflows/app-store.yml`, which
runs `scripts/apple-release.sh`). The App Store Connect API key is kept in the secrets of the
`app-store` environment. The same workflow can be run by hand on any branch, also without
uploading.

## License

[MIT](LICENSE)
