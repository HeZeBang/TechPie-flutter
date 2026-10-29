import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../utils/platform.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';

/// Shared OAuth browser; credentials stay in the identity provider's WebView.
class UniAuthWebViewPage extends StatefulWidget {
  const UniAuthWebViewPage({super.key, required this.authorizeUrl, required this.callbackUri});

  final String authorizeUrl;
  final Uri callbackUri;

  @override
  State<UniAuthWebViewPage> createState() => _UniAuthWebViewPageState();
}

class _UniAuthWebViewPageState extends State<UniAuthWebViewPage> {
  late final WebViewController _controller;
  double _progress = 0;
  bool _completed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController();
    unawaited(_configureController());
  }

  Future<void> _configureController() async {
    try {
      await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await _controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _handleNavigation,
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress / 100);
          },
          onWebResourceError: (error) {
            if (mounted && error.isForMainFrame == true) {
              setState(() => _error = '认证页面加载失败，请重试');
            }
          },
        ),
      );
      await _load();
    } catch (_) {
      if (mounted) setState(() => _error = '认证页面加载失败，请重试');
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _error = null;
      _progress = 0;
    });
    try {
      await _controller.loadRequest(Uri.parse(widget.authorizeUrl));
    } catch (_) {
      if (mounted) setState(() => _error = '认证页面加载失败，请重试');
    }
  }

  NavigationDecision _handleNavigation(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    final callback = widget.callbackUri;
    if (uri?.scheme != callback.scheme) return NavigationDecision.navigate;
    if (!_completed &&
        mounted &&
        request.isMainFrame &&
        uri?.host == callback.host &&
        uri?.path == callback.path) {
      _completed = true;
      Navigator.of(context).pop(request.url);
    }
    return NavigationDecision.prevent;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: isIos()
          ? IosNativeNavigationBar(
              title: 'GeekPie Uni-Auth',
              leadingItems: const [
                IosNativeNavigationBarItem(
                  id: 'back',
                  sfSymbol: 'chevron.left',
                  accessibilityLabel: '取消登录',
                ),
              ],
              onItemPressed: (_) => Navigator.of(context).pop(),
            )
          : AppBar(title: const Text('GeekPie Uni-Auth')),
      body: SafeArea(
        top: false,
        child: _error != null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!),
                    TextButton(onPressed: _load, child: const Text('重试')),
                  ],
                ),
              )
            : Stack(
                children: [
                  WebViewWidget(controller: _controller),
                  if (_progress < 1) LinearProgressIndicator(value: _progress),
                ],
              ),
      ),
    );
  }
}
