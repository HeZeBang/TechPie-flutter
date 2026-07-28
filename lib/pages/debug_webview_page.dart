import 'dart:async';
import 'dart:io' show Platform;

import 'package:desktop_webview_window/desktop_webview_window.dart'
    show CreateConfiguration, WebviewWindow;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/webview_bridge.dart';

/// A debug-only webview page that accepts a custom URL.
class DebugWebViewPage extends StatefulWidget {
  const DebugWebViewPage({super.key, this.initialUrl});

  final String? initialUrl;

  @override
  State<DebugWebViewPage> createState() => _DebugWebViewPageState();
}

class _DebugWebViewPageState extends State<DebugWebViewPage> {
  late final WebViewController _controller;
  final TextEditingController _urlController = TextEditingController();
  String? _bridgeMessage;

  @override
  void initState() {
    super.initState();
    _urlController.text = widget.initialUrl ?? '';
    if (Platform.isLinux || Platform.isWindows) {
      unawaited(_openDesktop());
    } else {
      _controller = WebViewController();
      unawaited(_initController());
    }
  }

  Future<void> _openDesktop() async {
    final webview = await WebviewWindow.create(
      configuration: const CreateConfiguration(
        title: 'Debug WebView', windowWidth: 900, windowHeight: 700,
      ),
    );
    webview.addOnWebMessageReceivedCallback((message) {
      if (mounted) setState(() => _bridgeMessage = message);
    });
    webview.addScriptToExecuteOnDocumentCreated(techPieDocumentStartScript);
    final url = _urlController.text.trim();
    if (url.isNotEmpty) webview.launch(url);
  }

  Future<void> _initController() async {
    await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) => NavigationDecision.navigate,
      ),
    );
    await _controller.addJavaScriptChannel(
      'TechPieBridge',
      onMessageReceived: (JavaScriptMessage message) {
        setState(() => _bridgeMessage = message.message);
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
    if (url.isNotEmpty) {
      if (Platform.isLinux || Platform.isWindows) {
        await _openDesktop();
      } else {
        await _controller.loadRequest(Uri.parse(url));
      }
    }
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
      appBar: AppBar(title: const Text('Debug WebView'), centerTitle: true),
      body: Platform.isLinux || Platform.isWindows
          ? Column(children: [urlRow, ...bridgeText, const Text('Desktop WebView opened in separate window')])
          : Column(children: [urlRow, ...bridgeText, Expanded(child: WebViewWidget(controller: _controller))]),
    );
  }
}
