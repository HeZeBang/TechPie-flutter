import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class GenericWebViewPage extends StatefulWidget {
  const GenericWebViewPage({
    super.key,
    required this.title,
    required this.url,
    this.mobileUrl,
    this.initialUseMobileService = false,
    this.cookies,
  });

  final String title;
  final String url;
  final String? mobileUrl;
  final bool initialUseMobileService;
  final List<WebViewCookie>? cookies;

  @override
  State<GenericWebViewPage> createState() => _GenericWebViewPageState();
}

class _GenericWebViewPageState extends State<GenericWebViewPage> {
  late final WebViewController controller;
  late bool _useMobileService;

  String get _currentUrl {
    if (_useMobileService && widget.mobileUrl != null) {
      return widget.mobileUrl!;
    }
    return widget.url;
  }

  @override
  void initState() {
    super.initState();

    _useMobileService =
        widget.initialUseMobileService && widget.mobileUrl != null;

    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            return NavigationDecision.navigate;
          },
        ),
      );

    _loadWithCookies();
  }

  Future<void> _loadWithCookies() async {
    final cookieManager = WebViewCookieManager();

    await cookieManager.clearCookies();

    for (final cookie in widget.cookies ?? const <WebViewCookie>[]) {
      await cookieManager.setCookie(cookie);
    }

    await controller.loadRequest(Uri.parse(_currentUrl));
  }

  Future<void> _switchUseMobileService(bool useMobileService) async {
    if (_useMobileService == useMobileService || widget.mobileUrl == null) {
      return;
    }

    setState(() {
      _useMobileService = useMobileService;
    });

    await controller.loadRequest(Uri.parse(_currentUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        centerTitle: true,
        actions: [
          PopupMenuButton<bool>(
            icon: const Icon(Icons.more_vert),
            tooltip: '更多',
            onSelected: _switchUseMobileService,
            itemBuilder: (context) {
              if (widget.mobileUrl == null) {
                return const [
                  PopupMenuItem<bool>(
                    enabled: false,
                    child: Text('无可用移动版服务'),
                  ),
                ];
              }

              return [
                CheckedPopupMenuItem<bool>(
                  value: !_useMobileService,
                  checked: _useMobileService,
                  child: const Text('使用移动版服务'),
                ),
              ];
            },
          ),
        ],
      ),
      body: WebViewWidget(controller: controller),
    );
  }
}
