import 'dart:async';

import 'package:desktop_webview_window/desktop_webview_window.dart' show Webview;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart'
    show
        JavaScriptMessage,
        WebViewController,
        WebViewUserScript,
        JavaScriptMode,
        NavigationDelegate,
        NavigationDecision,
        WebViewWidget,
        WebViewCookieManager;

import '../models/feature.dart';
import '../services/auth_service.dart';
import '../services/service_provider.dart';
import '../services/third_party_auth_service.dart';
import '../services/webview_bridge.dart';
import 'webview_host.dart';

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
    this.cookieType,
    this.initialUserScripts = const <WebViewUserScript>[],
  });

  final String title;
  final String url;

  /// The campus session this page authenticates against. Null for a page with
  /// no campus session (a plain URL).
  final CookieType? cookieType;

  final List<WebViewUserScript> initialUserScripts;

  @override
  State<GenericWebViewPage> createState() => _GenericWebViewPageState();
}

class _GenericWebViewPageState extends State<GenericWebViewPage>
    with BhWebViewHost<GenericWebViewPage>, WidgetsBindingObserver {
  late final WebViewController _controller;
  Webview? _desktopWebview;
  String? _desktopError;

  ThirdPartyAuthService? _tpAuth;
  AuthService? _auth;
  String? _primaryUserId;
  String? _owner;
  String? _error;

  @override
  Webview? get desktopWebview => _desktopWebview;

  @override
  CookieType? get hostCookieType => widget.cookieType;

  @override
  Future<void> runPageJavaScript(String script) async {
    if (isDesktopWebView) {
      await _desktopWebview?.evaluateJavaScript(script);
      return;
    }
    await _controller.runJavaScript(script);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

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
    _owner = _tpAuth!.campusWebSession.owner;
    _tpAuth!.addListener(_bindingChanged);
    if (isDesktopWebView) {
      unawaited(_openDesktop());
    } else {
      _controller = WebViewController();
      unawaited(_initController());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _auth?.removeListener(_primaryAccountChanged);
    _tpAuth?.removeListener(_bindingChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(notifyBhMobileSdkResume());
    }
  }

  void _bindingChanged() {
    if (_owner == _tpAuth!.campusWebSession.owner) return;
    if (mounted) Navigator.of(context).pop();
  }

  bool get _authorized =>
      _auth!.isLoggedIn && _auth!.session?.userId == _primaryUserId;

  void _primaryAccountChanged() {
    if (_authorized || !mounted) return;
    setState(() => _error = '请先登录 TechPie');
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  // -- Desktop path (desktop_webview_window popup) --

  Future<void> _openDesktop() async {
    await prepareHostSession();
    if (!mounted) return;
    final webview = await openDesktopWebview(
      title: widget.title,
      url: widget.url,
      cookies: hostCookies,
      session: hostSession,
      initialScripts: <String>[
        for (final script in widget.initialUserScripts) script.source,
      ],
    );
    if (webview == null) {
      if (mounted) {
        setState(
          () => _desktopError = 'The WebView window could not be opened',
        );
      }
      return;
    }
    _desktopWebview = webview;
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

      installBhMobileSdkBridge();
      await _controller.addJavaScriptChannel(
        'TechPieBridge',
        onMessageReceived: (JavaScriptMessage message) {
          unawaited(handleBhMobileSdkMessage(message.message));
        },
      );

      await _controller.addUserScripts(<WebViewUserScript>[
        ...widget.initialUserScripts,
        const WebViewUserScript(source: techPieDocumentStartScript),
      ]);

      // The campus pages share one cookie store, whose reset on an account
      // change [CampusWebSession] owns: that wipe runs first (along with the
      // feature's scheduled renew), then this page writes the cookies of the
      // session it authenticates against — ecourse on the IDS/CASTGC session
      // directly, egate on its own MOD_AUTH_CAS/_WEU session derived from it.
      // Nothing is injected before the wipe, so nothing is collateral.
      await prepareHostSession();
      final session = _tpAuth!.campusWebSession;
      await session.clearLocalStorageIfDue(_controller);
      if (!mounted ||
          !_authorized ||
          _owner != session.owner) {
        return;
      }

      final cookieManager = WebViewCookieManager();
      for (final c in hostCookies) {
        await cookieManager.setCookie(c);
      }

      await _controller.loadRequest(Uri.parse(widget.url));
    } catch (_) {
      if (mounted) setState(() => _error = '校园网页加载失败，请稍后重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final appBar = hostNavBarVisible
        ? AppBar(title: Text(hostPageTitle ?? widget.title), centerTitle: true)
        : null;
    if (isDesktopWebView) {
      return Scaffold(
        appBar: appBar,
        body: Center(
          child: _desktopError == null
              ? const CircularProgressIndicator()
              : Text(_desktopError!),
        ),
      );
    }

    return Scaffold(
      appBar: appBar,
      // Bottom only: inside a tab the page sits above the tab bar.
      body: SafeArea(
        top: false,
        left: false,
        right: false,
        child: _error == null
            ? WebViewWidget(controller: _controller)
            : Center(child: Text(_error!)),
      ),
    );
  }
}
