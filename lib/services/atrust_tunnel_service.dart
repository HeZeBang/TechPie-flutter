import 'dart:convert';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

/// A refusal reported by the core library, passed through verbatim: the library
/// writes human-readable messages and this never invents its own.
class AtrustTunnelException implements Exception {
  const AtrustTunnelException(this.message);

  final String message;

  @override
  String toString() => 'AtrustTunnelException: $message';
}

/// The tunnel's own liveness, straight from `geektrust_status`. It says nothing
/// about whether the *session* is still good — that is the controller's answer
/// to `onlineInfo`.
class AtrustTunnelStatus {
  const AtrustTunnelStatus({
    required this.alive,
    required this.abi,
    required this.deviceId,
    required this.username,
    required this.vip,
    required this.gateway,
    required this.dialAttempts,
    this.gateways = const [],
    this.tun = const {},
  });

  final bool alive;
  final int abi;
  final String deviceId;
  final String username;
  final String vip;
  final String gateway;
  final int dialAttempts;

  /// The gateway lines the engine flattened out of the policy (`host:port`).
  ///
  /// Only the engine knows them — the session the app holds never carries the
  /// flattening — and a system-VPN shell has to keep them out of the routes it
  /// configures. See [AtrustRouting.withoutGateways].
  final List<String> gateways;

  /// The attached interface's own counters, empty while nothing is attached.
  /// They are the only evidence a data plane is alive on a platform that gives
  /// the engine no log channel.
  final Map<String, int> tun;

  static AtrustTunnelStatus fromJson(Map<String, dynamic> json) =>
      AtrustTunnelStatus(
        alive: json['alive'] == true,
        abi: (json['abi'] as num?)?.toInt() ?? 0,
        deviceId: (json['device_id'] as String?) ?? '',
        username: (json['username'] as String?) ?? '',
        vip: (json['vip'] as String?) ?? '',
        gateway: (json['gateway'] as String?) ?? '',
        dialAttempts: (json['dial_attempts'] as num?)?.toInt() ?? 0,
        gateways: (json['gateways'] as List?)?.whereType<String>().toList() ??
            const [],
        tun: {
          if (json['tun'] case final Map<dynamic, dynamic> counters)
            for (final entry in counters.entries)
              if (entry.value is num) '${entry.key}': (entry.value as num).toInt(),
        },
      );
}

/// The packet side of the aTrust integration: a thin binding over
/// `libgeektrust.so`, nothing else.
///
/// The control plane authenticates, then hands over the session and the
/// controller's routing policy as JSON; this class turns that into local
/// SOCKS5/HTTP listeners — the desktop and in-app shape — or, once the tun-fd
/// inbound lands in the library, into packets from a platform VPN shell.
///
/// A platform without the library (or with one that does not speak this ABI)
/// loads as *unsupported* rather than throwing: the app has to keep working
/// when the tunnel does not.
class AtrustTunnelService {
  AtrustTunnelService._({
    required DynamicLibrary library,
    required this.version,
    required this.abi,
    required this.sourceDigest,
  }) : unsupportedReason = '',
       _library = library {
    _init = library.lookupFunction<_InitNative, _InitDart>('geektrust_init');
    _startProxies = library
        .lookupFunction<_ProxiesNative, _ProxiesDart>('geektrust_start_proxies');
    _attachTunFd = library
        .lookupFunction<_TunNative, _TunDart>('geektrust_attach_tun_fd');
    _status = library
        .lookupFunction<_StatusNative, _StatusDart>('geektrust_status');
    _close = library.lookupFunction<_CloseNative, _CloseDart>('geektrust_close');
  }

  AtrustTunnelService._unsupported(this.unsupportedReason)
    : _library = null,
      version = '',
      abi = 0,
      sourceDigest = '';

  /// The ABI this app is written against; the library refuses anything else.
  static const expectedAbi = 1;

  /// Resolved by the loader through the bundle's own search path (`$ORIGIN/lib`
  /// on Linux, the APK's `lib/<abi>/` on Android, the module's libs on OHOS).
  static const defaultLibraryName = 'libgeektrust.so';

  static const _markerPattern = r'TECHPIE-GEEKTRUST=(\d+):([^:]*):([0-9a-f]{64})';
  static const _errorBytes = 1024;
  static const _statusBytes = 4096;

  final DynamicLibrary? _library;

  /// The library's own version string (`<git describe>`), empty when it never
  /// loaded.
  final String version;

  /// The ABI the loaded library speaks, 0 when it never loaded.
  final int abi;

  /// The digest of the sources it was built from — the same value the app
  /// recomputes from the pinned submodule in its artifact test.
  final String sourceDigest;

  /// Why this platform cannot use the tunnel, when [isSupported] is false.
  final String unsupportedReason;

  bool get isSupported => _library != null;

  late final _InitDart _init;
  late final _ProxiesDart _startProxies;
  late final _TunDart _attachTunFd;
  late final _StatusDart _status;
  late final _CloseDart _close;

