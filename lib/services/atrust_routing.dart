/// Whether the app's own campus traffic goes through the aTrust tunnel — and
/// the single place that answers "through what".
///
/// The tunnel only carries what the controller's policy authorizes, which is
/// the campus: routing anything else into it would simply hang. So a request is
/// sent to the local SOCKS5 proxy only when it targets a campus host, and only
/// while this is armed.
///
/// It is off until asked for: the tunnel is a diagnostic until the desktop path
/// has been verified end to end from the app itself.
abstract final class AtrustRouting {
  /// Whether campus hosts are sent through the tunnel's SOCKS5 proxy.
  static bool enabled = false;

  /// Where the core library serves SOCKS5 (`geektrust_start_proxies`).
  static String socksProxy = '127.0.0.1:1080';

  /// Hosts the tunnel exists for: the campus's own namespace.
  static bool isCampusHost(String host) =>
      host == 'shanghaitech.edu.cn' || host.endsWith('.shanghaitech.edu.cn');

  /// The `HttpClient.findProxy` hookup: campus hosts through the tunnel while it
  /// is armed, everything else straight out.
  static String forUri(Uri uri) =>
      enabled && socksProxy.isNotEmpty && isCampusHost(uri.host)
      ? 'SOCKS5 $socksProxy'
      : 'DIRECT';

  /// The prefixes in [prefixes] with every IPv4 address in [gateways] cut out.
  ///
  /// A gateway is where the tunnel begins, so it has to stay reachable *outside*
  /// the interface that carries it: routing it in turns the engine's own dial to
  /// it into a flow over the tunnel being built, which the device side refuses
  /// (`ErrGatewayLoop`) — and the tunnel then dies with the very interface it
  /// created. A route list has no "except", so an excluded address is removed by
  /// splitting its covering prefix into the prefixes around it: the complement
  /// of one address inside a /8 is at most 24 entries, and every address that is
  /// not excluded stays routed.
  ///
  /// `[v6]:port` entries exclude nothing: the interface carries IPv4 only.
  ///
  /// Ported from the OHOS shell's `GeekTrustVpnRoutes.ets`, which is where this
  /// was first needed; the system-VPN shells share it so there is one answer.
  static List<String> withoutGateways(
    List<String> prefixes,
    List<String> gateways,
  ) {
    final excluded = _gatewayAddresses(gateways);
    if (excluded.isEmpty) return prefixes;
    final kept = <String>[];
    for (final prefix in prefixes) {
      final parsed = _parsePrefix(prefix);
      if (parsed == null) {
        kept.add(prefix);
        continue;
      }
      kept.addAll(_withoutHosts(parsed, excluded));
    }
    return kept;
  }

  /// The IPv4 addresses in a `geektrust_status` gateway list (`host:port`).
  static List<int> _gatewayAddresses(List<String> gateways) {
    final addresses = <int>[];
    for (final gateway in gateways) {
      if (gateway.startsWith('[')) continue;
      final colon = gateway.indexOf(':');
      final address = _ipv4(colon < 0 ? gateway : gateway.substring(0, colon));
      if (address != null) addresses.add(address);
    }
    return addresses;
  }

  /// [prefix] with every address in [excluded] removed, as the prefixes around
  /// them.
  static List<String> _withoutHosts(_RoutePrefix prefix, List<int> excluded) {
    final pending = <_RoutePrefix>[prefix];
    final kept = <_RoutePrefix>[];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (!excluded.any((address) => _contains(current, address))) {
        kept.add(current);
        continue;
      }
      // A /32 that is one of the excluded addresses has nothing left to route.
      if (current.length == 32) continue;
      final half = 1 << (31 - current.length);
      pending
        ..add(_RoutePrefix(current.base, current.length + 1))
        ..add(_RoutePrefix(current.base | half, current.length + 1));
    }
    kept.sort(
      (left, right) =>
          left.base != right.base ? left.base - right.base : left.length - right.length,
    );
    return [
      for (final entry in kept) '${_formatAddress(entry.base)}/${entry.length}',
    ];
  }

  static bool _contains(_RoutePrefix prefix, int address) =>
      (address & _maskFor(prefix.length)) == prefix.base;

  static int _maskFor(int length) =>
      length == 0 ? 0 : (0xFFFFFFFF << (32 - length)) & 0xFFFFFFFF;

  static _RoutePrefix? _parsePrefix(String text) {
    final slash = text.indexOf('/');
    if (slash < 0) return null;
    final base = _ipv4(text.substring(0, slash));
    final length = int.tryParse(text.substring(slash + 1));
    if (base == null || length == null || length < 0 || length > 32) return null;
    return _RoutePrefix(base & _maskFor(length), length);
  }

  static int? _ipv4(String text) {
    final parts = text.split('.');
    if (parts.length != 4) return null;
    var value = 0;
    for (final part in parts) {
      final octet = int.tryParse(part);
      if (octet == null || octet < 0 || octet > 255) return null;
      value = (value << 8) | octet;
    }
    return value & 0xFFFFFFFF;
  }

  static String _formatAddress(int address) =>
      '${(address >> 24) & 0xFF}.${(address >> 16) & 0xFF}.'
      '${(address >> 8) & 0xFF}.${address & 0xFF}';
}

/// One IPv4 prefix: a base address and a length in bits.
class _RoutePrefix {
  const _RoutePrefix(this.base, this.length);

  final int base;
  final int length;
}
