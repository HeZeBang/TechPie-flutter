import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/third_party_account.dart';
import '../services/auth_service.dart';
import '../services/debug_logger.dart';
import '../services/elrc_client.dart';
import '../services/service_provider.dart';
import '../services/third_party_auth_service.dart';
import '../widgets/adaptive_page_navigation.dart';
import 'elrc_player_page.dart';
import 'third_party_bind_page.dart';

class ElrcRecordingsPage extends StatefulWidget {
  const ElrcRecordingsPage({super.key});

  @override
  State<ElrcRecordingsPage> createState() => _ElrcRecordingsPageState();
}

class _ElrcRecordingsPageState extends State<ElrcRecordingsPage> {
  ElrcClient? _client;
  List<ElrcCourse>? _courses;
  ElrcCourse? _selectedCourse;
  List<ElrcLesson>? _lessons;
  String? _error;
  bool _needsLogin = false;
  int _request = 0;
  bool _starting = true;
  bool _busy = false;
  ThirdPartyAuthService? _tpAuth;
  late final DebugLogger _debugLogger;
  AuthService? _auth;
  String? _primaryUserId;
  String? _bindingOwner;

  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_tpAuth != null) return;
    final services = ServiceProvider.of(context);
    _debugLogger = services.debugLogger;
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
    if (_supported) _prepare();
  }

  bool get _authorized => _auth!.isLoggedIn && _auth!.session?.userId == _primaryUserId;

  void _primaryAccountChanged() {
    if (_authorized || !mounted) return;
    _request++;
    _client?.dispose();
    _client = null;
    setState(() {
      _courses = null;
      _lessons = null;
      _selectedCourse = null;
      _needsLogin = false;
      _starting = false;
      _error = '请先登录 TechPie';
    });
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _bindingChanged() {
    final generation = _tpAuth!.campusWebSession.owner;
    if (generation == _bindingOwner || !mounted) return;
    _bindingOwner = generation;
    _request++;
    _client?.dispose();
    _client = null;
    setState(() {
      _courses = null;
      _lessons = null;
      _selectedCourse = null;
      _needsLogin = false;
      _busy = false;
      _starting = true;
    });
    if (_supported) _prepare();
  }

  void _prepare() {
    _client?.dispose();
    final client = _client = ElrcClient(auth: _tpAuth!, logger: _debugLogger);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _authorized && identical(_client, client)) {
        unawaited(_loadCourses());
      }
    });
  }

  Future<void> _reloadReview() async {
    final request = ++_request;
    setState(() {
      _courses = null;
      _selectedCourse = null;
      _lessons = null;
      _needsLogin = false;
      _error = null;
      _starting = true;
      _busy = false;
    });
    if (mounted && _authorized && request == _request) await _loadCourses();
  }

  Future<void> _loadCourses() async {
    final client = _client;
    if (client == null || _busy) return;
    final request = ++_request;
    setState(() {
      _busy = true;
      _starting = false;
      _error = null;
      _needsLogin = false;
    });
    try {
      final courses = await client.courses();
      if (!mounted || request != _request) return;
      setState(() {
        _courses = courses;
        _selectedCourse = null;
        _lessons = null;
      });
    } on ElrcException catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = error.message;
        _needsLogin = error.needsLogin;
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
    if (client == null || _busy) return;
    final request = ++_request;
    setState(() {
      _selectedCourse = course;
      _lessons = null;
      _error = null;
      _needsLogin = false;
      _busy = true;
    });
    try {
      final lessons = await client.lessons(course);
      if (!mounted || request != _request) return;
      setState(() => _lessons = lessons);
    } on ElrcException catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = error.message;
        _needsLogin = error.needsLogin;
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
      _needsLogin = false;
    });
    try {
      final sources = await client.sources(course, lesson);
      if (!mounted || request != _request) return;
      setState(() => _busy = false);
      final cookie = client.mediaCookie;
      if (!mounted || request != _request) return;
      await pushAdaptivePage<void>(
        context,
        builder: (_) => ElrcPlayerPage(
          courseName: course.name,
          lessonTitle: lesson.title,
          referer: course.referer,
          sources: sources,
          cookie: cookie,
        ),
      );
    } on ElrcException catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = error.message;
        _needsLogin = error.needsLogin;
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
    });
  }

  void _retryCourses() {
    unawaited(_courses == null ? _reloadReview() : _loadCourses());
  }

  void _retryLessons(ElrcCourse course) {
    unawaited(_loadLessons(course));
  }

  void _openCampusLogin() => unawaited(
        pushAdaptivePage<void>(
          context,
          builder: (_) => const ThirdPartyBindPage(platform: ThirdPartyPlatform.cpdaily),
        ),
      );

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
              if (_needsLogin)
                TextButton(
                  onPressed: _openCampusLogin,
                  child: const Text('重新登录校园账号'),
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
              if (_needsLogin)
                TextButton(
                  onPressed: _openCampusLogin,
                  child: const Text('重新登录'),
                ),
            ],
          ),
        ),
      );

  Widget _content() {
    if (!_supported) {
      return const Center(child: Text('当前平台暂不支持录播'));
    }
    if (_error != null && _courses == null) {
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
                subtitle: lesson.weekDate.isEmpty ? null : Text(lesson.weekDate),
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
              onPressed: _reloadReview,
              child: const Text('重新加载'),
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
              subtitle: course.description.isEmpty ? null : Text(course.description),
              trailing: const Icon(Icons.chevron_right),
              onTap: _busy ? null : () => unawaited(_loadLessons(course)),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _auth?.removeListener(_primaryAccountChanged);
    _request++;
    _tpAuth?.removeListener(_bindingChanged);
    _client?.dispose();
    _client = null;
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
            title: const Text('课程录播'),
            actions: [
              if (!_starting)
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
                if (_busy && (_courses != null || _lessons != null))
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
