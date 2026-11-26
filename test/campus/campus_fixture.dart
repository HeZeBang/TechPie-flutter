import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/models/third_party_account.dart';
import 'package:techpie/services/campus/campus_errors.dart';
import 'package:techpie/services/campus/campus_session.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/session/session_tree.dart';

typedef Reply = FutureOr<ResponseBody> Function(RequestOptions request);

class CampusFixture implements HttpClientAdapter {
  CampusFixture(String origin, this.reply) {
    final uri = Uri.parse(origin);
    final tree = SessionTree(
      persist: (_, {force = false}) async {},
      http: LoggingHttpClient(DebugLogger()),
      baseUrl: () => 'https://backend.invalid',
      localCookieMint: (node, root) async => 'SESSION=v${++renewals}',
    );
    tree.ids.setAccount(
      ThirdPartyAccount(
        platform: ThirdPartyPlatform.ids,
        account: 'bound',
        token: '',
        raw: const {'authMethod': 'passkey', 'tgc': 'ids-only'},
        boundAt: DateTime.utc(2026),
      ),
    );
    final node = switch (uri.host) {
      'egate.shanghaitech.edu.cn' => tree.egateApp,
      'eams.shanghaitech.edu.cn' => tree.eams,
      'elearning.shanghaitech.edu.cn' => tree.elearning,
      _ => throw ArgumentError.value(origin),
    };
    node.setDerivedCookie('SESSION=v0; CASTGC=ids-only');
    session = CampusSession(
      uri,
      Dio()..httpClientAdapter = this,
      <T>(action) => tree.withCookie<T>(node, action),
      () => identity,
    );
    addTearDown(tree.dispose);
  }
  final Reply reply;
  late final CampusSession session;
  CampusIdentity identity = (user: 'user', ids: 'bound');
  final requests = <RequestOptions>[];
  int renewals = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return reply(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody respond(
  Object body, {
  int status = 200,
  Map<String, List<String>> headers = const {},
}) =>
    ResponseBody.fromBytes(
      body is List<int> ? body : utf8.encode(body is String ? body : jsonEncode(body)),
      status,
      headers: headers,
    );

Matcher fails(CampusErrorKind kind) =>
    throwsA(isA<CampusRequestException>().having((e) => e.kind, 'kind', kind));
