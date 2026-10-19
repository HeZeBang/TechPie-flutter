import 'dart:convert';

import 'package:http/http.dart' as http_pkg;

import 'api_base_url.dart';
import 'http_client.dart';
import 'live_classroom_cache.dart';
import 'session/session_tree.dart';
import 'storage_service.dart';
import 'third_party_auth_service.dart';

enum LiveCamera {
  panorama('全景画面'),
  screen('屏幕画面'),
  closeup('教师画面');

  const LiveCamera(this.label);

  final String label;
}

class LiveException implements Exception {
  const LiveException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LiveClient {
  LiveClient(this.auth, this.storage, this.http);

  final ThirdPartyAuthService auth;
  final StorageService storage;
  final LoggingHttpClient http;
  final Map<int, _SignedUrlBatch> _signedUrls = {};

  String? get _owner {
    final account = auth.cpdailyNode.account;
    return account == null ? null : '${account.sid}:${account.account}';
  }

  Future<Uri> byClassroom(
    String classroom,
    LiveCamera camera, {
    required String semesterId,
    required String fingerprint,
  }) async {
    final owner = _owner;
    if (owner == null) throw const LiveException('请先绑定校园账号');
    final generation = storage.liveCacheGeneration;
    final baseUrl = apiBaseUrl(storage);
    try {
      final id = await LiveClassroomCache(storage).resolve(
        scope: jsonEncode([baseUrl, owner, semesterId, generation]),
        fingerprint: fingerprint,
        classroom: classroom,
        fetch: () async {
          final data = await _requestClassrooms({'semesterId': semesterId});
          final raw = data['classrooms'];
          if (raw is! Map<String, dynamic> ||
              raw.values
                  .any((v) => v != 'unknown' && !(v is int && v > 0 && v <= 9007199254740991))) {
            throw const LiveException('直播教室信息返回异常');
          }
          return raw.cast<String, Object>();
        },
      );
      if (id == null) throw const LiveException('暂未找到该课程对应的直播教室');
      return await byId(id, camera);
    } on StateError catch (error) {
      throw LiveException(error.message);
    }
  }

  Future<Uri> byId(int id, LiveCamera camera) async {
    final cached = _signedUrls[id];
    if (cached != null &&
        cached.owner == _owner &&
        cached.baseUrl == apiBaseUrl(storage) &&
        cached.generation == storage.liveCacheGeneration &&
        DateTime.now().isBefore(cached.expiresAt)) {
      return cached.urls[camera]!;
    }
    final data = await _requestUrl(id, camera);
    final uri = _playbackUri(data['url']);
    final batch = data['urls'];
    if (batch is Map<String, dynamic> &&
        LiveCamera.values.every((source) => batch.containsKey(source.name))) {
      final urls = {
        for (final source in LiveCamera.values)
          source: _playbackUri(batch[source.name]),
      };
      // Signed links have a limited lifetime. Never retain them for more than
      // 30 seconds, and respect a recognizable upstream expiry when provided.
      var expiresAt = DateTime.now().add(const Duration(seconds: 30));
      for (final signed in urls.values) {
        final expiry = _signedExpiry(signed);
        if (expiry != null && expiry.isBefore(expiresAt)) expiresAt = expiry;
      }
      _signedUrls[id] = _SignedUrlBatch(
        _owner,
        apiBaseUrl(storage),
        storage.liveCacheGeneration,
        expiresAt.subtract(const Duration(seconds: 3)),
        urls,
      );
    }
    return uri;
  }

  Uri _playbackUri(Object? raw) {
    final uri = raw is String ? Uri.tryParse(raw) : null;
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'live.shanghaitech.edu.cn' ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw const LiveException('直播播放链接返回异常');
    }
    return uri;
  }

  DateTime? _signedExpiry(Uri uri) {
    final raw = uri.queryParameters['expires'] ??
        uri.queryParameters['expire'] ??
        uri.queryParameters['exp'] ??
        uri.queryParameters['auth_key']?.split('-').first;
    final seconds = int.tryParse(raw ?? '');
    if (seconds == null || seconds < 1000000000) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      seconds > 100000000000 ? seconds : seconds * 1000,
    );
  }

  // Stream signing no longer consumes ELRC credentials. In particular, do not
  // mint a derived cookie just to switch cameras in an existing live session.
  Future<Map<String, dynamic>> _requestUrl(int id, LiveCamera camera) async {
    final baseUrl = apiBaseUrl(storage);
    if (_owner == null) throw const LiveException('请先绑定校园账号');
    final response = await http
        .post(
          Uri.parse('$baseUrl/live/url'),
          headers: {'Content-Type': 'application/json; charset=UTF-8'},
          body: jsonEncode({'id': id, 'camera': camera.name}),
          tag: 'liveRequest',
        )
        .timeout(const Duration(seconds: 30));
    return _readResponse(response);
  }

  Future<Map<String, dynamic>> _requestClassrooms(Map<String, Object> input) async {
    final baseUrl = apiBaseUrl(storage);
    if (_owner == null) throw const LiveException('请先绑定校园账号');

    final response = await auth.sessionTree.withCookie<http_pkg.Response>(
      auth.elrcNode,
      (provider) async {
        final result = await http
            .post(
              Uri.parse('$baseUrl/live/classrooms'),
              headers: {'Content-Type': 'application/json; charset=UTF-8'},
              body: jsonEncode({
                ...input,
                'cookie': provider.cookies,
                'tgc': auth.cpdailyNode.rawFields['tgc'],
              }),
              tag: 'liveRequest',
            )
            .timeout(const Duration(seconds: 65));
        return CookieAction(result, expired: result.statusCode == 401);
      },
    );
    if (response == null) throw const LiveException('直播服务暂不可用，请重试');
    if (response.statusCode == 401) {
      throw const LiveException('ELRC 登录续期失败，请重试');
    }
    return _readResponse(response);
  }

  Map<String, dynamic> _readResponse(http_pkg.Response response) {
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) throw const LiveException('直播服务返回异常');
    if (response.statusCode != 200 || body['success'] != true) {
      throw LiveException(body['error'] is String ? body['error'] as String : '直播服务暂不可用');
    }
    final data = body['data'];
    if (data is! Map<String, dynamic>) throw const LiveException('直播服务返回异常');
    return data;
  }
}

class _SignedUrlBatch {
  const _SignedUrlBatch(this.owner, this.baseUrl, this.generation, this.expiresAt, this.urls);

  final String? owner;
  final String baseUrl;
  final int generation;
  final DateTime expiresAt;
  final Map<LiveCamera, Uri> urls;
}
