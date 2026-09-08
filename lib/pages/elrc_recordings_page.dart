import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/elrc_client.dart';
import '../services/service_provider.dart';
import '../services/third_party_auth_service.dart';
import '../widgets/adaptive_page_navigation.dart';
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

  WebViewController? _controller;
  ElrcClient? _client;
  List<ElrcCourse>? _courses;
  ElrcCourse? _selectedCourse;
  List<ElrcLesson>? _lessons;
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
  int _bindingGeneration = -1;
  bool _campusAttempted = false;

  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_tpAuth != null) return;
    _tpAuth = ServiceProvider.of(context).thirdPartyAuthService;
    _bindingGeneration = _tpAuth!.cpdailyNode.generation;
    _tpAuth!.addListener(_bindingChanged);
    if (_supported) unawaited(_prepare());
  }

  void _bindingChanged() {
    final generation = _tpAuth!.cpdailyNode.generation;
    if (generation == _bindingGeneration || !mounted) return;
    _bindingGeneration = generation;
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

  Future<void> _prepare() async {
    final generation = _bindingGeneration;
    final controller = WebViewController();
    final client = ElrcClient(controller);
    try {
      await _tpAuth!.campusWebSession.prepare();
      if (!mounted || generation != _bindingGeneration) {
        client.dispose();
        return;
      }
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await client.initialize();
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (!identical(_controller, controller)) {
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
              unawaited(
                controller.loadRequest(target),
              );
              return NavigationDecision.prevent;
            }
            if (_isLogin(uri) &&
                !_campusAttempted &&
                _tpAuth!.hasCpdailyBinding) {
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
      if (!mounted || generation != _bindingGeneration) {
        client.dispose();
        return;
      }
      _controller = controller;
      _client = client;
      setState(() {});
      await controller.loadRequest(_reviewUri);
    } catch (_) {
      client.dispose();
      if (!mounted || generation != _bindingGeneration) return;
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
      if (!mounted || request != _request) return;
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
        final reused = await _tpAuth!.campusWebSession.useIdsSession();
        _trace(reused
            ? 'IDS cookie prepared; awaiting official SSO'
            : 'manual login required',);
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
      _trace('course request completed');
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
      _trace('course request failed; needsLogin=${error.needsLogin}');
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
      await pushAdaptivePage<void>(
        context,
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

  Widget _message(String text, VoidCallback retry) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.info_outline, size: 42),
              const SizedBox(height: 12),
              Text(text, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : retry,
                child: const Text('重新加载'),
              ),
            ],
          ),
        ),
      );

  Widget _errorCard(VoidCallback retry) => Card.filled(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
              TextButton(
                onPressed: _busy ? null : retry,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );

  Widget _content() {
    if (!_supported) {
      return const Center(child: Text('请在 iPhone 或 Android 手机中观看录播'));
    }
    if (_error != null && _courses == null && !_webVisible) {
      return _message(_error!, _retryCourses);
    }
    if ((_starting || _busy) && _courses == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final selectedCourse = _selectedCourse;
    if (selectedCourse != null) {
      final lessons = _lessons;
      if (_busy && lessons == null) {
        return const Center(child: CircularProgressIndicator());
      }
      if (lessons == null) {
        return _message(
          _error ?? '录播课次加载失败',
          () => _retryLessons(selectedCourse),
        );
      }
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (selectedCourse.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(selectedCourse.description),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _errorCard(() => _retryLessons(selectedCourse)),
            ),
          for (final lesson in lessons)
            Card.outlined(
              child: ListTile(
                title: Text(lesson.title),
                subtitle:
                    lesson.weekDate.isEmpty ? null : Text(lesson.weekDate),
                trailing: const Icon(Icons.play_circle_outline),
                onTap: _busy ? null : () => unawaited(_openLesson(lesson)),
              ),
            ),
        ],
      );
    }

    final courses = _courses;
    if (courses == null) {
      return _message(_error ?? '课程列表加载失败', _retryCourses);
    }
    if (courses.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('当前账号暂无课程录播'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _openLogin,
              child: const Text('重新登录'),
            ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _errorCard(_retryCourses),
          ),
        for (final course in courses)
          Card.outlined(
            child: ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: Text(course.name),
              subtitle:
                  course.description.isEmpty ? null : Text(course.description),
              trailing: const Icon(Icons.chevron_right),
              onTap: _busy ? null : () => unawaited(_loadLessons(course)),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _request++;
    _tpAuth?.removeListener(_bindingChanged);
    _client?.dispose();
    _client = null;
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: _selectedCourse == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _showCourses();
        },
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: _selectedCourse == null,
            leading: _selectedCourse == null
                ? null
                : IconButton(
                    onPressed: _busy ? null : _showCourses,
                    icon: const Icon(Icons.arrow_back),
                  ),
            title: Text(_webVisible ? '登录课程录播' : '课程录播'),
            actions: [
              if (!_webVisible && !_starting)
                IconButton(
                  tooltip: '刷新',
                  onPressed: _busy
                      ? null
                      : _selectedCourse == null
                          ? _retryCourses
                          : () => _retryLessons(_selectedCourse!),
                  icon: const Icon(Icons.refresh),
                ),
            ],
          ),
          body: SafeArea(
            child: Stack(
              children: [
                Positioned.fill(child: _content()),
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
