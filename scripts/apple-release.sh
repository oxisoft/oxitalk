#!/usr/bin/env bash
# Release build for the App Store: archive, sign with Apple's cloud-managed distribution
# certificate, and (with --upload) send it to App Store Connect, where it appears in
# TestFlight. Never submits for review.
#
#   scripts/apple-release.sh ios|macos [--upload]
#
# iOS is the App Store record io.oxisoft.oxitalk, macOS its own record
# io.oxisoft.oxitalk.macos. Needs Xcode, Flutter, rustup and an App Store Connect API key:
#   ASC_KEY_ID, ASC_ISSUER_ID, and ASC_KEY_PATH (the AuthKey .p8 file). Without a key and
#   without --upload it stops after the archive is signed ad hoc (a build check).
#
# The archive is built unsigned, so no signing certificate is ever created on the machine.
# The app is then ad-hoc signed with the release entitlements, because the export keeps only
# the entitlements already in the archived signature; the export re-signs it for distribution.
set -euo pipefail

platform=${1:?usage: apple-release.sh ios|macos [--upload]}
upload=${2:-}
team=75PUXA6477
root=$(cd "$(dirname "$0")/.." && pwd)
app=$root/apps/oxitalk
if [ -n "${ASC_KEY_ID:-}" ] && [ -s "${ASC_KEY_PATH:-}" ]; then
  have_key=1
elif [ "$upload" = --upload ]; then
  echo "uploading needs ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH" >&2
  exit 2
fi

case $platform in
  ios)
    entitlements=$app/ios/Runner/Runner.entitlements
    workspace=$app/ios/Runner.xcworkspace
    destination='generic/platform=iOS'
    frameworks=Frameworks
    aps_key=aps-environment
    ;;
  macos)
    entitlements=$app/macos/Runner/Release.entitlements
    workspace=$app/macos/Runner.xcworkspace
    destination='generic/platform=macOS'
    frameworks=Contents/Frameworks
    aps_key=com.apple.developer.aps-environment
    ;;
  *) echo "unknown platform: $platform" >&2; exit 2 ;;
esac

out=$app/build/release-$platform
rm -rf "$out"
mkdir -p "$out"
step() { printf '\n== %s\n' "$*"; }
tail_log() { echo "-- $1 failed, last 60 lines:"; tail -60 "$out/$1.log"; exit 1; }

cd "$app"
step "flutter build $platform --config-only ($(sed -n 's/^version: *//p' pubspec.yaml))"
flutter build "$platform" --release --config-only

step "archive (unsigned)"
xcodebuild -workspace "$workspace" -scheme Runner -configuration Release \
  -destination "$destination" -archivePath "$out/Runner.xcarchive" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  archive >"$out/archive.log" 2>&1 || tail_log archive
bundle=$(ls -d "$out"/Runner.xcarchive/Products/Applications/*.app)
echo "archived $bundle"

step "ad-hoc sign with the release entitlements"
# Distribution builds take the production push environment.
sed -e "s/\$(AppIdentifierPrefix)/$team./g" "$entitlements" >"$out/release.entitlements"
# PlistBuddy, not plutil: plutil reads the dots in the macOS key as a key path.
/usr/libexec/PlistBuddy -c "Set :$aps_key production" "$out/release.entitlements"
find "$bundle/$frameworks" -maxdepth 1 \( -name '*.framework' -o -name '*.dylib' \) \
  -exec codesign --force --sign - --timestamp=none {} \;
codesign --force --sign - --timestamp=none --entitlements "$out/release.entitlements" "$bundle"
codesign -d --entitlements - "$bundle"

if [ -z "${have_key:-}" ]; then
  echo "no App Store Connect key: stopping before the export"
  exit 0
fi
auth=(-allowProvisioningUpdates
  -authenticationKeyPath "$ASC_KEY_PATH"
  -authenticationKeyID "$ASC_KEY_ID"
  -authenticationKeyIssuerID "${ASC_ISSUER_ID:?}")
if [ "$upload" = --upload ]; then target=upload; else target=export; fi
cat >"$out/export.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>$team</string>
  <key>destination</key><string>$target</string>
  <key>uploadSymbols</key><true/>
</dict></plist>
EOF

step "export ($target)"
xcodebuild -exportArchive -archivePath "$out/Runner.xcarchive" -exportPath "$out/export" \
  -exportOptionsPlist "$out/export.plist" "${auth[@]}" >"$out/export.log" 2>&1 \
  || tail_log export
grep -E "Upload succeeded|Uploaded|EXPORT SUCCEEDED" "$out/export.log" | tail -3
