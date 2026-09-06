import 'dart:async';

import 'package:desktop_webview_window/desktop_webview_window.dart'
    show Webview, WebviewWindow, CreateConfiguration;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/school_web_session_service.dart';

bool isAllowedWebViewNavigation(
  String requestUrl,
  Set<String> allowedHostSuffixes,
) {
  final uri = Uri.tryParse(requestUrl);
  if (uri == null || uri.scheme != 'https') return false;
  final host = uri.host.toLowerCase();
  return allowedHostSuffixes.any((rawSuffix) {
    final suffix = rawSuffix.toLowerCase();
    return host == suffix || host.endsWith('.$suffix');
  });
}

/// Hosts an in-app WebView, or a separate popup on Linux and Windows.
class GenericWebViewPage extends StatefulWidget {
  const GenericWebViewPage({
    super.key,
    required this.title,
    required this.url,
    this.cookies,
    this.clearCookiesBeforeLoad = true,
    this.allowedHostSuffixes,
    this.schoolSession,
  });

  final String title;
  final String url;
  final List<WebViewCookie>? cookies;
  final bool clearCookiesBeforeLoad;
  final Set<String>? allowedHostSuffixes;
  // Managed school pages read the current binding after serialized cleanup;
  // the cookies argument is only used by standalone pages.
  final SchoolWebSessionService? schoolSession;

  @override
  State<GenericWebViewPage> createState() => _GenericWebViewPageState();
}

class _GenericWebViewPageState extends State<GenericWebViewPage> {
  final _desktop = defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.windows;
  late final WebViewController _controller;
  Webview? _desktopView;
  VoidCallback? _detach;
  late final int? _generation;
  bool _invalidated = false;
  bool _failed = false;

  bool get _isOpen => mounted && !_invalidated;

  @override
  void initState() {
    super.initState();
    _generation = widget.schoolSession?.generation;
    _detach = widget.schoolSession?.attach(_invalidate);
    if (!_desktop) _controller = WebViewController();
    unawaited(_open());
  }

  Future<void> _invalidate() async {
    if (!mounted) return;
    setState(() => _invalidated = true);
    await _stopView();
  }

  Future<void> _stopView() async {
    if (_desktop) {
      final view = _desktopView;
      if (view != null) {
        view.close();
        await view.onClose;
      }
    } else {
      try {
        await _controller.runJavaScript('window.stop();');
      } catch (_) {/* A not-yet-loaded document may have no JS context. */}
      // Stop redirects and discard the old document before clearing its jar.
      await _controller
          .loadHtmlString('<!doctype html><html><body></body></html>');
    }
  }

  Future<void> _open() async {
    try {
      if (_desktop) {
        await _openDesktop();
      } else {
        await _initController();
      }
    } catch (_) {
      if (_isOpen) setState(() => _failed = true);
    }
  }

  Future<void> _prepareAndLoad({
    required Future<void> Function(WebViewCookie) setCookie,
    required Future<void> Function() load,
    Future<void> Function()? prepare,
  }) async {
    final school = widget.schoolSession;
    if (school != null) {
      await school.open(
        generation: _generation!,
        isOpen: () => _isOpen,
        prepare: prepare,
        setCookie: setCookie,
        load: load,
      );
      return;
    }
    if (widget.clearCookiesBeforeLoad) {
      if (_desktop) {
        await WebviewWindow.clearAll();
      } else {
        await WebViewCookieManager().clearCookies();
      }
    }
    if (!_isOpen) return;
    await prepare?.call();
    if (!_isOpen) return;
    for (final cookie in widget.cookies ?? const <WebViewCookie>[]) {
      await setCookie(cookie);
      if (!_isOpen) return;
    }
    await load();
  }

  Future<void> _openDesktop() async {
    await _prepareAndLoad(
      prepare: () async {
        _desktopView = await WebviewWindow.create(
          configuration: CreateConfiguration(
            title: widget.title,
            windowWidth: 900,
            windowHeight: 700,
          ),
        );
        if (!_isOpen) await _stopView();
      },
      setCookie: (c) async => _desktopView!.setCookie(
        url: widget.url,
        name: c.name,
        value: c.value,
        domain: c.domain,
        path: c.path,
        isHttpOnly: true,
      ),
      load: () async => _desktopView!.launch(widget.url),
    );
    final view = _desktopView;
    if (view == null) return;
    // Keep the binding listener alive while the separate window is open.
    await view.onClose;
    if (mounted && !_invalidated) Navigator.of(context).pop();
  }

  Future<void> _initController() async {
    await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          if (_invalidated && request.url == 'about:blank') {
            return NavigationDecision.navigate;
          }
          if (!_isOpen) return NavigationDecision.prevent;
          final suffixes = widget.allowedHostSuffixes;
          return suffixes == null ||
                  isAllowedWebViewNavigation(request.url, suffixes)
              ? NavigationDecision.navigate
              : NavigationDecision.prevent;
        },
      ),
    );
    await _prepareAndLoad(
      setCookie: WebViewCookieManager().setCookie,
      load: () => _controller.loadRequest(Uri.parse(widget.url)),
    );
  }

  @override
  void dispose() {
    _detach?.call();
    unawaited(_stopView().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_invalidated) {
      body = const Center(child: Text('学校绑定已更改，请返回后重新打开。'));
    } else if (_failed) {
      body = const Center(child: Text('网页会话初始化失败，请返回后重试。'));
    } else if (_desktop) {
      body = const Center(child: Text('请在独立窗口中查看网页。'));
    } else {
      body = WebViewWidget(controller: _controller);
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), centerTitle: true),
      body: body,
    );
  }
}
