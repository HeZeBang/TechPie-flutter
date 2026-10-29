import 'dart:async';

import 'package:desktop_webview_window/desktop_webview_window.dart' show Webview;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/webview_bridge.dart';
import 'webview_host.dart';

/// A debug-only webview page that accepts a custom URL.
class DebugWebViewPage extends StatefulWidget {
  const DebugWebViewPage({super.key, this.initialUrl});

  final String? initialUrl;

  @override
  State<DebugWebViewPage> createState() => _DebugWebViewPageState();
}

class _DebugWebViewPageState extends State<DebugWebViewPage>
    with BhWebViewHost<DebugWebViewPage>, WidgetsBindingObserver {
  late final WebViewController _controller;
  final TextEditingController _urlController = TextEditingController();
  Webview? _desktopWebview;
  String? _bridgeMessage;

  @override
  Webview? get desktopWebview => _desktopWebview;

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
    _urlController.text = widget.initialUrl ?? '';
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
    _urlController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(notifyBhMobileSdkResume());
    }
  }

  Future<void> _openDesktop() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    final webview = await openDesktopWebview(title: 'Debug WebView', url: url);
    if (webview == null) return;
    webview.addOnWebMessageReceivedCallback((message) {
      if (mounted) setState(() => _bridgeMessage = message);
    });
    _desktopWebview = webview;
  }

  Future<void> _initController() async {
    await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) => NavigationDecision.navigate,
      ),
    );
    installBhMobileSdkBridge();
    await _controller.addJavaScriptChannel(
      'TechPieBridge',
      onMessageReceived: (JavaScriptMessage message) {
        unawaited(handleBhMobileSdkMessage(message.message));
        if (mounted) setState(() => _bridgeMessage = message.message);
      },
    );
    await _controller.addUserScripts(const <WebViewUserScript>[
      WebViewUserScript(source: techPieDocumentStartScript),
    ]);
    if (_urlController.text.isNotEmpty) {
      unawaited(_controller.loadRequest(Uri.parse(_urlController.text)));
    }
  }

  Future<void> _load() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    if (isDesktopWebView) {
      final webview = await openDesktopWebview(
        title: 'Debug WebView',
        url: url,
      );
      if (webview != null) _desktopWebview = webview;
      return;
    }
    await _controller.loadRequest(Uri.parse(url));
  }

  @override
  Widget build(BuildContext context) {
    final urlRow = Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                hintText: 'https://…', isDense: true, border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              onSubmitted: (_) => unawaited(_load()),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: _load, child: const Text('Go')),
        ],
      ),
    );
    final bridgeText = _bridgeMessage == null
        ? const <Widget>[]
        : <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Bridge: $_bridgeMessage', style: const TextStyle(fontSize: 12, color: Colors.green)),
              ),
            ),
          ];
    return Scaffold(
      appBar: buildHostNavigationBar('Debug WebView'),
      body: isDesktopWebView
          ? Column(children: [urlRow, ...bridgeText, const Text('Desktop WebView opened in separate window')])
          : Column(
              children: [
                urlRow,
                ...bridgeText,
                Expanded(
                  // Bottom only: inside a tab the page sits above the tab bar.
                  child: SafeArea(
                    top: false,
                    left: false,
                    right: false,
                    child: WebViewWidget(controller: _controller),
                  ),
                ),
              ],
            ),
    );
  }
}
