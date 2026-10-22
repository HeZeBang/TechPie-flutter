#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/.flutter-version")"

if [[ -n "${TECHPIE_FLUTTER_ROOT:-}" ]]; then
  FLUTTER="$TECHPIE_FLUTTER_ROOT/bin/flutter"
elif [[ -x "$ROOT/.cache/flutter-$VERSION/flutter/bin/flutter" ]]; then
  FLUTTER="$ROOT/.cache/flutter-$VERSION/flutter/bin/flutter"
else
  FLUTTER="$(command -v flutter || true)"
fi

if [[ -z "$FLUTTER" || ! -x "$FLUTTER" ]]; then
  echo "Flutter $VERSION is required. Set TECHPIE_FLUTTER_ROOT to its SDK directory." >&2
  exit 1
fi

SDK_INFO="$("$FLUTTER" --version --machine)"
SDK_VERSION="$(printf '%s\n' "$SDK_INFO" | sed -n 's/.*"frameworkVersion":[[:space:]]*"\([^"]*\)".*/\1/p')"
if [[ "$SDK_VERSION" != "$VERSION" ]]; then
  printf 'Flutter %s is required for upstream targets. This SDK reports:\n%s\n' "$VERSION" "$SDK_INFO" >&2
  exit 1
fi

if [[ "$(uname -s)" == Darwin ]]; then
  export PATH="$ROOT/scripts/apple-tools:$PATH"
fi

exec "$FLUTTER" "$@"
