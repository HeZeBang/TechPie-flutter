import 'dart:async';
import 'dart:io' show Platform;

import 'package:desktop_webview_window/desktop_webview_window.dart'
    show WebviewWindow, CreateConfiguration;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart'
    show
        WebViewController,
        JavaScriptMode,
        NavigationDelegate,
        NavigationDecision,
        WebViewWidget;

import '../services/auth_service.dart';
import '../services/service_provider.dart';
import '../services/third_party_auth_service.dart';

/// A page that hosts a webview.
///
/// On Linux and Windows it opens a separate popup window via
/// [WebviewWindow] (WebKitGTK on Linux, WebView2 on Windows). On all
/// other platforms it uses [WebViewWidget] (webview_flutter) for an
/// in-app webview.
class GenericWebViewPage extends StatefulWidget {
  const GenericWebViewPage({
    super.key,
    required this.title,
    required this.url,
  });

  final String title;
  final String url;

  @override
  State<GenericWebViewPage> createState() => _GenericWebViewPageState();
}

class _GenericWebViewPageState extends State<GenericWebViewPage> {
  late final WebViewController _controller;

  ThirdPartyAuthService? _tpAuth;
  AuthService? _auth;
  String? _primaryUserId;
  int _generation = -1;
  String? _error;

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
      _error = '请先登录 TechPie';
      return;
    }
    _generation = _tpAuth!.cpdailyNode.generation;
    _tpAuth!.addListener(_bindingChanged);
    if (Platform.isLinux || Platform.isWindows) {
      unawaited(_openDesktop());
    } else {
      _controller = WebViewController();
      unawaited(_initController());
    }
  }

  void _bindingChanged() {
    if (_generation == _tpAuth!.cpdailyNode.generation) return;
    if (mounted) Navigator.of(context).pop();
  }

  bool get _authorized =>
      _auth!.isLoggedIn && _auth!.session?.userId == _primaryUserId;

  void _primaryAccountChanged() {
    if (_authorized || !mounted) return;
    setState(() => _error = '请先登录 TechPie');
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  void dispose() {
    _auth?.removeListener(_primaryAccountChanged);
    _tpAuth?.removeListener(_bindingChanged);
    super.dispose();
  }

  // -- Desktop path (desktop_webview_window popup) --

  Future<void> _openDesktop() async {
    final webview = await WebviewWindow.create(
      configuration: CreateConfiguration(
        title: widget.title,
        windowWidth: 900,
        windowHeight: 700,
      ),
    );

    webview.launch(widget.url);
    if (mounted) Navigator.of(context).pop();
  }

  // -- Mobile / webview_flutter in-app widget --

  Future<void> _initController() async {
    try {
      await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await _controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) => _authorized
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
        ),
      );

      await _tpAuth!.campusWebSession.useIdsSession();
      if (!mounted ||
          !_authorized ||
          _generation != _tpAuth!.cpdailyNode.generation) {
        return;
      }
      await _controller.loadRequest(Uri.parse(widget.url));
    } catch (_) {
      if (mounted) setState(() => _error = '校园网页加载失败，请稍后重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isLinux || Platform.isWindows) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title), centerTitle: true),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.title), centerTitle: true),
      body: _error == null
          ? WebViewWidget(controller: _controller)
          : Center(child: Text(_error!)),
    );
  }
}
