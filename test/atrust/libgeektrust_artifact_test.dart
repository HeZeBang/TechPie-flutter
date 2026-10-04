import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_test/flutter_test.dart';

/// The core library is built on a developer machine and committed, because an
/// OHOS build needs the vendor SDK and cannot run in CI. Nothing in a Flutter
/// build would notice a library that came from different sources, so each one
/// embeds `TECHPIE-GEEKTRUST=<abi>:<version>:<source digest>` and this
/// recomputes the digest from the pinned submodule.
///
/// A failure here means exactly one thing: rebuild the libraries from the
/// submodule's `build.sh` and commit them.
void main() {
  const submodule = 'third_party/geektrust-core';

  /// Committed library → the ELF machine it must be built for.
  const libraries = {
    'ohos/entry/libs/arm64-v8a/libgeektrust.so': 0xb7, // EM_AARCH64
    'linux/libgeektrust.so': 0x3e, // EM_X86_64
  };

  const abi = 1;

  test('every committed library was built from the pinned submodule', () {
    final digest = sourceDigest(Directory(submodule));

    for (final entry in libraries.entries) {
      final file = File(entry.key);
      expect(file.existsSync(), isTrue, reason: '${entry.key} is missing');

      final bytes = file.readAsBytesSync();
      expect(
        bytes.sublist(0, 4),
        [0x7f, 0x45, 0x4c, 0x46],
        reason: '${entry.key} is not an ELF file',
      );
      expect(
        bytes[18] | (bytes[19] << 8),
        entry.value,
        reason: '${entry.key} is built for the wrong architecture',
      );

      final marker = RegExp(
        r'TECHPIE-GEEKTRUST=(\d+):([^:]*):([0-9a-f]{64})',
      ).firstMatch(latin1.decode(bytes));
      expect(
        marker,
        isNotNull,
        reason: '${entry.key} carries no provenance marker — was it built by '
            'the submodule\'s build.sh?',
      );
      expect(
        int.parse(marker!.group(1)!),
        abi,
        reason: '${entry.key} speaks a different ABI than this app',
      );
      expect(
        marker.group(3),
        digest,
        reason:
            '${entry.key} was not built from the pinned submodule: run '
            'third_party/geektrust-core/build.sh and commit the result',
      );
    }
  });
}

/// The digest recipe, frozen in the submodule's `build.sh`: every file under the
/// submodule except anything under `.git` or `dist/`, sorted by path, each
/// contributing `"<path>\n<sha256 of its bytes, lowercase hex>\n"` — the sha256
/// of that UTF-8 text is the digest. Nothing else is added, and the app must
/// keep using this exact recipe.
String sourceDigest(Directory root) {
  final base = root.absolute.uri.path;
  final paths =
      root
          .listSync(recursive: true)
          .whereType<File>()
          .map((file) => file.absolute.uri.path)
          .where((path) => path.startsWith(base))
          .map((path) => path.substring(base.length))
          .where((path) => path != '.git')
          .where((path) => !path.startsWith('.git/'))
          .where((path) => !path.startsWith('dist/'))
          .toList()
        ..sort();

  final lines = StringBuffer();
  for (final path in paths) {
    final bytes = File('${root.path}/$path').readAsBytesSync();
    lines.write('$path\n${sha256.convert(bytes)}\n');
  }
  return sha256.convert(utf8.encode(lines.toString())).toString();
}
