#!/usr/bin/env bash
# Build the aTrust VPN extension shim (libgeektrust_vpn.so).
#
#   ohos/scripts/build-geektrust-vpn.sh
#
# hvigor does not compile ohos/entry/src/main/cpp/geektrust_vpn: the shim ships
# as a committed .so under ohos/entry/libs/arm64-v8a/, so the release image needs
# no C++ toolchain (CLAUDE.md -> OHOS-specific gotchas). Run this whenever
# anything under geektrust_vpn/ changes — test/atrust/geektrust_vpn_artifact_test.dart
# fails until the committed .so carries the digest of the source it was built
# from.
#
# The SDK is a local dependency; override CLD_DIR if it is not where .envrc says.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$ROOT/ohos/entry/src/main/cpp/geektrust_vpn"
OUT="$ROOT/ohos/entry/libs/arm64-v8a/libgeektrust_vpn.so"
CLD_DIR="${CLD_DIR:-$HOME/dev/command-line-tools}"
SDK="$CLD_DIR/sdk/default"
NATIVE="$SDK/openharmony/native"
HMS="$SDK/hms/native"
CMAKE="$NATIVE/build-tools/cmake/bin/cmake"
NINJA="$NATIVE/build-tools/cmake/bin/ninja"
STRIP="$NATIVE/llvm/bin/llvm-strip"

for tool in "$CMAKE" "$NINJA" "$STRIP"; do
  if [[ ! -x "$tool" ]]; then
    printf 'missing %s — is CLD_DIR=%s the command-line-tools root?\n' "$tool" "$CLD_DIR" >&2
    exit 1
  fi
done

build="$(mktemp -d "${TMPDIR:-/tmp}/geektrust-vpn-build.XXXXXX")"
trap 'rm -rf "$build"' EXIT

# The same variables hvigor passes for externalNativeOptions (see the CMakeCache
# hvigor writes under ohos/entry/.cxx for the full list).
"$CMAKE" -S "$SRC" -B "$build" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$HMS/build/cmake/hmos.toolchain.cmake" \
  -DCMAKE_MAKE_PROGRAM="$NINJA" \
  -DCMAKE_BUILD_TYPE=Release \
  -DOHOS_ARCH=arm64-v8a \
  -DOHOS_SDK_NATIVE="$NATIVE" \
  -DHMOS_SDK_NATIVE="$HMS"
"$CMAKE" --build "$build"

"$STRIP" --strip-all "$build/libgeektrust_vpn.so"
mkdir -p "$(dirname "$OUT")"
cp "$build/libgeektrust_vpn.so" "$OUT"
chmod 644 "$OUT"

# Self-checks: the shim has to register itself as a NAPI module (that is how
# ArkTS finds it) and it must not have been linked against anything exotic.
if ! "$NATIVE/llvm/bin/llvm-nm" -D "$OUT" 2>/dev/null | grep -q napi_module_register; then
  echo "libgeektrust_vpn.so does not register a NAPI module" >&2
  exit 1
fi
if ! "$NATIVE/llvm/bin/llvm-nm" -D "$OUT" 2>/dev/null | grep -q "dlopen\|dlsym"; then
  echo "libgeektrust_vpn.so does not resolve dlopen/dlsym" >&2
  exit 1
fi
# The C++ runtime the shim is linked against rides along with it. The extension
# process searches this directory — it says so in its own loader error — but the
# bundle does not otherwise carry libc++_shared.so, and without it the shim fails
# to load with "Error loading shared library libc++_shared.so" and every call
# into the engine dies before it starts.
CXX_LIB="$NATIVE/llvm/lib/aarch64-linux-ohos/libc++_shared.so"
if [[ -f "$CXX_LIB" ]]; then
  cp "$CXX_LIB" "$(dirname "$OUT")/libc++_shared.so"
  chmod 644 "$(dirname "$OUT")/libc++_shared.so"
else
  echo "warning: $CXX_LIB not found; the shim will not load on a device" >&2
fi

ls -l "$OUT"
