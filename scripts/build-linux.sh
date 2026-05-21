#!/usr/bin/env bash
# Build the Linux x64 release bundle using the upstream Flutter SDK.
#
# The OHOS Flutter fork's gen_snapshot miscompiles Linux x64 AOT, producing a
# binary that SIGSEGVs on the io.flutter.ui thread at startup. Always use
# upstream Flutter for Linux builds.
#
# Override the SDK by exporting FLUTTER_UPSTREAM_SDK before invoking.

set -euo pipefail

FLUTTER_UPSTREAM_SDK="${FLUTTER_UPSTREAM_SDK:-/home/zambar/dev/flutter}"
FLUTTER_BIN="$FLUTTER_UPSTREAM_SDK/bin/flutter"

if [[ ! -x "$FLUTTER_BIN" ]]; then
  echo "error: upstream Flutter not found at $FLUTTER_BIN" >&2
  echo "set FLUTTER_UPSTREAM_SDK to a stock flutter checkout" >&2
  exit 1
fi

SDK_CHANNEL="$("$FLUTTER_BIN" --version 2>/dev/null | awk '/channel/ {print; exit}')"
if [[ "$SDK_CHANNEL" == *ohos* ]]; then
  echo "error: $FLUTTER_BIN looks like the OHOS fork — refusing to build Linux release with it" >&2
  exit 1
fi

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "==> using $FLUTTER_BIN"
"$FLUTTER_BIN" --version | head -2

echo "==> flutter clean"
"$FLUTTER_BIN" clean >/dev/null

echo "==> flutter pub get"
"$FLUTTER_BIN" pub get

echo "==> flutter build linux --release $*"
"$FLUTTER_BIN" build linux --release "$@"

echo "==> output: $PROJECT_ROOT/build/linux/x64/release/bundle/techpie"
