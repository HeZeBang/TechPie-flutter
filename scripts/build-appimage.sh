#!/usr/bin/env bash
# Repackage an existing Flutter Linux bundle; GTK/WebKit remain system libraries.
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo 'usage: build-appimage.sh <bundle> <release-name> <output-directory>' >&2
  exit 2
fi
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
bundle="$(realpath "$1")"
version="$2"
mkdir -p "$3"
out="$(realpath "$3")"
if [[ ! -x "$bundle/techpie" || ! -d "$bundle/lib" || ! -d "$bundle/data" ]]; then
  echo 'Expected a Flutter Linux bundle containing techpie, lib/ and data/.' >&2
  exit 1
fi

tools="${PACKAGING_TOOLS_DIR:-$root/build/packaging-tools}"
mkdir -p "$tools"
tool="$tools/appimagetool"
runtime="$tools/runtime-x86_64"
download_asset() {
  local asset="$1" path="$2"
  local headers=(-H 'Accept: application/octet-stream')
  if [[ -n "${GH_TOKEN:-}" ]]; then
    headers+=(-H "Authorization: Bearer $GH_TOKEN")
  fi
  echo "Downloading ${path##*/} from GitHub release asset $asset"
  curl -fsSL --retry 3 "${headers[@]}" "https://api.github.com/repos/AppImage/$asset" -o "$path.tmp"
  mv "$path.tmp" "$path"
}

if [[ ! -f "$tool" ]]; then
  download_asset appimagetool/releases/assets/324406736 "$tool"
fi
if [[ ! -f "$runtime" ]]; then
  download_asset type2-runtime/releases/assets/657374641 "$runtime"
fi
printf '%s  %s\n' \
  ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0 "$tool" \
  617aa77314d57c8b8e4fae9c3f0b35af7b30d5529cb69e98f64f92510ed98a46 "$runtime" \
  | sha256sum --check --status
chmod +x "$tool"

appdir="$(mktemp -d "$out/TechPie.AppDir.XXXXXX")"
trap 'rm -rf -- "$appdir"' EXIT
mkdir -p "$appdir/usr/lib/techpie" "$appdir/usr/bin" \
  "$appdir/usr/share/applications" "$appdir/usr/share/icons/hicolor/512x512/apps"
cp -a "$bundle/." "$appdir/usr/lib/techpie/"
install -m755 "$root/packaging/linux/AppRun" "$appdir/AppRun"
install -m644 "$root/packaging/linux/techpie.desktop" "$appdir/usr/share/applications/techpie.desktop"
install -m644 "$root/assets/icon/icon.png" "$appdir/usr/share/icons/hicolor/512x512/apps/techpie.png"
ln -s ../lib/techpie/techpie "$appdir/usr/bin/techpie"
ln -s usr/share/applications/techpie.desktop "$appdir/techpie.desktop"
ln -s usr/share/icons/hicolor/512x512/apps/techpie.png "$appdir/techpie.png"
ln -s techpie.png "$appdir/.DirIcon"
desktop-file-validate "$appdir/techpie.desktop"
ARCH=x86_64 VERSION="$version" "$tool" --appimage-extract-and-run \
  --no-appstream --runtime-file "$runtime" "$appdir" \
  "$out/TechPie-${version}-linux-x86-64.AppImage"
