#!/usr/bin/env bash
# Build the OpenHarmony HAP using the OHOS Flutter fork.
#
# The OHOS fork (flutter_flutter) is required: stock Flutter has no `build hap`
# subcommand and does not ship the OHOS engine artifacts.
#
# Override the SDK by exporting FLUTTER_OHOS_SDK before invoking.
# Default build target is `hap`; pass `app`, `har`, or `hsp` as the first
# positional arg to switch.

set -euo pipefail

FLUTTER_OHOS_SDK="${FLUTTER_OHOS_SDK:-$HOME/dev/flutter_flutter}"
FLUTTER_BIN="$FLUTTER_OHOS_SDK/bin/flutter"

if [[ ! -x "$FLUTTER_BIN" ]]; then
  echo "error: OHOS Flutter fork not found at $FLUTTER_BIN" >&2
  echo "set FLUTTER_OHOS_SDK to the flutter_flutter checkout (OpenHarmony-SIG fork)" >&2
  exit 1
fi

SDK_CHANNEL="$("$FLUTTER_BIN" --version 2>/dev/null | awk '/channel/ {print; exit}')"
if [[ "$SDK_CHANNEL" != *ohos* ]]; then
  echo "error: $FLUTTER_BIN is not the OHOS fork — refusing to build HAP with it" >&2
  exit 1
fi

if [[ -z "${OHOS_SDK_HOME:-}" && -z "${HOS_SDK_HOME:-}" && -z "${HARMONYOS_SDK_HOME:-}" ]]; then
  echo "warning: no OHOS SDK env var set (OHOS_SDK_HOME / HOS_SDK_HOME / HARMONYOS_SDK_HOME)" >&2
fi

TARGET="${1:-hap}"
shift || true
case "$TARGET" in
hap | app | har | hsp) ;;
*)
  echo "error: unknown OHOS target '$TARGET' (expected hap|app|har|hsp)" >&2
  exit 1
  ;;
esac

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "==> using $FLUTTER_BIN"
"$FLUTTER_BIN" --version | head -2

echo "==> flutter clean"
"$FLUTTER_BIN" clean >/dev/null

echo "==> flutter pub get"
"$FLUTTER_BIN" pub get

echo "==> flutter build $TARGET --release $*"
"$FLUTTER_BIN" build "$TARGET" --release "$@"

echo "==> output: $PROJECT_ROOT/ohos/entry/build/default/outputs/"
