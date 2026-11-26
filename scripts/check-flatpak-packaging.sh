#!/usr/bin/env bash
# Install a generated fixture in a temporary installation and run it in the runtime.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/bundle/lib" "$work/bundle/data" "$work/bundle/widgets"
cc -x c -o "$work/bundle/techpie" - <<'C'
#include <stdio.h>
int main(int argc, char **argv) {
  if (argc != 2) return 1;
  puts(argv[1]);
  return 0;
}
C
"$root/scripts/build-flatpak.sh" "$work/bundle" 1.2.3-rc.1 "$work/dist"
export FLATPAK_USER_DIR="$work/installation"
flatpak install --user --noninteractive --no-deps "$work/dist/TechPie-1.2.3-rc.1-linux-x86-64.flatpak"
flatpak info --user --show-metadata club.geekpie.TechPie//beta > "$work/metadata"
grep -Fx 'runtime=org.gnome.Platform/x86_64/51' "$work/metadata"
grep -Fx 'org.freedesktop.secrets=talk' "$work/metadata"
if grep -q '^filesystems=' "$work/metadata"; then
  echo 'The Flatpak unexpectedly grants host filesystem access.' >&2
  exit 1
fi
flatpak run --user club.geekpie.TechPie//beta 'argument with spaces' > "$work/arguments"
grep -Fx 'argument with spaces' "$work/arguments"
flatpak run --user --command=sh club.geekpie.TechPie//beta -c \
  'test -f /app/share/applications/club.geekpie.TechPie.desktop && test ! -d /app/lib/techpie/widgets'
echo 'Flatpak installation, runtime, permissions, beta branch and argument forwarding passed.'
