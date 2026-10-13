#!/usr/bin/env bash
# Build the prebuilt eCard bind packet reader (libecardbind_reader.so).
#
#   ohos/scripts/build-ecardbind-reader.sh
#
# hvigor does not compile ohos/entry/src/main/cpp. The module ships a committed
# .so under ohos/entry/libs/arm64-v8a/ instead, so the release image needs no C++
# toolchain — worth 4.5 GB of image and a manual republish step (CLAUDE.md ->
# OHOS-specific gotchas). Run this whenever anything under src/main/cpp changes:
# test/ecard_bind_reader_artifact_test.dart fails until the committed .so carries
# the digest of the source it was built from.
#
# The SDK is a local dependency; override CLD_DIR if it is not where .envrc says.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CPP_DIR="$ROOT/ohos/entry/src/main/cpp"
OUT="$ROOT/ohos/entry/libs/arm64-v8a/libecardbind_reader.so"
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

build="$(mktemp -d "${TMPDIR:-/tmp}/ecardbind-build.XXXXXX")"
trap 'rm -rf "$build"' EXIT

# The same variables hvigor passes for externalNativeOptions — the toolchain file
# comes from hms/native, the sysroots and clang from openharmony/native (hvigor's
# own CMakeCache.txt under ohos/entry/.cxx lists them all).
"$CMAKE" -S "$CPP_DIR" -B "$build" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$HMS/build/cmake/hmos.toolchain.cmake" \
  -DCMAKE_MAKE_PROGRAM="$NINJA" \
  -DCMAKE_BUILD_TYPE=Release \
  -DOHOS_ARCH=arm64-v8a \
  -DOHOS_SDK_NATIVE="$NATIVE" \
  -DHMOS_SDK_NATIVE="$HMS"
"$CMAKE" --build "$build"

# Stripped: this file is what the repository keeps, and the hap carries it as is.
# 644 because a shared library is data here, not something anyone runs.
"$STRIP" --strip-all "$build/libecardbind_reader.so"
mkdir -p "$(dirname "$OUT")"
cp "$build/libecardbind_reader.so" "$OUT"
chmod 644 "$OUT"
ls -l "$OUT"
