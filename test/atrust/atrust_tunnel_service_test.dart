import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/services/atrust_tunnel_service.dart';

/// Drives the *committed* library through the FFI binding — the same artifact
/// the app loads, called the same way. The artifact's own provenance is checked
/// in `libgeektrust_artifact_test.dart`; this file is about the binding.
///
/// Only the Linux artifact is loadable from a test host; an OHOS library is
/// covered by that provenance test instead.
void main() {
  const linuxLibrary = 'linux/libgeektrust.so';

  test('loads the committed library and speaks its ABI', () {
    final tunnel = AtrustTunnelService.load(libraryPath: linuxLibrary);

    expect(tunnel.isSupported, isTrue, reason: tunnel.unsupportedReason);
    expect(tunnel.abi, AtrustTunnelService.expectedAbi);
    expect(tunnel.version, isNotEmpty);
    expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(tunnel.sourceDigest), isTrue);

    // Nothing has been started, yet the library still answers — and keeps
    // answering after being torn down twice.
    final before = tunnel.status();
    expect(before.alive, isFalse);
    expect(before.abi, AtrustTunnelService.expectedAbi);
    tunnel.stop();
    tunnel.stop();
    expect(tunnel.status().alive, isFalse);
  });

  test('a refusal comes from the library, as a typed failure', () {
    final tunnel = AtrustTunnelService.load(libraryPath: linuxLibrary);

    // Proxies cannot start without a session; the library says so in its own
    // words, and the binding passes that through instead of guessing.
    expect(
      () => tunnel.startProxies(socksAddress: '127.0.0.1:0'),
      throwsA(
        isA<AtrustTunnelException>().having(
          (error) => error.message,
          'message',
          isNotEmpty,
        ),
      ),
    );

    // The tun-fd shape is not wired into the library yet: calling it must fail
    // loudly and say so, never silently succeed.
    expect(
      () => tunnel.attachTunFd(-1),
      throwsA(
        isA<AtrustTunnelException>().having(
          (error) => error.message,
          'message',
          contains('not implemented'),
        ),
      ),
    );
  });

  test('a missing library is reported, not thrown', () {
    final tunnel = AtrustTunnelService.load(libraryPath: 'no/such/libgeektrust.so');

    expect(tunnel.isSupported, isFalse);
    expect(tunnel.unsupportedReason, isNotEmpty);
    // Every call refuses cleanly rather than crashing the app that could not
    // ship the library.
    expect(
      () => tunnel.status(),
      throwsA(isA<AtrustTunnelException>()),
    );
    tunnel.stop(); // and teardown stays a no-op
  });

  test('the shipped library is the one the bundle would load', () {
    // Guards the placement table: the file the build installs is the file this
    // binding can open by name from the app bundle.
    expect(File(linuxLibrary).existsSync(), isTrue);
    expect(File('ohos/entry/libs/arm64-v8a/libgeektrust.so').existsSync(), isTrue);
  });
}
