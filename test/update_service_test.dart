import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:techpie/services/update_service.dart';
import 'package:techpie/utils/product_version.dart';

void main() {
  testWidgets(
    'uses the App Store catalog for an App Store installation',
    (tester) async {
      PackageInfo.setMockInitialValues(
        appName: 'TechPie',
        packageName: 'club.geekpie.techpie',
        version: '1.0.1',
        buildNumber: '9',
        buildSignature: '',
        installerStore: 'com.apple',
      );
      final service = UpdateService(
        client: _FakeClient((request) async {
          expect(request.url.host, 'itunes.apple.com');
          expect(request.url.path, '/lookup');
          expect(request.url.queryParameters['id'], '6771316576');
          return _jsonResponse({
            'results': [
              {'trackId': 123, 'version': '9.9.9'},
              {'trackId': 6771316576, 'version': '1.1', 'releaseNotes': ' 修复同步 '},
            ],
          });
        }),
      );

      final release = await service.checkForUpdate(const ProductVersion(1, 0, 1, null, 9));

      expect(release?.version, const ProductVersion(1, 1, 0));
      expect(release?.name, '1.1');
      expect(release?.notes, '修复同步');
      expect(release?.source, UpdateSource.appStore);
      expect(await service.checkForUpdate(const ProductVersion(1, 1, 0, null, 1)), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'TestFlight keeps using the existing release channel',
    (tester) async {
      PackageInfo.setMockInitialValues(
        appName: 'TechPie',
        packageName: 'club.geekpie.techpie',
        version: '1.0.1',
        buildNumber: '9',
        buildSignature: '',
        installerStore: 'com.apple.testflight',
      );
      expect(await UpdateService().source, UpdateSource.github);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  test('an empty App Store result fails on that channel', () async {
    final service = UpdateService(
      client: _FakeClient((_) async => _jsonResponse({'results': <Object>[]})),
    );
    await expectLater(
      service.checkForUpdate(const ProductVersion(1, 0, 1), source: UpdateSource.appStore),
      throwsA(
        isA<UpdateCheckException>().having(
          (error) => error.message,
          'message',
          contains('App Store'),
        ),
      ),
    );
  });

  test('offers the published release when it is newer, without its checksums',
      () async {
    final requests = <http.BaseRequest>[];
    final service = UpdateService(
      client: _FakeClient((request) async {
        requests.add(request);
        return _jsonResponse({
          'tag_name': 'v1.0.2+7',
          'name': 'v1.0.2',
          'body': '## 变更\n\n'
              '- 修好了某件事\n'
              '\n'
              '\n## SHA-256\n\n'
              '```text\n'
              'abc123  TechPie-1.0.2-android-arm64v8.apk\n'
              '```\n',
        });
      }),
    );

    final release = await service.checkForUpdate(const ProductVersion(1, 0, 1, 2));

    expect(release, isNotNull);
    expect(release!.version, const ProductVersion(1, 0, 2, null, 7));
    expect(release.name, 'v1.0.2');
    // The checksum block the release pipeline writes into the same body is not
    // part of what a user is shown as the changelog.
    expect(release.notes, '## 变更\n\n- 修好了某件事');

    final request = requests.single;
    expect(
      request.url.toString(),
      'https://api.github.com/repos/HeZeBang/TechPie-flutter/releases/latest',
    );
    expect(request.headers['Accept'], contains('github+json'));
    expect(request.headers['User-Agent'], isNotEmpty);
  });

  test('says nothing is newer when the running build is the newest', () async {
    final service = UpdateService(
      client: _FakeClient(
        (_) async => _jsonResponse({'tag_name': 'v1.0.1+5', 'name': 'v1.0.1', 'body': 'notes'}),
      ),
    );

    expect(await service.checkForUpdate(const ProductVersion(1, 0, 1)), isNull);
    expect(await service.checkForUpdate(const ProductVersion(1, 0, 2)), isNull);

    // But a candidate of the published version is not the newest thing: the
    // stable release it led to is newer, so it is offered.
    final fromCandidate =
        await service.checkForUpdate(const ProductVersion(1, 0, 1, 2));
    expect(fromCandidate!.version, const ProductVersion(1, 0, 1, null, 5));
  });

  test('reads a legacy tag shape and a candidate', () async {
    final service = UpdateService(
      client: _FakeClient(
        (_) async => _jsonResponse({'tag_name': 'android-v1.0.2-rc.3+9', 'name': 'v1.0.2-rc.3', 'body': 'n'}),
      ),
    );

    final release = await service.checkForUpdate(const ProductVersion(1, 0, 1));
    expect(release!.version, const ProductVersion(1, 0, 2, 3, 9));
  });

  test('offers a higher build of the same stable version', () async {
    // The bug this was written for: v1.0.1+13 landed, but a build on 1.0.1+12 saw
    // only "1.0.1" and was told it was up to date.
    final service = UpdateService(
      client: _FakeClient(
        (_) async => _jsonResponse({'tag_name': 'v1.0.1+13', 'name': 'v1.0.1', 'body': 'n'}),
      ),
    );

    final release = await service.checkForUpdate(const ProductVersion(1, 0, 1, null, 12));

    expect(release, isNotNull);
    expect(release!.version, const ProductVersion(1, 0, 1, null, 13));
    // The title says only v1.0.1, so it must be the tag ("v1.0.1+13") that names
    // the offer — otherwise "发现新版本 v1.0.1" reads as no change at all.
    expect(release.name, 'v1.0.1+13');

    // And a build that is already the newer one is told nothing.
    expect(
      await service.checkForUpdate(const ProductVersion(1, 0, 1, null, 13)),
      isNull,
    );
  });

  test('refuses to prompt from a version it cannot read', () async {
    final service = UpdateService(
      client: _FakeClient((_) async => _jsonResponse({'tag_name': 'nightly', 'name': 'nightly'})),
    );

    expect(
      () => service.checkForUpdate(const ProductVersion(1, 0, 1)),
      throwsA(isA<UpdateCheckException>()),
    );
  });

  test('a request that hangs fails on a deadline instead of never', () async {
    // What api.github.com looks like from a network that drops packets: the
    // request neither succeeds nor fails, and without a deadline the check would
    // sit there. The response below arrives far too late to matter.
    final service = UpdateService(
      client: _FakeClient(
        (_) => Future<http.Response>.delayed(
          const Duration(seconds: 5),
          () => http.Response('{}', 200),
        ),
      ),
      timeout: const Duration(milliseconds: 50),
    );

    await expectLater(
      service.checkForUpdate(const ProductVersion(1, 0, 1)),
      throwsA(
        isA<UpdateCheckException>().having(
          (error) => error.message,
          'message',
          contains('超时'),
        ),
      ),
    );
  });

  test('reports a refusal as a failure, not as up to date', () async {
    // Unauthenticated GitHub requests are capped at 60 an hour per address.
    final rateLimited = UpdateService(
      client: _FakeClient(
        (_) async => http.Response('{"message":"API rate limit exceeded"}', 403),
      ),
    );
    expect(
      () => rateLimited.checkForUpdate(const ProductVersion(1, 0, 1)),
      throwsA(isA<UpdateCheckException>()),
    );

    final unreachable = UpdateService(
      client: _FakeClient((_) async => throw const SocketExceptionStub()),
    );
    expect(
      () => unreachable.checkForUpdate(const ProductVersion(1, 0, 1)),
      throwsA(isA<UpdateCheckException>()),
    );
  });
}

class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
  @override
  String toString() => 'SocketException: connection refused';
}

http.Response _jsonResponse(Map<String, dynamic> body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

class _FakeClient extends http.BaseClient {
  _FakeClient(this._handler);

  final Future<http.Response> Function(http.BaseRequest request) _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _handler(request);
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}
