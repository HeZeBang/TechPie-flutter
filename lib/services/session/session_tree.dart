import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/third_party_account.dart';
import '../http_client.dart';
import 'cookie_provider.dart';
import 'session_node.dart';
import 'session_nodes.dart';
///
/// Topology is built once at construction; the facade
/// ([ThirdPartyAuthService]) feeds account mutations in via [setAccount].
class SessionTree extends ChangeNotifier {
  SessionTree({
    required this.persist,
    required this.http,
    required this.baseUrl,
  }) {
    egate = CpdailySessionNode(
      persist: persist,
      http: http,
      baseUrl: baseUrl,
    );
    ids = IdsSessionNode(cpdaily: egate);
    egate.attachChild(ids);
    gradescope = LeafSessionNode(
      platform: ThirdPartyPlatform.gradescope,
      persist: persist,
      http: http,
      baseUrl: baseUrl,
    );
    hydro = LeafSessionNode(
      platform: ThirdPartyPlatform.hydro,
      persist: persist,
      http: http,
      baseUrl: baseUrl,
    );

    // Propagate child notifications up so listeners on the tree (facade →
    // UI / sync) fire on any node change.
    for (final n in [egate, ids, gradescope, hydro]) {
      n.addListener(notifyListeners);
    }
  }

  final PersistAccount persist;
  final LoggingHttpClient http;
  final BaseUrlGetter baseUrl;


  late final CpdailySessionNode egate;
  late final IdsSessionNode ids;
  late final LeafSessionNode gradescope;
  late final LeafSessionNode hydro;

  /// All top-level nodes in a stable order.
  List<SessionNode> get roots => [egate, gradescope, hydro];

  /// Lookup a leaf/ root node by [ThirdPartyPlatform].
  SessionNode nodeFor(ThirdPartyPlatform p) => switch (p) {
        ThirdPartyPlatform.egate => egate,
        ThirdPartyPlatform.gradescope => gradescope,
        ThirdPartyPlatform.hydro => hydro,
      };

  /// Feed an account mutation from the facade into the matching node. Used by
  /// bind/unbind/replaceAll/updateRaw.
  void setAccount(ThirdPartyPlatform p, ThirdPartyAccount? acc) {
    switch (p) {
      case ThirdPartyPlatform.egate:
        egate.setAccount(acc);
        break;
      case ThirdPartyPlatform.gradescope:
        gradescope.setAccount(acc);
        break;
      case ThirdPartyPlatform.hydro:
        hydro.setAccount(acc);
        break;
    }
  }

  // -- The anti-storm 401-renew-retry helper --

  /// Run [action] with the cookie view from [node]. On a response the caller
  /// flags as expired (via [isExpired]), renew the node exactly once (shared
  /// across all concurrent callers) and retry with the fresh cookie. If a
  /// concurrent renew already advanced the cookie epoch since [action]
  /// captured it, skip the renew entirely and just retry with the new cookie.
  ///
  /// [action] receives the current [CookieProvider] (non-null — callers
  /// gate on [node.isAvailable] first) and returns its result + whether the
  /// result should be treated as "cookie expired, please renew+retry".
  ///
  /// Returns the (possibly retried) result, or null if the node was
  /// unavailable or renew failed.
  Future<T?> withCookie<T>(
    SessionNode node,
    Future<CookieAction<T>> Function(CookieProvider provider) action,
  ) async {
    if (!node.isAvailable) return null;
    var cp = node.cookieProvider;
    if (cp == null) return null;

    var result = await action(cp);
    if (!result.expired) return result.value;

    // 401: renew if the cookie hasn't already been refreshed since we read it.
    final beforeEpoch = node.epoch;
    final ok = await node.renewIfNeeded(beforeEpoch);
    if (!ok) return result.value;

    cp = node.cookieProvider;
    if (cp == null) return result.value;
    final retried = await action(cp);
    return retried.value;
  }

  @override
  void dispose() {
    for (final n in [egate, ids, gradescope, hydro]) {
      n.removeListener(notifyListeners);
      n.dispose();
    }
    super.dispose();
  }
}

/// The result of a cookie-bearing action, tagged by the caller so
/// [SessionTree.withCookie] knows whether to trigger a renew+retry.
class CookieAction<T> {
  final T value;
  final bool expired;
  const CookieAction(this.value, {required this.expired});
}
