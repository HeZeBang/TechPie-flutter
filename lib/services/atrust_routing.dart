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
}
