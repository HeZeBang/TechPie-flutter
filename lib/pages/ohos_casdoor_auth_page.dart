import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// OAuth WebView for OHOS, where Casdoor's SDK has no platform implementation.
class OhosCasdoorAuthPage extends StatefulWidget {
  const OhosCasdoorAuthPage({
    super.key,
    required this.authorizeUrl,
    required this.callbackScheme,
  });

  final String authorizeUrl;
  final String callbackScheme;

  @override
  State<OhosCasdoorAuthPage> createState() => _OhosCasdoorAuthPageState();
}

class _OhosCasdoorAuthPageState extends State<OhosCasdoorAuthPage> {
  late final WebViewController _controller;
  double _progress = 0;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController();
    unawaited(_configureController());
  }

  Future<void> _configureController() async {
    await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: _handleNavigation,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress / 100);
        },
      ),
    );
    await _controller.loadRequest(Uri.parse(widget.authorizeUrl));
  }

  NavigationDecision _handleNavigation(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri?.scheme != widget.callbackScheme) {
      return NavigationDecision.navigate;
    }

    _completed = true;
    Navigator.of(context).pop(request.url);
    return NavigationDecision.prevent;
  }

  void _onWillPop() {
    if (!_completed) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onWillPop();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('登录')),
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_progress < 1) LinearProgressIndicator(value: _progress),
          ],
        ),
      ),
    );
  }
}
