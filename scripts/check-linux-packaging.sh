#!/usr/bin/env bash
# Exercise both package formats without rebuilding Flutter or publishing.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/bundle/lib" "$work/bundle/data"
cc -x c -o "$work/bundle/techpie" - <<'C'
#include <stdio.h>
int main(int argc, char **argv) {
  if (argc != 2) return 1;
  puts(argv[1]);
  return 0;
}
C
"$root/scripts/build-appimage.sh" "$work/bundle" 1.2.3 "$work/dist"
APPIMAGE_EXTRACT_AND_RUN=1 "$work/dist/TechPie-1.2.3-linux-x86-64.AppImage" \
  'argument with spaces' > "$work/arguments"
grep -Fx 'argument with spaces' "$work/arguments"

tar -czf "$work/TechPie-1.2.3-linux-x86-64.tar.gz" -C "$work" bundle
python3 "$root/scripts/prepare-aur.py" --tag v1.2.3+4 \
  --bundle "$work/TechPie-1.2.3-linux-x86-64.tar.gz" --output "$work/aur"
cp "$work/TechPie-1.2.3-linux-x86-64.tar.gz" "$work/aur/"
cp "$root/assets/icon/icon.png" "$work/aur/techpie.png"
cp "$root/README.md" "$work/aur/README.md"
if python3 "$root/scripts/prepare-aur.py" --tag v1.2.3-rc.1+4 \
  --bundle "$work/TechPie-1.2.3-linux-x86-64.tar.gz" --output "$work/rejected" \
  > "$work/rejection.log" 2>&1; then
  echo 'A candidate release was incorrectly accepted for AUR.' >&2
  exit 1
fi
grep -F 'AUR accepts stable' "$work/rejection.log"
cd "$work/aur"
bash -n PKGBUILD
makepkg --printsrcinfo > .SRCINFO
grep -Fx $'\tpkgver = 1.2.3' .SRCINFO
grep -Fx $'\tpkgrel = 4' .SRCINFO
makepkg --nodeps --noconfirm --nosign
bsdtar -tf techpie-bin-1.2.3-4-x86_64.pkg.tar.zst > "$work/contents"
grep -Fx 'opt/techpie/techpie' "$work/contents"
grep -Fx 'usr/bin/techpie' "$work/contents"
grep -Fx 'usr/share/applications/techpie.desktop' "$work/contents"
echo 'AppImage launch, AUR release selection, metadata and Arch package layout passed.'
