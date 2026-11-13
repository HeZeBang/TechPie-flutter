#!/usr/bin/env bash
# Export an existing Flutter bundle as a Flatpak single-file bundle.
set -euo pipefail
if [[ $# -ne 3 ]]; then
  echo 'usage: build-flatpak.sh <bundle> <release-name> <output-directory>' >&2
  exit 2
fi
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
bundle="$(realpath "$1")"
version="$2"
if [[ ! -x "$bundle/techpie" || ! -d "$bundle/lib" || ! -d "$bundle/data" ]]; then
  echo 'Expected a Flutter Linux bundle containing techpie, lib/ and data/.' >&2
  exit 1
fi
mkdir -p "$3"
out="$(realpath "$3")"
work="$(mktemp -d "$out/flatpak-build.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
build="$work/app"
app_id=club.geekpie.TechPie
branch=stable
if [[ "$version" == *-* ]]; then branch=beta; fi
mkdir -p "$build/files/lib/techpie" "$build/files/bin" \
  "$build/files/share/applications" "$build/files/share/icons/hicolor/512x512/apps" \
  "$build/files/share/metainfo"
cp "$root/packaging/flatpak/metadata" "$build/metadata"
cp -a "$bundle/." "$build/files/lib/techpie/"
# Host shell extensions use the native package's snapshot location, outside this sandbox.
rm -rf -- "$build/files/lib/techpie/widgets"
install -m755 "$root/packaging/flatpak/techpie" "$build/files/bin/techpie"
sed "s/^Icon=.*/Icon=$app_id/" "$root/packaging/linux/techpie.desktop" \
  > "$build/files/share/applications/$app_id.desktop"
convert "$root/assets/icon/icon.png" -resize 512x512 \
  "$build/files/share/icons/hicolor/512x512/apps/$app_id.png"
install -m644 "$root/packaging/flatpak/$app_id.metainfo.xml" "$build/files/share/metainfo/$app_id.metainfo.xml"
desktop-file-validate "$build/files/share/applications/$app_id.desktop"
# Keep the prebuilt runner's existing GApplication identity; permit only that name.
flatpak build-finish --command=techpie \
  --share=network --share=ipc --socket=wayland --socket=fallback-x11 \
  --socket=pulseaudio --device=dri --talk-name=org.freedesktop.secrets \
  --own-name=com.example.techpie "$build"
flatpak build-export --subject="TechPie $version" "$work/repo" "$build" "$branch"
flatpak build-bundle --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo \
  "$work/repo" "$out/TechPie-${version}-linux-x86-64.flatpak" "$app_id" "$branch"
