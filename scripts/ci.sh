#!/usr/bin/env bash
# Everything CI checks on Linux, runnable locally: ./scripts/ci.sh
# Needs: the Rust toolchain from rust/rust-toolchain.toml, Flutter (version in
# apps/oxitalk/pubspec.yaml), flutter_rust_bridge_codegen 2.13.0, cargo-llvm-cov, ANDROID_HOME
# with the NDK pinned in apps/oxitalk/android/app/build.gradle.kts, actionlint, zizmor, and
# podman compose (with the user podman.socket enabled) or, when CI is set, docker compose.
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

step "generated code is up to date (bindings, freezed, riverpod)"
(cd "$app" && flutter_rust_bridge_codegen generate >/dev/null && dart run build_runner build >/dev/null)
generated=(rust/oxitalk_core/src/frb_generated.rs apps/oxitalk/lib)
git -C "$root" diff --exit-code -- "${generated[@]}"
if [ -n "$(git -C "$root" ls-files --others --exclude-standard -- "${generated[@]}")" ]; then
  echo "untracked generated files" >&2
  exit 1
fi

step "rust: fmt, clippy (host, android), tests"
cd "$rust"
cargo fmt --all --check
cargo clippy --workspace --all-targets --locked -- -D warnings
ndk_version=$(sed -n 's/.*ndkVersion = "\(.*\)".*/\1/p' "$app/android/app/build.gradle.kts")
ndk_bin=$ANDROID_HOME/ndk/$ndk_version/toolchains/llvm/prebuilt/linux-x86_64/bin
CC_aarch64_linux_android=$ndk_bin/aarch64-linux-android36-clang \
  AR_aarch64_linux_android=$ndk_bin/llvm-ar \
  cargo clippy --workspace --locked --target aarch64-linux-android -- -D warnings
cargo test --workspace --locked

step "rust: all tests with the test homeservers (Synapse, then Tuwunel), coverage (not a gate)"
if [ -n "${CI:-}" ]; then compose=(docker compose); else compose=(podman compose); fi
compose+=(--file "$root/test-infra/compose.yaml")
"${compose[@]}" down --volumes --timeout 1 >/dev/null 2>&1 || true
trap '"${compose[@]}" down --volumes --timeout 1 >/dev/null 2>&1 || true' EXIT
"${compose[@]}" up --detach
# Every test runs on both; Tuwunel has no /health, so both are asked for their versions.
homeservers=(http://localhost:8008 http://localhost:8009)
for homeserver in "${homeservers[@]}"; do
  for _ in $(seq 60); do
    curl --silent --fail "$homeserver/_matrix/client/versions" >/dev/null && break
    sleep 1
  done
  curl --silent --show-error --fail "$homeserver/_matrix/client/versions" >/dev/null \
    || { "${compose[@]}" logs; exit 1; }
done
coverage=$(OXITALK_TEST_HOMESERVER=${homeservers[0]} cargo llvm-cov --workspace --locked \
  --summary-only --ignore-filename-regex 'frb_generated\.rs' -- --include-ignored)
printf '%s\n' "$coverage"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  printf '### Rust coverage\n\n```\n%s\n```\n' "$coverage" >>"$GITHUB_STEP_SUMMARY"
fi
cargo llvm-cov clean --workspace
OXITALK_TEST_HOMESERVER=${homeservers[1]} cargo test --locked -p oxitalk_core --test homeserver \
  -- --ignored

step "dart: format, analyze, tests"
cd "$app"
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed \
  lib/main.dart lib/src/{app,features,matrix,ui,util} test integration_test hook
flutter analyze --fatal-infos --fatal-warnings
flutter test

step "debug builds: linux, android"
flutter build linux --debug
flutter build apk --debug

# A hung test must fail the run, not stall it.
step "integration test (linux), on both test homeservers"
# In a virtual display when there is one, so no window opens on a developer's desktop. GTK
# would still pick a Wayland session's display, so it is kept to X11.
for homeserver in "${homeservers[@]}"; do
  if [ -n "${CI:-}" ] || command -v xvfb-run >/dev/null; then
    OXITALK_TEST_HOMESERVER=$homeserver timeout 600 env -u WAYLAND_DISPLAY GDK_BACKEND=x11 \
      xvfb-run -a flutter test integration_test -d linux
  else
    OXITALK_TEST_HOMESERVER=$homeserver timeout 600 flutter test integration_test -d linux
  fi
done

printf '\nCI OK\n'
