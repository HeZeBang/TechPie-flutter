import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// The OHOS packet reader ships as a prebuilt shared object: hvigor does not
/// compile `ohos/entry/src/main/cpp` at all, which is what lets the release
/// image carry no C++ toolchain (see CLAUDE.md -> OHOS-specific gotchas, and
/// `ohos/scripts/build-ecardbind-reader.sh`).
///
/// Nothing in an ordinary build would notice a source edit that was never
/// compiled — no compiler ever sees the two together — so the build script
/// embeds a digest of that source tree in the .so and this recomputes it. A
/// failure below means exactly one thing: rebuild the reader and commit it.
void main() {
  const cppDirectory = 'ohos/entry/src/main/cpp/ecardbind_reader';
  final library = File('ohos/entry/libs/arm64-v8a/libecardbind_reader.so');

  test('the prebuilt reader was built from the source in this tree', () {
    final embedded = RegExp(r'TECHPIE-ECARDBIND-SRC-SHA256=([0-9a-f]{64})')
        .firstMatch(latin1.decode(library.readAsBytesSync()))
        ?.group(1);

    expect(
      embedded,
      isNotNull,
      reason: '$library carries no source digest — was it built at all?',
    );
    expect(
      embedded,
      sourceDigest(Directory(cppDirectory)),
      reason: 'the reader is stale: run ohos/scripts/build-ecardbind-reader.sh '
          'and commit what it writes',
    );
  });

  test('the prebuilt reader is a 64-bit ARM shared object', () {
    final header = library.readAsBytesSync().sublist(0, 20);

    expect(header.sublist(0, 4), [0x7f, 0x45, 0x4c, 0x46], reason: 'not ELF');
    expect(header[4], 2, reason: 'not 64-bit');
    expect(header[5], 1, reason: 'not little-endian');
    expect(header[16] | (header[17] << 8), 3, reason: 'not a shared object');
    expect(header[18] | (header[19] << 8), 0xb7, reason: 'not AArch64');
  });
}

/// The digest the build embeds, recomputed from the source: one line per file —
/// `<path relative to [cpp]> <sha256 of its bytes>` — over every file under it,
/// sorted by path, minus `types/` (ArkTS-facing declarations, not compiled
/// here). `CMakeLists.txt` is a line too, so adding a source invalidates it.
///
/// `CMakeLists.txt` computes the other half of this recipe; the test above is
/// what notices if the two ever disagree.
String sourceDigest(Directory cpp) {
  // A directory's uri path always ends in '/', so trimming it off the file's own
  // uri path is the relative name — and '/'-separated on every platform.
  final base = cpp.absolute.uri.path;
  final paths = cpp
      .listSync(recursive: true)
      .whereType<File>()
      .map((file) => file.absolute.uri.path)
      .where((path) => path.startsWith(base))
      .map((path) => path.substring(base.length))
      .where((path) => !path.startsWith('types/'))
      .toList()
    ..sort();

  final lines = StringBuffer();
  for (final path in paths) {
    final bytes = File('${cpp.path}/$path').readAsBytesSync();
    lines.writeln('$path ${sha256.convert(bytes)}');
  }
  return sha256.convert(utf8.encode(lines.toString())).toString();
}
