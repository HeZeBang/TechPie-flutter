import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../pages/campus_session_handle.dart';
import '../../../services/campus_web_session.dart';
import '../../../utils/platform.dart';
import '../../../widgets/adaptive_page_navigation.dart';
import '../application/genai_session_service.dart';
import '../domain/genai_failure.dart';
import '../domain/genai_session.dart';
import '../platform/genai_login_policy.dart';

class GenAiLoginPage extends StatefulWidget {
  const GenAiLoginPage({
    super.key,
    required this.sessions,
    this.campusWebSession,
    this.campusSession,
    this.openPortal,
    this.ephemeral = false,
  });

  final GenAiSessionService sessions;
  final CampusWebSession? campusWebSession;
  final CampusSessionHandle? campusSession;
  final Future<bool> Function(Uri)? openPortal;
  final bool ephemeral;

  @override
  State<GenAiLoginPage> createState() => _GenAiLoginPageState();
}

class _GenAiLoginPageState extends State<GenAiLoginPage> {
  final _token = TextEditingController();
  late final int _revision;
  bool _finished = false;
  String? _error;

  bool get _authorized =>
      widget.sessions.revision == _revision && widget.sessions.owner != null;
  bool get _supportsEmbedded =>
      widget.openPortal == null &&
      !kIsWeb &&
      (isAndroid() ||
          isIos() ||
          isOhos() ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  void initState() {
    super.initState();
    _revision = widget.sessions.revision;
    widget.sessions.addListener(_ownerChanged);
  }

  void _ownerChanged() {
    if (!_authorized &&
        mounted &&
        (ModalRoute.of(context)?.isCurrent ?? false)) {
      _finish(null);
    }
  }

  void _finish(GenAiCredential? credential) {
    if (_finished || !mounted) return;
    _finished = true;
    _token.clear();
    Navigator.of(context).pop(credential);
  }

  Future<void> _openLogin() async {
    if (!_authorized) {
      _finish(null);
      return;
    }
    if (_supportsEmbedded && widget.openPortal == null) {
      final credential = await pushAdaptivePage<GenAiCredential>(
        context,
        builder: (_) => GenAiBrowserLoginPage(
          sessions: widget.sessions,
          campusWebSession: widget.campusWebSession,
          campusSession: widget.campusSession,
        ),
      );
      if (!mounted) return;
      if (!_authorized) {
        _finish(null);
        return;
      }
      if (credential != null) _finish(credential);
      return;
    }
    try {
      final opened =
          await (widget.openPortal?.call(GenAiLoginPolicy.loginUri) ??
              launchUrl(
                GenAiLoginPolicy.loginUri,
                mode: LaunchMode.externalApplication,
              ));
      if (!opened && mounted) setState(() => _error = '无法打开浏览器，请重试。');
    } catch (_) {
      if (mounted) setState(() => _error = '无法打开浏览器，请重试。');
    }
  }

  void _import() {
    if (!_authorized) {
      _finish(null);
      return;
    }
    try {
      _finish(GenAiLoginPolicy.importCredential(_token.text));
    } on GenAiFailure {
      setState(() => _error = '请输入有效的 GenAI 访问令牌，或学校平台的登录结果链接。');
    }
  }

  @override
  void dispose() {
    widget.sessions.removeListener(_ownerChanged);
    _token.clear();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('连接校园 GenAI')),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.school_outlined, size: 48),
                  const SizedBox(height: 24),
                  Text(
                    '使用学校账号登录',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '请使用校园账号 ${widget.sessions.owner?.studentId ?? ''} 登录。'
                    '${_supportsEmbedded && widget.campusSession != null ? '将优先复用 TechPie 已有的 IDS 登录状态。' : ''}'
                    'TechPie 会验证 GenAI 身份。'
                    '${widget.ephemeral ? '本次预览的令牌仅保存在内存中。' : '令牌将保存在本机安全存储中。'}',
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => unawaited(_openLogin()),
                    icon: const Icon(Icons.open_in_new),
                    label: Text(
                      _supportsEmbedded && widget.campusSession != null
                          ? '使用现有 IDS 会话继续'
                          : _supportsEmbedded
                              ? '打开学校登录页'
                              : '在浏览器中登录',
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!_supportsEmbedded)
                    const Text(
                      '网页登录完成后，返回这里导入平台返回的访问令牌或登录结果链接。浏览器登录状态不会自动共享到 TechPie。',
                    ),
                  const SizedBox(height: 20),
                  ExpansionTile(
                    title: const Text('导入已有访问令牌'),
                    initiallyExpanded: !_supportsEmbedded,
                    tilePadding: EdgeInsets.zero,
                    children: [
                      TextField(
                        key: const ValueKey('genai-token'),
                        controller: _token,
                        obscureText: true,
                        enableSuggestions: false,
                        autocorrect: false,
                        enableIMEPersonalizedLearning: false,
                        smartDashesType: SmartDashesType.disabled,
                        smartQuotesType: SmartQuotesType.disabled,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(10000),
                        ],
                        decoration: const InputDecoration(
                          labelText: '访问令牌或登录结果链接',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _import(),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          onPressed: _import,
                          child: const Text('验证并连接'),
                        ),
                      ),
                    ],
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
}

/// Only created on platforms with a native WebView implementation.
class GenAiBrowserLoginPage extends StatefulWidget {
  const GenAiBrowserLoginPage({
    super.key,
    required this.sessions,
    this.campusWebSession,
    this.campusSession,
  });
  final GenAiSessionService sessions;
  final CampusWebSession? campusWebSession;
  final CampusSessionHandle? campusSession;
  @override
  State<GenAiBrowserLoginPage> createState() => _GenAiBrowserLoginPageState();
}

class _GenAiBrowserLoginPageState extends State<GenAiBrowserLoginPage> {
  WebViewController? _controller;
  late final int _revision;
  int _progress = 0;
  bool _finished = false;
  bool _failed = false;
  bool get _authorized =>
      widget.sessions.revision == _revision && widget.sessions.owner != null;

