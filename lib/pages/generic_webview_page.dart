import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/service_provider.dart';
import '../widgets/adaptive_alert_dialog.dart';
import '../widgets/adaptive_feedback.dart';

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

  Future<void> _showCookies() async {
    // 1. 获取初始注入的 Cookies
    String injectedCookies = '无';
    if (widget.cookies != null && widget.cookies!.isNotEmpty) {
      injectedCookies = widget.cookies!
          .map((c) => '${c.name}=${c.value}\n(Domain: ${c.domain})')
          .join('\n\n');
    }

    // 2. 获取当前页面真实的 document.cookie
    String documentCookies = '';
    try {
      final jsResult =
          await controller.runJavaScriptReturningResult('document.cookie');
      documentCookies = jsResult.toString();
      // webview_flutter 可能会给返回的字符串加引号，去掉首尾引号
      if (documentCookies.startsWith('"') &&
          documentCookies.endsWith('"') &&
          documentCookies.length >= 2) {
        documentCookies =
            documentCookies.substring(1, documentCookies.length - 1);
      }
      if (documentCookies.isEmpty) {
        documentCookies = '无 (注: HttpOnly 无法通过 JS 获取)';
      } else {
        documentCookies = documentCookies.replaceAll('; ', '\n');
      }
    } catch (e) {
      documentCookies = '获取失败: $e';
    }

    final cookieStr = '=== 初始注入的 Cookies ===\n'
        '$injectedCookies\n\n'
        '=== 网页当前的 Cookies ===\n'
        '$documentCookies';

    final result = await showAdaptiveAlertDialog<String>(
      context: context,
      title: '当前 Cookies (Debug)',
      message: cookieStr,
      actions: const [
        AdaptiveAlertAction(label: '复制', value: 'copy'),
        AdaptiveAlertAction(label: '关闭', value: 'close', isDefault: true),
      ],
    );

    if (result == 'copy') {
      await Clipboard.setData(ClipboardData(text: cookieStr));
      if (mounted) {
        showAdaptiveFeedback(
          context: context,
          message: '已复制到剪贴板',
          style: AdaptiveFeedbackStyle.success,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDebug = ServiceProvider.of(context).storageService.debugMode;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: '更多',
            onSelected: (value) {
              if (value == 'mobile') {
                _switchUseMobileService(!_useMobileService);
              } else if (value == 'cookies') {
                _showCookies();
              }
            },
            itemBuilder: (context) {
              final items = <PopupMenuEntry<String>>[];

              if (widget.mobileUrl != null) {
                items.add(
                  CheckedPopupMenuItem<String>(
                    value: 'mobile',
                    checked: _useMobileService,
                    child: const Text('使用移动版服务'),
                  ),
                );
              } else {
                items.add(
                  const PopupMenuItem<String>(
                    enabled: false,
                    child: Text('无可用移动版服务'),
                  ),
                );
              }

              if (isDebug) {
                items.add(
                  const PopupMenuItem<String>(
                    value: 'cookies',
                    child: Text('查看 Cookies (Debug)'),
                  ),
                );
              }

              return items;
            },
          ),
        ],
      ),
      body: WebViewWidget(controller: controller),
    );
  }
}
