import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_test/flutter_test.dart';

/// The VPN extension's NAPI shim is committed as a prebuilt `.so` — hvigor never
/// compiles `ohos/entry/src/main/cpp/geektrust_vpn`, because the OHOS build image
/// deliberately carries no C++ toolchain. Nothing in a build would notice a shim
/// built from different sources, so the digest of that directory is embedded in
/// the artifact and recomputed here.
///
/// A failure means one thing: run `ohos/scripts/build-geektrust-vpn.sh` and
/// commit what it writes.
void main() {
  const sourceDirectory = 'ohos/entry/src/main/cpp/geektrust_vpn';
  final library = File('ohos/entry/libs/arm64-v8a/libgeektrust_vpn.so');

  test('the committed shim was built from the source in this tree', () {
    final bytes = library.readAsBytesSync();

    // An aarch64 shared object, like everything else in that directory.
    expect(bytes.sublist(0, 4), [0x7f, 0x45, 0x4c, 0x46]);
    expect(bytes[18] | (bytes[19] << 8), 0xb7);

    final embedded = RegExp(r'TECHPIE-GEEKTRUST-VPN=([0-9a-f]{64})')
        .firstMatch(latin1.decode(bytes))
        ?.group(1);
    expect(
      embedded,
      isNotNull,
      reason: '$library carries no source digest — was it built by the script?',
    );
    expect(
      embedded,
      sourceDigest(Directory(sourceDirectory)),
      reason:
          'the shim is stale: run ohos/scripts/build-geektrust-vpn.sh and '
          'commit what it writes',
    );
  });
}

/// The digest recipe, frozen in that directory's `CMakeLists.txt`: one line per
/// file — `<path relative to the directory> <sha256 of its bytes>` — over every
/// file under it, sorted by path, minus `types/` (ArkTS-facing declarations, not
/// compiled here). `CMakeLists.txt` is a line too, so adding a source
/// invalidates the digest.
String sourceDigest(Directory root) {
  final base = root.absolute.uri.path;
  final paths =
      root
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
    final bytes = File('${root.path}/$path').readAsBytesSync();
    lines.write('$path ${sha256.convert(bytes)}\n');
  }
  return sha256.convert(utf8.encode(lines.toString())).toString();
}
