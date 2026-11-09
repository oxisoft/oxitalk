#!/usr/bin/env bash
# Packs the Linux release bundle into the files of a GitHub release:
#   oxitalk-<version>-linux-x86_64.tar.gz   the bundle as it is
#   oxitalk-<version>-x86_64.AppImage        runs on most distributions (GTK 3 and libsecret
#                                            from the system, like the tarball)
#   oxitalk-<version>-x86_64.flatpak         single-file Flatpak on the GNOME 51 runtime
#
#   packaging/linux/build.sh <version> <out dir>
#
# Run from the repository root after `flutter build linux --release` in apps/oxitalk.
# Needs flatpak-builder (or the org.flatpak.Builder Flatpak) with org.gnome.Sdk//51 and
# org.gnome.Platform//51 installed, and curl for appimagetool (pinned by SHA-256 below).
set -euo pipefail

version=$1
out=$(realpath -m "$2")
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
bundle=$root/apps/oxitalk/build/linux/x64/release/bundle
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

[ -x "$bundle/oxitalk" ] || { echo "no release bundle at $bundle"; exit 1; }
mkdir -p "$out"

# The metainfo with this version.
metainfo=$work/io.oxisoft.oxitalk.metainfo.xml
sed -e "s/@VERSION@/$version/" -e "s/@DATE@/$(date -u +%F)/" \
  "$here/io.oxisoft.oxitalk.metainfo.xml" >"$metainfo"

echo "== tarball"
cp -a "$bundle" "$work/oxitalk-$version"
tar -C "$work" -czf "$out/oxitalk-$version-linux-x86_64.tar.gz" "oxitalk-$version"

echo "== AppImage"
tool_sha=ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0
tool=$work/appimagetool
curl -fsSL -o "$tool" https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-x86_64.AppImage
echo "$tool_sha  $tool" | sha256sum -c -
chmod +x "$tool"
appdir=$work/OxiTalk.AppDir
mkdir -p "$appdir/usr/share/metainfo"
cp -a "$bundle" "$appdir/oxitalk"
cp "$root/apps/oxitalk/linux/io.oxisoft.oxitalk.desktop" "$appdir/"
cp "$bundle/data/app_icon.png" "$appdir/io.oxisoft.oxitalk.png"
cp "$metainfo" "$appdir/usr/share/metainfo/io.oxisoft.oxitalk.appdata.xml"
cat >"$appdir/AppRun" <<'EOF'
#!/bin/sh
exec "${APPDIR:-$(dirname "$(readlink -f "$0")")}/oxitalk/oxitalk" "$@"
EOF
chmod +x "$appdir/AppRun"
# --appimage-extract-and-run: no FUSE needed where this runs (CI containers).
ARCH=x86_64 "$tool" --appimage-extract-and-run --no-appstream "$appdir" \
  "$out/oxitalk-$version-x86_64.AppImage"

echo "== Flatpak"
stage=$work/flatpak/stage
mkdir -p "$stage"
cp "$here/io.oxisoft.oxitalk.yml" "$work/flatpak/"
cp -a "$bundle" "$stage/bundle"
cp "$root/apps/oxitalk/linux/io.oxisoft.oxitalk.desktop" "$metainfo" "$stage/"
if command -v flatpak-builder >/dev/null; then
  builder=(flatpak-builder)
else
  builder=(flatpak run --filesystem="$work" org.flatpak.Builder)
fi
(
  cd "$work/flatpak"
  "${builder[@]}" --user --force-clean --disable-rofiles-fuse --repo=repo build io.oxisoft.oxitalk.yml
  flatpak build-bundle repo "$out/oxitalk-$version-x86_64.flatpak" io.oxisoft.oxitalk
)

ls -la "$out"
