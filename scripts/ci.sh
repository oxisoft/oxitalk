#!/usr/bin/env bash
# Everything CI checks on Linux, runnable locally: ./scripts/ci.sh
# Needs: the Rust toolchain from rust/rust-toolchain.toml, Flutter (version in
# apps/oxitalk/pubspec.yaml), flutter_rust_bridge_codegen 2.13.0, ANDROID_HOME with the NDK
# pinned in apps/oxitalk/android/app/build.gradle.kts, actionlint and zizmor.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
app=$root/apps/oxitalk
rust=$root/rust

step() { printf '\n== %s\n' "$*"; }

step "rust-toolchain.toml copies match"
cmp "$rust/rust-toolchain.toml" "$rust/oxitalk_core/rust-toolchain.toml"

step "workflows (actionlint, zizmor)"
actionlint=$(command -v actionlint || echo "$HOME/go/bin/actionlint")
"$actionlint" "$root"/.github/workflows/*.yml
zizmor --quiet "$root/.github/workflows"

step "generated bindings are up to date"
(cd "$app" && flutter_rust_bridge_codegen generate >/dev/null)
generated=(rust/oxitalk_core/src/frb_generated.rs apps/oxitalk/lib/src/rust)
git -C "$root" diff --exit-code -- "${generated[@]}"
if [ -n "$(git -C "$root" ls-files --others --exclude-standard -- "${generated[@]}")" ]; then
  echo "untracked generated files" >&2
  exit 1
fi

step "rust: fmt, clippy (host, android, wasm), tests"
cd "$rust"
cargo fmt --all --check
cargo clippy --workspace --all-targets --locked -- -D warnings
ndk_version=$(sed -n 's/.*ndkVersion = "\(.*\)".*/\1/p' "$app/android/app/build.gradle.kts")
ndk_bin=$ANDROID_HOME/ndk/$ndk_version/toolchains/llvm/prebuilt/linux-x86_64/bin
CC_aarch64_linux_android=$ndk_bin/aarch64-linux-android36-clang \
  AR_aarch64_linux_android=$ndk_bin/llvm-ar \
  cargo clippy --workspace --locked --target aarch64-linux-android -- -D warnings
cargo clippy --workspace --locked --target wasm32-unknown-unknown -- -D warnings
cargo test --workspace --locked

step "dart: format, analyze, tests"
cd "$app"
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib/main.dart test integration_test hook
flutter analyze --fatal-infos --fatal-warnings
flutter test

step "debug builds: linux, android, web"
flutter build linux --debug
flutter build apk --debug
flutter build web --debug

step "integration test (linux)"
if [ -n "${CI:-}" ]; then
  xvfb-run -a flutter test integration_test -d linux
else
  flutter test integration_test -d linux
fi

printf '\nCI OK\n'
