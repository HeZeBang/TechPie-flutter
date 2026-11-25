import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../utils/platform.dart';
import '../utils/product_version.dart';

const _appStoreId = 6771316576;

enum UpdateSource {
  github('GitHub', UpdateService.latestReleasePage),
  appStore('App Store', 'itms-apps://apps.apple.com/app/id$_appStoreId');

  const UpdateSource(this.label, this.releasePage);

  final String label;
  final String releasePage;
}

/// Thrown when the check cannot produce an answer. The message is user-facing,
/// so it says what happened in the user's terms rather than in HTTP's.
class UpdateCheckException implements Exception {
  UpdateCheckException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A published release that is newer than the running build.
class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.name,
    required this.notes,
    this.source = UpdateSource.github,
  });

  /// The version the release carries, comparable with the running one.
  final ProductVersion version;

  /// What the release calls itself — `v1.0.1`, `v1.0.1-rc.2`.
  final String name;

  /// The release notes shown in the update prompt.
  final String notes;

  final UpdateSource source;

  @override
  String toString() => 'ReleaseInfo($name)';
}

/// Checks the distribution channel directly for a newer release.
class UpdateService {
  UpdateService({
    http.Client? client,
    // A route that drops packets instead of refusing them — which is what
    // api.github.com looks like from some networks — leaves the request hanging
    // rather than failing, so the check carries its own deadline. Injectable so
    // a test does not have to wait one out.
    this.timeout = const Duration(seconds: 12),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  static const repository = 'HeZeBang/TechPie-flutter';

  /// GitHub's redirect to the latest stable release.
  static const latestReleasePage =
      'https://github.com/$repository/releases/latest';

  static Uri get _latestReleaseUri =>
      Uri.https('api.github.com', '/repos/$repository/releases/latest');

  static final _appStoreLookupUri = Uri.https('itunes.apple.com', '/lookup', {
    'id': '$_appStoreId',
  });

  Future<UpdateSource> get source async {
    if (!isIos()) return UpdateSource.github;
    // The package-info plugin reports distinct installers for TestFlight and
    // the simulator. The native macOS build is distributed separately.
    final info = await PackageInfo.fromPlatform();
    return info.installerStore == 'com.apple'
        ? UpdateSource.appStore
        : UpdateSource.github;
  }

  /// The version this build is, for a caller that has no other reason to hold it
  /// — the silent check has none. Null when the platform cannot say or the answer
  /// is not a version: a check against an unknown version would answer about
  /// nothing.
  static Future<ProductVersion?> currentProductVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final raw = info.buildNumber.isEmpty
          ? info.version
          : '${info.version}+${info.buildNumber}';
      return ProductVersion.tryParse(raw);
    } catch (_) {
      return null;
    }
  }

  /// The newest published release when it is newer than [current], or null when
  /// the running build is already the newest — which is not a failure, and must
  /// not read like one.
  Future<ReleaseInfo?> checkForUpdate(
    ProductVersion current, {
    UpdateSource? source,
  }) async {
    final channel = source ?? await this.source;
    final uri = switch (channel) {
      UpdateSource.appStore => _appStoreLookupUri,
      UpdateSource.github => _latestReleaseUri,
    };
    final http.Response response;
    try {
      response = await _client
          .get(
            uri,
            headers: channel == UpdateSource.github
                ? {
                    'Accept': 'application/vnd.github+json',
                    'X-GitHub-Api-Version': '2022-11-28',
                    'User-Agent': 'TechPie/$current',
                  }
                : null,
          )
          .timeout(timeout);
    } on TimeoutException {
      throw UpdateCheckException('连接 ${channel.label} 超时，请检查网络后重试。');
    } catch (error) {
      throw UpdateCheckException('无法连接 ${channel.label}：$error');
    }

    if (channel == UpdateSource.appStore) {
      return _appStoreRelease(response, current);
    }

    switch (response.statusCode) {
      case 200:
        break;
      case 404:
        // No published release yet: nothing to update to, and nothing broken.
        throw UpdateCheckException('GitHub 上还没有已发布的版本。');
      case 403:
        // Unauthenticated requests are capped at 60 an hour per address.
        throw UpdateCheckException('GitHub 暂时拒绝了请求（可能是请求过于频繁），请稍后再试。');
      default:
        throw UpdateCheckException('GitHub 返回了 HTTP ${response.statusCode}。');
    }

    final Map<String, dynamic> payload;
    try {
      payload = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw UpdateCheckException('GitHub 的响应无法解析。');
    }

    final tag = (payload['tag_name'] as String? ?? '').trim();
    final title = (payload['name'] as String? ?? '').trim();
    final published =
        ProductVersion.tryParse(tag) ?? ProductVersion.tryParse(title);
    if (published == null) {
      // Better to say we cannot tell than to prompt for an update we do not
      // understand: a wrong prompt is worse than none.
      throw UpdateCheckException('无法识别 GitHub 上的版本号（$tag）。');
    }
    if (!published.isNewerThan(current)) {
      return null;
    }

    // Two builds of one version differ only by `+B`, and the build number is not
    // part of the title (`v1.0.1`). Offering this update by title would read as
    // "still 1.0.1" to everyone the build is the whole difference — so the tag,
    // which carries `+B`, is what names it then.
    final sameVersion = published.toString() == current.toString();
    return ReleaseInfo(
      version: published,
      name: title.isNotEmpty && !sameVersion ? title : tag,
      notes: _changelog(payload['body'] as String? ?? ''),
    );
  }

  static ReleaseInfo? _appStoreRelease(
    http.Response response,
    ProductVersion current,
  ) {
    if (response.statusCode != 200) {
      throw UpdateCheckException('App Store 返回了 HTTP ${response.statusCode}。');
    }

    final List<dynamic> results;
    try {
      final payload =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      results = payload['results'] as List<dynamic>;
    } catch (_) {
      throw UpdateCheckException('App Store 的响应无法解析。');
    }

    for (final item in results) {
      if (item is! Map<String, dynamic> || item['trackId'] != _appStoreId) {
        continue;
      }
      final raw = switch (item['version']) {
        final String version => version.trim(),
        _ => '',
      };
      final parts = raw.split('.');
      final published = _appStoreVersion.hasMatch(raw)
          ? ProductVersion.tryParse(
              [...parts, ...List.filled(3 - parts.length, '0')].join('.'),
            )
          : null;
      if (published == null) {
        throw UpdateCheckException('无法识别 App Store 上的版本号（$raw）。');
      }
      if (!published.isNewerThan(current)) return null;
      final notes = item['releaseNotes'];
      final changelog = notes is String ? notes.trim() : '';
      return ReleaseInfo(
        version: published,
        name: raw,
        notes: changelog.isEmpty ? _noReleaseNotes : changelog,
        source: UpdateSource.appStore,
      );
    }
    throw UpdateCheckException('App Store 上暂时无法获取 TechPie 的版本信息。');
  }

  static final _appStoreVersion = RegExp(r'^\d+(?:\.\d+){0,2}$');
  static const _noReleaseNotes = '（这个版本没有写更新说明。）';
  static final RegExp _checksumBlock = RegExp(r'\n#+ *SHA-256\b');

  /// `release.yml` writes the changelog and the checksums into one body. A
  /// checksum list is not a changelog, so the block is dropped before the text
  /// reaches a dialog.
  static String _changelog(String body) {
    final match = _checksumBlock.firstMatch(body);
    final changelog = (match == null ? body : body.substring(0, match.start)).trim();
    return changelog.isEmpty ? _noReleaseNotes : changelog;
  }
}