  /// Loads the library and checks that it speaks [expectedAbi]. Never throws.
  factory AtrustTunnelService.load({String libraryPath = defaultLibraryName}) {
    // A device verification needs this in the log: the panel can only show a
    // line, and "why is the tunnel unavailable" is the first question.
    debugPrint('[atrust] loading $libraryPath');
    final DynamicLibrary library;
    try {
      library = DynamicLibrary.open(libraryPath);
    } catch (error) {
      debugPrint('[atrust] tunnel unavailable: $libraryPath ($error)');
      return AtrustTunnelService._unsupported(
        '$libraryPath could not be loaded ($error)',
      );
    }

    final String version;
    try {
      version = library
          .lookupFunction<_VersionNative, _VersionDart>('geektrust_version')()
          .toDartString();
    } catch (error) {
      return AtrustTunnelService._unsupported(
        '$libraryPath does not look like the core library ($error)',
      );
    }
    final marker = RegExp(_markerPattern).firstMatch(version);
    if (marker == null) {
      return AtrustTunnelService._unsupported(
        '$libraryPath carries no provenance marker ("$version")',
      );
    }
    final abi = int.parse(marker.group(1)!);
    if (abi != expectedAbi) {
      return AtrustTunnelService._unsupported(
        '$libraryPath speaks ABI $abi, this app needs $expectedAbi',
      );
    }
    final service = AtrustTunnelService._(
      library: library,
      version: marker.group(2) ?? '',
      abi: abi,
      sourceDigest: marker.group(3) ?? '',
    );
    debugPrint(
      '[atrust] tunnel library ${service.version} (abi ${service.abi})',
    );
    return service;
  }

  /// Brings the tunnel up for [sessionJson] (`sid`, `device_id`, `username`,
  /// `base_url`, `gateways`, `dns`) and [policyJson] (the controller's
  /// `clientResource` body). Calling it again replaces the session.
  void start({required String sessionJson, required String policyJson}) {
    _requireLibrary();
    final session = sessionJson.toNativeUtf8();
    final policy = policyJson.toNativeUtf8();
    final error = calloc<Uint8>(_errorBytes);
    try {
      final code = _init(session, policy, error.cast(), _errorBytes);
      if (code != 0) throw AtrustTunnelException(_message(error));
    } finally {
      malloc.free(session);
      malloc.free(policy);
      calloc.free(error);
    }
  }

  /// Starts the local proxies. An empty address disables that listener.
  void startProxies({
    required String socksAddress,
    String httpAddress = '',
  }) {
    _requireLibrary();
    final socks = socksAddress.toNativeUtf8();
    final http = httpAddress.toNativeUtf8();
    final error = calloc<Uint8>(_errorBytes);
    try {
      final code = _startProxies(socks, http, error.cast(), _errorBytes);
      if (code != 0) throw AtrustTunnelException(_message(error));
    } finally {
      malloc.free(socks);
      malloc.free(http);
      calloc.free(error);
    }
  }

  /// The system-VPN shape: hand over the file descriptor a platform VPN shell
  /// created. The library reports that this is not wired yet — this binding
  /// passes that through rather than pretending otherwise.
  void attachTunFd(int descriptor) {
    _requireLibrary();
    final error = calloc<Uint8>(_errorBytes);
    try {
      final code = _attachTunFd(descriptor, error.cast(), _errorBytes);
      if (code != 0) throw AtrustTunnelException(_message(error));
    } finally {
      calloc.free(error);
    }
  }

  AtrustTunnelStatus status() {
    _requireLibrary();
    final buffer = calloc<Uint8>(_statusBytes);
    try {
      final code = _status(buffer.cast(), _statusBytes);
      if (code != 0) throw AtrustTunnelException(_message(buffer));
      final decoded = jsonDecode(buffer.cast<Utf8>().toDartString());
      return AtrustTunnelStatus.fromJson(decoded as Map<String, dynamic>);
    } finally {
      calloc.free(buffer);
    }
  }

  /// Tears the tunnel and the listeners down. Safe to call twice, and safe on
  /// an unsupported platform.
  void stop() {
    if (_library == null) return;
    _close();
  }

  void _requireLibrary() {
    if (_library == null) {
      throw AtrustTunnelException('the tunnel is not available: $unsupportedReason');
    }
  }

  static String _message(Pointer<Uint8> error) {
    final text = error.cast<Utf8>().toDartString();
    return text.isEmpty ? 'the core library refused the call' : text;
  }
}

typedef _VersionNative = Pointer<Utf8> Function();
typedef _VersionDart = Pointer<Utf8> Function();
typedef _InitNative =
    Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Int32);
typedef _InitDart =
    int Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, int);
typedef _ProxiesNative =
    Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Int32);
typedef _ProxiesDart =
    int Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, int);
typedef _TunNative = Int32 Function(Int32, Pointer<Utf8>, Int32);
typedef _TunDart = int Function(int, Pointer<Utf8>, int);
typedef _StatusNative = Int32 Function(Pointer<Utf8>, Int32);
typedef _StatusDart = int Function(Pointer<Utf8>, int);
typedef _CloseNative = Void Function();
typedef _CloseDart = void Function();
