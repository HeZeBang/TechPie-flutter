import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/auth_service.dart';
import '../services/elrc_client.dart';
import '../services/service_provider.dart';
import '../services/third_party_auth_service.dart';
import '../theme/theme.dart';
import '../widgets/adaptive_button.dart';
import '../widgets/adaptive_navigation_scaffold.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/design_system/design_system.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';
import 'campus_session_handle.dart';
import 'elrc_player_page.dart';

class ElrcRecordingsPage extends StatefulWidget {
  const ElrcRecordingsPage({super.key});

  @override
  State<ElrcRecordingsPage> createState() => _ElrcRecordingsPageState();
}

class _ElrcRecordingsPageState extends State<ElrcRecordingsPage> {
  static final _reviewUri = Uri.parse(
    'https://elrc.shanghaitech.edu.cn/learn/videoreview?type=1',
  );
  static final _loginUri = Uri.https(
    'elrc.shanghaitech.edu.cn',
    '/unifiedlogin/v1/loginmanage/login/direction',
    {'redirect_url': _reviewUri.toString()},
  );

  final _searchCtrl = TextEditingController();
  WebViewController? _controller;
  ElrcClient? _client;
  List<ElrcCourse>? _courses;
  ElrcCourse? _selectedCourse;
  List<ElrcLesson>? _lessons;
  String _searchQuery = '';
  String? _error;
  Uri? _activeUri;
  int _request = 0;
  bool _starting = true;
  bool _busy = false;
  bool _webVisible = false;
  bool _reviewFinished = false;
  bool _sessionReloadRequired = false;
  bool _loginPresented = false;
  var _expectedMainFrameCancellations = 0;
  ThirdPartyAuthService? _tpAuth;
  AuthService? _auth;
  String? _primaryUserId;
  String? _bindingOwner;
  bool _campusAttempted = false;

  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_tpAuth != null) return;
    final services = ServiceProvider.of(context);
    _tpAuth = services.thirdPartyAuthService;
    _auth = services.authService;
    _primaryUserId = _auth!.session?.userId;
    _auth!.addListener(_primaryAccountChanged);
    if (!_auth!.isLoggedIn) {
      _starting = false;
      _error = '请先登录 TechPie';
      return;
    }
    _bindingOwner = _tpAuth!.campusWebSession.owner;
    _tpAuth!.addListener(_bindingChanged);
    if (_supported) unawaited(_prepare());
  }

  bool get _authorized =>
      _auth!.isLoggedIn && _auth!.session?.userId == _primaryUserId;

  void _primaryAccountChanged() {
    if (_authorized || !mounted) return;
    _request++;
    _client?.dispose();
    _client = null;
    _controller = null;
    setState(() {
      _courses = null;
      _lessons = null;
      _selectedCourse = null;
      _starting = false;
      _webVisible = false;
      _error = '请先登录 TechPie';
    });
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _bindingChanged() {
    final generation = _tpAuth!.campusWebSession.owner;
    if (generation == _bindingOwner || !mounted) return;
    _bindingOwner = generation;
    _request++;
    _campusAttempted = false;
    _loginPresented = false;
    _client?.dispose();
    _client = null;
    _controller = null;
    setState(() {
      _courses = null;
      _lessons = null;
      _selectedCourse = null;
      _busy = false;
      _starting = true;
      _webVisible = false;
    });
    if (_supported) unawaited(_prepare());
  }

  Future<void> _writeCampusSession(WebViewController controller) async {
    try {
      final session = CampusSessionHandle(_tpAuth!, _tpAuth!.idsNode);
      await session.prepare();
      await _tpAuth!.campusWebSession.clearLocalStorageIfDue(controller);
      final cookieManager = WebViewCookieManager();
      for (final cookie in session.cookies) {
        await cookieManager.setCookie(cookie);
      }
    } catch (error) {
      _trace('campus session pre-flight failed: $error');
    }
  }

  Future<void> _prepare() async {
    final generation = _bindingOwner;
    final controller = WebViewController();
    final client = ElrcClient(controller);
    try {
      await _writeCampusSession(controller);
      _campusAttempted = true;
      if (!mounted || !_authorized || generation != _bindingOwner) {
        client.dispose();
        return;
      }
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await client.initialize();
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (!_authorized || !identical(_controller, controller)) {
              return NavigationDecision.prevent;
            }
            final uri = Uri.tryParse(request.url);
            _trace('navigation request ${_safeUri(uri)}');
            if (request.url == 'about:blank') {
              return NavigationDecision.navigate;
            }
            if (_isHttpElrc(uri)) {
              final target = uri!.replace(scheme: 'https', port: 443);
              _expectedMainFrameCancellations++;
              _trace('upgrade navigation to ${_safeUri(target)}');
              unawaited(controller.loadRequest(target));
              return NavigationDecision.prevent;
            }
            if (_isLogin(uri) && !_campusAttempted && _tpAuth!.hasIdsBinding) {
              _expectedMainFrameCancellations++;
              unawaited(_openLogin());
              return NavigationDecision.prevent;
            }
            if (_isHttpsElrc(uri) || _isLogin(uri)) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
          onPageStarted: (url) {
            if (!identical(_controller, controller)) return;
            _trace('page started ${_safeUri(Uri.tryParse(url))}');
            _activate(url, pageStarted: true);
          },
          onUrlChange: (change) {
            if (!identical(_controller, controller)) return;
            _trace('URL changed ${_safeUri(Uri.tryParse(change.url ?? ''))}');
            _activate(change.url);
          },
          onPageFinished: (url) {
            if (!identical(_controller, controller)) return;
            _trace('page finished ${_safeUri(Uri.tryParse(url))}');
            _navigationFinished(url);
          },
          onWebResourceError: (error) {
            if (identical(_controller, controller)) _webResourceFailed(error);
          },
        ),
      );
      if (!mounted || !_authorized || generation != _bindingOwner) {
        client.dispose();
        return;
      }
      _controller = controller;
      _client = client;
      setState(() {});
      await controller.loadRequest(_reviewUri);
    } catch (_) {
      client.dispose();
      if (!mounted || generation != _bindingOwner) return;
      if (identical(_client, client)) {
        _client = null;
        _controller = null;
      }
      setState(() {
        _starting = false;
        _busy = false;
        _webVisible = false;
        _sessionReloadRequired = true;
        _error = 'ELRC 页面加载失败';
      });
    }
  }

  bool _isHttpElrc(Uri? uri) =>
      uri?.scheme == 'http' &&
      uri?.host == 'elrc.shanghaitech.edu.cn' &&
      uri?.port == 80 &&
      uri?.userInfo.isEmpty == true;

  bool _isHttpsElrc(Uri? uri) =>
      uri?.scheme == 'https' &&
      uri?.host == 'elrc.shanghaitech.edu.cn' &&
      uri?.port == 443 &&
      uri?.userInfo.isEmpty == true;

  bool _isReview(Uri? uri) =>
      _isHttpsElrc(uri) &&
      (uri?.path == '/learn/videoreview' || uri?.path == '/learn/videoreview/');

  bool _isAppSide(Uri? uri) =>
      _isHttpsElrc(uri) &&
      (uri?.path == '/appside' || uri?.path == '/appside/');

  bool _isSessionPage(Uri? uri) => _isReview(uri) || _isAppSide(uri);

  bool _isLogin(Uri? uri) =>
      uri?.scheme == 'https' &&
      uri?.host == 'ids.shanghaitech.edu.cn' &&
      uri?.port == 443 &&
      uri?.userInfo.isEmpty == true;

  void _trace(String message) {
    if (kDebugMode) debugPrint('[ELRC] $message');
  }

  String _safeUri(Uri? uri) {
    if (uri == null) return '<invalid URL>';
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port${uri.path}';
  }

  void _activate(String? url, {bool pageStarted = false}) {
    final uri = Uri.tryParse(url ?? '');
    if (uri == null) return;
    final wasSessionPage = _isSessionPage(_activeUri);
    _activeUri = uri;
    if (_isSessionPage(uri) && (pageStarted || !wasSessionPage)) {
      _reviewFinished = false;
    }
    if (!mounted) return;

    final login = _isLogin(uri);
    setState(() {
      _webVisible = login;
      if (login) {
        _loginPresented = true;
        _starting = false;
        _busy = false;
      } else if (_isHttpsElrc(uri)) {
        _starting = _courses == null;
        if (_isSessionPage(uri)) {
          _error = null;
          _sessionReloadRequired = false;
        }
      }
    });
  }

  void _navigationFinished(String url) {
    final uri = Uri.tryParse(url);
    if (_isSessionPage(uri) && _isSessionPage(_activeUri)) {
      if (_reviewFinished) return;
      _reviewFinished = true;
      if (mounted) {
        setState(() => _webVisible = false);
        unawaited(_loadCourses());
      }
      return;
    }
    if (_isLogin(uri) && _isLogin(_activeUri) && mounted) {
      setState(() {
        _starting = false;
        _webVisible = true;
      });
    }
  }

  void _webResourceFailed(WebResourceError error) {
    _trace(
      'resource error main=${error.isForMainFrame} '
      'code=${error.errorCode} type=${error.errorType?.name} '
      '${_safeUri(Uri.tryParse(error.url ?? ''))}',
    );
    if (error.isForMainFrame != true) return;
    if (error.errorCode == 102 && _expectedMainFrameCancellations > 0) {
      _expectedMainFrameCancellations--;
      _trace('ignored expected replacement-navigation cancellation');
      return;
    }
    _pageLoadFailed();
  }

  void _pageLoadFailed() {
    if (!mounted) return;
    setState(() {
      _starting = false;
      _busy = false;
      _sessionReloadRequired = true;
      _error = 'ELRC 页面加载失败';
      if (!_isLogin(_activeUri)) _webVisible = false;
    });
  }

  Future<void> _reloadReview() async {
    final controller = _controller;
    if (controller == null) {
      await _prepare();
      return;
    }
    final request = ++_request;
    _reviewFinished = false;
    setState(() {
      _courses = null;
      _selectedCourse = null;
      _lessons = null;
      _error = null;
      _starting = true;
      _busy = false;
      _webVisible = false;
      _sessionReloadRequired = false;
    });
    try {
      await controller.loadRequest(_reviewUri);
    } catch (_) {
      if (!mounted || !_authorized || request != _request) return;
      setState(() {
        _starting = false;
        _sessionReloadRequired = true;
        _error = 'ELRC 页面加载失败';
      });
    }
  }

  Future<void> _openLogin() async {
    final controller = _controller;
    if (controller == null) {
      await _prepare();
      return;
    }
    _reviewFinished = false;
    setState(() {
      _loginPresented = true;
      _error = null;
      _starting = true;
      _busy = false;
      _webVisible = false;
      _sessionReloadRequired = true;
    });
    _trace('opening fixed ELRC login entry');
    final request = ++_request;
    try {
      if (!_campusAttempted) {
        _campusAttempted = true;
        await _writeCampusSession(controller);
        _trace('IDS cookie written; awaiting official SSO');
      }
      if (!mounted || request != _request) return;
      await controller.loadRequest(_loginUri);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = 'ELRC 登录页面加载失败';
      });
    }
  }

  Future<void> _loadCourses() async {
    final client = _client;
    if (client == null || _busy || !_isSessionPage(_activeUri)) return;
    final request = ++_request;
    _trace('course request started from ${_safeUri(_activeUri)}');
    setState(() {
      _busy = true;
      _starting = false;
      _error = null;
      _sessionReloadRequired = false;
    });
    try {
      final courses = await client.courses();
      if (!mounted || request != _request) return;
      _trace('course request completed with ${courses.length} courses');
      if (courses.isEmpty && !_loginPresented) {
        _trace('empty initial course list; opening login');
        await _openLogin();
        return;
      }
      setState(() {
        _courses = courses;
        _selectedCourse = null;
        _lessons = null;
      });
    } on ElrcException catch (error) {
      if (!mounted || request != _request) return;
      _trace('course request failed: ${error.message}');
      if (error.needsLogin) {
        await _openLogin();
        return;
      }
      setState(() {
        _error = error.message;
        _sessionReloadRequired = error.needsLogin;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() => _error = '课程列表加载失败');
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  Future<void> _loadLessons(ElrcCourse course) async {
    final client = _client;
    if (client == null || _busy || !_isSessionPage(_activeUri)) return;
    final request = ++_request;
    setState(() {
      _selectedCourse = course;
      _lessons = null;
      _error = null;
      _busy = true;
      _sessionReloadRequired = false;
    });
    try {
      final lessons = await client.lessons(course);
      if (!mounted || request != _request) return;
      setState(() => _lessons = lessons);
    } on ElrcException catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = error.message;
        _sessionReloadRequired = error.needsLogin;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() => _error = '录播课次加载失败');
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  Future<void> _openLesson(ElrcLesson lesson) async {
    final course = _selectedCourse;
    final client = _client;
    if (course == null || client == null || _busy) return;
    final request = ++_request;
    setState(() {
      _busy = true;
      _error = null;
      _sessionReloadRequired = false;
    });
    try {
      final sources = await client.sources(course, lesson);
      if (!mounted || request != _request) return;
      setState(() => _busy = false);
      // Playback is immersive, so it covers the tab bar.
      await pushAdaptivePage<void>(
        context,
        rootNavigator: true,
        builder: (_) => ElrcPlayerPage(
          courseName: course.name,
          lessonTitle: lesson.title,
          referer: course.referer,
          sources: sources,
        ),
      );
    } on ElrcException catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = error.message;
        _sessionReloadRequired = error.needsLogin;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() => _error = '播放地址加载失败');
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  void _showCourses() {
    if (_busy) return;
    setState(() {
      _selectedCourse = null;
      _lessons = null;
      _error = null;
      _sessionReloadRequired = false;
    });
  }

  void _retryCourses() {
    unawaited(
      _sessionReloadRequired
          ? _openLogin()
          : _courses == null
              ? _reloadReview()
              : _loadCourses(),
    );
  }

  void _retryLessons(ElrcCourse course) {
    unawaited(
      _sessionReloadRequired ? _openLogin() : _loadLessons(course),
    );
  }

  String _courseSubtitle(ElrcCourse course) {
    final parts = <String>[
      if (course.courseNo != null && course.courseNo!.isNotEmpty)
        course.courseNo!,
      if (course.schoolYear != null && course.schoolYear!.isNotEmpty)
        course.semester != null && course.semester!.isNotEmpty
            ? '${course.schoolYear} · ${course.semester}'
            : course.schoolYear!,
      if (course.description.isNotEmpty) course.description,
    ];
    return parts.join(' · ');
  }

  Widget _stateCard(
    TpColors colors, {
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? action,
    bool loading = false,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TpTokens.pageHorizontalPadding,
        ),
        child: TpPageBody(
          child: TpCard(
            padding: const EdgeInsets.symmetric(
              horizontal: TpTokens.space5,
              vertical: TpTokens.space6,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading)
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                else
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: colors.brandSoft,
                      borderRadius: BorderRadius.circular(TpTokens.radiusM),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      icon,
                      size: TpTokens.iconL + 4,
                      color: colors.brand,
                    ),
                  ),
                const SizedBox(height: TpTokens.space4),
                Text(
                  title,
                  style: TpTypography.cardTitle(colors).copyWith(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: TpTokens.space2),
                  Text(
                    subtitle,
                    style: TpTypography.itemMeta(colors),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (action != null) ...[
                  const SizedBox(height: TpTokens.space4),
                  action,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorCard(TpColors colors, VoidCallback retry) => TpCard(
        color: colors.dangerRed.withValues(alpha: colors.isDark ? 0.16 : 0.08),
        borderColor: colors.dangerRed.withValues(alpha: 0.25),
        borderRadius: TpTokens.radiusS,
        padding: const EdgeInsets.fromLTRB(
          TpTokens.space4,
          TpTokens.space3,
          TpTokens.space2,
          TpTokens.space3,
        ),
        child: Row(
          children: [
            Icon(TpIcons.info, size: TpTokens.iconS, color: colors.dangerRed),
            const SizedBox(width: TpTokens.space2),
            Expanded(
              child: Text(
                _error!,
                style: TpTypography.itemMeta(colors).copyWith(
                  color: colors.dangerRed,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            TextButton(
              onPressed: _busy ? null : retry,
              child: const Text('重试'),
            ),
          ],
        ),
      );

  Widget _content(TpColors colors) {
    if (!_supported) {
      return _stateCard(
        colors,
        icon: TpIcons.smartphone,
        title: '请在 iPhone 或 Android 手机中观看录播',
        subtitle: '课程录播依赖移动端嵌入式鉴权与视频播放组件。',
      );
    }
    if (_error != null && _courses == null && !_webVisible) {
      return _stateCard(
        colors,
        icon: TpIcons.info,
        title: _error!,
        action: AdaptiveButton(
          onPressed: _busy ? null : _retryCourses,
          icon: TpIcons.refresh,
          sfSymbol: 'arrow.clockwise',
          label: '重新加载',
          role: AdaptiveButtonRole.prominent,
          height: 44,
          width: 200,
        ),
      );
    }
    if ((_starting || _busy) && _courses == null) {
      return _stateCard(
        colors,
        icon: TpIcons.recordings,
        title: '正在连接课程录播…',
        subtitle: '正在自动同步校园认证会话',
        loading: true,
      );
    }

    final selectedCourse = _selectedCourse;
    if (selectedCourse != null) {
      final lessons = _lessons;
      if (_busy && lessons == null) {
        return _stateCard(
          colors,
          icon: TpIcons.recordings,
          title: '正在加载录播课次…',
          subtitle: selectedCourse.name,
          loading: true,
        );
      }
      if (lessons == null) {
        return _stateCard(
          colors,
          icon: TpIcons.info,
          title: _error ?? '录播课次加载失败',
          action: AdaptiveButton(
            onPressed: _busy ? null : () => _retryLessons(selectedCourse),
            icon: TpIcons.refresh,
            sfSymbol: 'arrow.clockwise',
            label: '重新加载',
            role: AdaptiveButtonRole.prominent,
            height: 44,
            width: 200,
          ),
        );
      }

      final meta = _courseSubtitle(selectedCourse);
      return ListView(
        padding: EdgeInsets.fromLTRB(
          TpTokens.pageHorizontalPadding,
          TpTokens.space3,
          TpTokens.pageHorizontalPadding,
          AppShellMetrics.bottomContentPaddingOf(context),
        ),
        children: [
          TpPageBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TpCard(
                  padding: const EdgeInsets.all(TpTokens.space4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              selectedCourse.name,
                              style: TpTypography.cardTitle(colors)
                                  .copyWith(fontSize: 17),
                            ),
                          ),
                          const SizedBox(width: TpTokens.space2),
                          TpBadge(
                            label: '${lessons.length} 节录播',
                            tone: TpBadgeTone.brand,
                          ),
                        ],
                      ),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: TpTokens.space2),
                        Text(meta, style: TpTypography.itemMeta(colors)),
                      ],
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: TpTokens.sectionGap),
                  _errorCard(colors, () => _retryLessons(selectedCourse)),
                ],
                const SizedBox(height: TpTokens.sectionGap),
                if (lessons.isEmpty)
                  TpCard(
                    padding: const EdgeInsets.all(TpTokens.space5),
                    child: Center(
                      child: Text(
                        '该课程暂无可观看录播',
                        style: TpTypography.itemMeta(colors),
                      ),
                    ),
                  )
                else
                  TpCard(
                    leadingIcon: TpIcons.recordings,
                    title: '录播课次',
                    trailing: Text('共 ${lessons.length} 节'),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < lessons.length; i++)
                          TpAccentRow(
                            accentColor: colors.brand,
                            title: lessons[i].title,
                            subtitle: lessons[i].weekDate.isEmpty
                                ? null
                                : lessons[i].weekDate,
                            showDivider: i < lessons.length - 1,
                            trailing: const TpBadge(
                              label: '播放',
                              icon: TpIcons.recordings,
                              tone: TpBadgeTone.brand,
                            ),
                            onTap: _busy
                                ? null
                                : () => unawaited(_openLesson(lessons[i])),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }

    final courses = _courses;
    if (courses == null) {
      return _stateCard(
        colors,
        icon: TpIcons.info,
        title: _error ?? '课程列表加载失败',
        action: AdaptiveButton(
          onPressed: _busy ? null : _retryCourses,
          icon: TpIcons.refresh,
          sfSymbol: 'arrow.clockwise',
          label: '重新加载',
          role: AdaptiveButtonRole.prominent,
          height: 44,
          width: 200,
        ),
      );
    }
    if (courses.isEmpty) {
      return _stateCard(
        colors,
        icon: TpIcons.recordings,
        title: '当前账号暂无课程录播',
        subtitle: '如果切换过校园账号或登录已失效，请尝试重新登录。',
        action: AdaptiveButton(
          onPressed: _openLogin,
          icon: TpIcons.login,
          sfSymbol: 'person.crop.circle',
          label: '重新登录',
          role: AdaptiveButtonRole.prominent,
          height: 44,
          width: 200,
        ),
      );
    }

    final q = _searchQuery.trim().toLowerCase();
    final filtered = q.isEmpty
        ? courses
        : courses.where((course) {
            return course.name.toLowerCase().contains(q) ||
                course.description.toLowerCase().contains(q) ||
                (course.courseNo?.toLowerCase().contains(q) ?? false);
          }).toList();

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        TpTokens.pageHorizontalPadding,
        TpTokens.space3,
        TpTokens.pageHorizontalPadding,
        AppShellMetrics.bottomContentPaddingOf(context),
      ),
      children: [
        TpPageBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Search Bar Card
              TpCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: TpTokens.space3,
                  vertical: 2,
                ),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (value) => setState(() => _searchQuery = value),
                  decoration: InputDecoration(
                    hintText: '搜索课程名称或编号',
                    border: InputBorder.none,
                    prefixIcon: Icon(
                      TpIcons.search,
                      size: TpTokens.iconS,
                      color: colors.textMuted,
                    ),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(
                              TpIcons.close,
                              size: TpTokens.iconS,
                            ),
                            tooltip: '清除搜索',
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                          ),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: TpTokens.sectionGap),
                _errorCard(colors, _retryCourses),
              ],
              const SizedBox(height: TpTokens.sectionGap),
              if (filtered.isEmpty)
                TpCard(
                  padding: const EdgeInsets.all(TpTokens.space5),
                  child: Center(
                    child: Text(
                      '没有匹配「$_searchQuery」的课程',
                      style: TpTypography.itemMeta(colors),
                    ),
                  ),
                )
              else
                TpCard(
                  leadingIcon: TpIcons.recordings,
                  title: '课程列表',
                  trailing: Text('${filtered.length} 门'),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < filtered.length; i++)
                        TpListRow(
                          icon: TpIcons.recordings,
                          iconColor: colors.brand,
                          title: filtered[i].name,
                          subtitle: _courseSubtitle(filtered[i]).isEmpty
                              ? null
                              : _courseSubtitle(filtered[i]),
                          showChevron: true,
                          showDivider: i < filtered.length - 1,
                          onTap: _busy
                              ? null
                              : () => unawaited(_loadLessons(filtered[i])),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _auth?.removeListener(_primaryAccountChanged);
    _request++;
    _tpAuth?.removeListener(_bindingChanged);
    _client?.dispose();
    _client = null;
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final title = _webVisible
        ? '登录课程录播'
        : _selectedCourse != null
            ? _selectedCourse!.name
            : '课程录播';

    return PopScope(
      canPop: _selectedCourse == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _showCourses();
      },
      child: Scaffold(
        backgroundColor: colors.canvas,
        appBar: AdaptiveNavigationScaffold.adaptiveBar(
          ios: () => IosNativeNavigationBar(
            title: title,
            leadingItems: [
              IosNativeNavigationBarItem(
                id: 'back',
                sfSymbol: 'chevron.left',
                accessibilityLabel: '返回',
                enabled: _selectedCourse == null || !_busy,
              ),
            ],
            trailingItems: [
              if (!_webVisible && !_starting)
                IosNativeNavigationBarItem(
                  id: 'refresh',
                  sfSymbol: 'arrow.clockwise',
                  accessibilityLabel: '刷新',
                  enabled: !_busy,
                ),
            ],
            onItemPressed: (id) {
              if (id == 'back') {
                if (_selectedCourse != null) {
                  _showCourses();
                } else {
                  unawaited(Navigator.of(context).maybePop());
                }
              } else if (id == 'refresh') {
                if (_selectedCourse == null) {
                  _retryCourses();
                } else {
                  _retryLessons(_selectedCourse!);
                }
              }
            },
          ),
          material: () => AppBar(
            automaticallyImplyLeading: _selectedCourse == null,
            leading: _selectedCourse == null
                ? null
                : IconButton(
                    onPressed: _busy ? null : _showCourses,
                    icon: const Icon(TpIcons.chevronLeft),
                    tooltip: '返回课程列表',
                  ),
            title: Text(title),
            actions: [
              if (!_webVisible && !_starting)
                IconButton(
                  tooltip: '刷新',
                  onPressed: _busy
                      ? null
                      : _selectedCourse == null
                          ? _retryCourses
                          : () => _retryLessons(_selectedCourse!),
                  icon: const Icon(TpIcons.refresh, size: TpTokens.iconM),
                ),
            ],
          ),
        ),
        body: SafeArea(
          top: false,
          child: Stack(
            children: [
              Positioned.fill(child: _content(colors)),
              if (_controller != null)
                Positioned.fill(
                  child: Offstage(
                    offstage: !_webVisible,
                    child: WebViewWidget(controller: _controller!),
                  ),
                ),
              if (_busy &&
                  (_courses != null || _lessons != null) &&
                  !_webVisible)
                const Align(
                  alignment: Alignment.topCenter,
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