  @override
  void initState() {
    super.initState();
    _revision = widget.sessions.revision;
    widget.sessions.addListener(_ownerChanged);
    unawaited(_configure());
  }

  void _ownerChanged() {
    if (!_authorized) _finish(null);
  }

  void _finish(GenAiCredential? credential) {
    if (_finished || !mounted) return;
    _finished = true;
    Navigator.of(context).pop(credential);
  }

  bool _callback(String url) {
    if (_finished || !_authorized) return false;
    final uri = Uri.tryParse(url);
    final credential = uri == null ? null : GenAiLoginPolicy.callback(uri);
    if (credential == null) return false;
    _finish(credential);
    return true;
  }

  Future<void> _configure() async {
    try {
      final controller = WebViewController();
      _controller = controller;
      final session = widget.campusSession;
      final browserSession =
          session?.tpAuth.campusWebSession ?? widget.campusWebSession;
      if (session != null) {
        await session.prepare();
      } else {
        await browserSession?.prepare();
      }
      await browserSession?.clearLocalStorageIfDue(controller);
      if (!mounted || !_authorized || _finished) return;
      if (session != null) {
        final cookies = WebViewCookieManager();
        for (final cookie in session.cookies) {
          if (!mounted || !_authorized || _finished) return;
          await cookies.setCookie(cookie);
        }
      }
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (!_authorized || _finished) return NavigationDecision.prevent;
            if (request.isMainFrame && _callback(request.url)) {
              return NavigationDecision.prevent;
            }
            final uri = Uri.tryParse(request.url);
            return uri != null && GenAiLoginPolicy.allowsNavigation(uri)
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
          onUrlChange: (change) {
            if (change.url != null) _callback(change.url!);
          },
          onProgress: (value) {
            if (mounted) setState(() => _progress = value);
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && mounted) {
              setState(() => _failed = true);
            }
          },
        ),
      );
      if (!mounted || !_authorized || _finished) return;
      setState(() {});
      await controller.loadRequest(GenAiLoginPolicy.loginUri);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    widget.sessions.removeListener(_ownerChanged);
    _finished = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('学校统一身份认证')),
        body: _failed
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('无法打开内置登录。请返回后使用浏览器登录，并导入访问令牌。'),
                ),
              )
            : Column(
                children: [
                  if (_progress < 100)
                    LinearProgressIndicator(
                      value: _progress == 0 ? null : _progress / 100,
                    ),
                  if (_controller != null)
                    Expanded(child: WebViewWidget(controller: _controller!)),
                ],
              ),
      );
}
