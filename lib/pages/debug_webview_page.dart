import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/webview_bridge.dart';

/// A debug-only webview page that accepts a custom URL.
///
/// Used to test the TechPie bridge document-start script against arbitrary
/// local or remote URLs.
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
    _controller = WebViewController();
    unawaited(_initController());
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
        setState(() {
          _bridgeMessage = message.message;
        });
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
      await _controller.loadRequest(Uri.parse(url));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Debug WebView'), centerTitle: true),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      hintText: 'https://…',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.url,
                    onSubmitted: (_) => unawaited(_load()),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _load, child: const Text('Go')),
              ],
            ),
          ),
          if (_bridgeMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Bridge: $_bridgeMessage',
                  style: const TextStyle(fontSize: 12, color: Colors.green),
                ),
              ),
            ),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}
