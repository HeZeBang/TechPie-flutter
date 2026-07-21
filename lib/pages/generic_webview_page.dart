import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:desktop_webview_window/desktop_webview_window.dart'
    show WebviewWindow, CreateConfiguration;
import 'package:webview_flutter/webview_flutter.dart'
    show WebViewController, JavaScriptMode, NavigationDelegate,
         NavigationDecision, WebViewWidget, WebViewCookie,
         WebViewCookieManager;

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
    this.cookies,
  });

  final String title;
  final String url;
  final List<WebViewCookie>? cookies;

  @override
  State<GenericWebViewPage> createState() => _GenericWebViewPageState();
}

class _GenericWebViewPageState extends State<GenericWebViewPage> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    if (Platform.isLinux || Platform.isWindows) {
      unawaited(_openDesktop());
    } else {
      _controller = WebViewController();
      unawaited(_initController());
    }
  }

  // -- Desktop path (desktop_webview_window popup) --

  Future<void> _openDesktop() async {
    final cookies = widget.cookies ?? const <WebViewCookie>[];

    final webview = await WebviewWindow.create(
      configuration: CreateConfiguration(
        title: widget.title,
        windowWidth: 900,
        windowHeight: 700,
        // TechPie doesn't use the title bar (Flutter view) that
        // desktop_webview_window creates for navigation buttons —
        // the webview has its own. Set height to 0 so the WebKit
        // view fills the full window without a black bar.
        titleBarHeight: 0,
      ),
    );

    for (final c in cookies) {
      webview.setCookie(
        url: widget.url,
        name: c.name,
        value: c.value,
        domain: c.domain,
        path: c.path,
        isHttpOnly: true,
      );
    }

    webview.launch(widget.url);
    if (mounted) Navigator.of(context).pop();
  }

  // -- Mobile / webview_flutter in-app widget --

  Future<void> _initController() async {
    await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) => NavigationDecision.navigate,
      ),
    );

    final cookieManager = WebViewCookieManager();
    await cookieManager.clearCookies();
    for (final c in widget.cookies ?? const <WebViewCookie>[]) {
      await cookieManager.setCookie(c);
    }

    await _controller.loadRequest(Uri.parse(widget.url));
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
      body: WebViewWidget(controller: _controller),
    );
  }
}
