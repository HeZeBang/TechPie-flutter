import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/genai_api_service.dart';
import '../services/service_provider.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_button.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/adaptive_select.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';

class GenaiApiPage extends StatefulWidget {
  const GenaiApiPage({super.key, this.service});
  final GenaiApiService? service;

  @override
  State<GenaiApiPage> createState() => _GenaiApiPageState();
}

class _GenaiApiPageState extends State<GenaiApiPage> {
  GenaiApiService? _service;
  final _apiToken = TextEditingController();
  final _port = TextEditingController(text: '5000');
  String _host = '127.0.0.1';
  bool _ready = false;
  bool _showToken = false;
  bool _ownsService = false;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_service != null) return;
    final provider = widget.service == null ? ServiceProvider.of(context) : null;
    _service = widget.service ?? provider?.genaiApiService;
    if (_service == null) {
      _service = GenaiApiService(provider!.storageService);
      _ownsService = true;
    }
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      await _service!.load();
      if (!mounted) return;
      _apiToken.text = _service!.apiToken;
      _port.text = '${_service!.port}';
      _host = _service!.host;
      setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    if (_ownsService) _service?.dispose();
    _apiToken.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _service!.saveSettings(apiToken: _apiToken.text, port: _port.text, host: _host);
      await _service!.start();
    } on FormatException catch (e) {
      if (mounted) {
        showAdaptiveFeedback(
          context: context,
          message: e.message,
          style: AdaptiveFeedbackStyle.error,
        );
      }
    } catch (_) {
      if (mounted) {
        showAdaptiveFeedback(
          context: context,
          message: '保存失败，请重试',
          style: AdaptiveFeedbackStyle.error,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _service!.saveSettings(apiToken: _apiToken.text, port: _port.text, host: _host);
      if (mounted) showAdaptiveFeedback(context: context, message: '已保存');
    } catch (e) {
      if (mounted) {
        showAdaptiveFeedback(
          context: context,
          message: e is FormatException ? e.message : '保存失败，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showAdaptiveFeedback(context: context, message: '已复制');
  }

  @override
  Widget build(BuildContext context) {
    final service = _service!;
    final useIosChrome = isIos();
    final top = useIosChrome || usesLegacyIosChrome()
        ? 16.0
        : adaptiveTopBarHeight() + MediaQuery.viewPaddingOf(context).top + 16;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final editable = _ready && !service.busy && !service.running && !_saving;
        return Scaffold(
          extendBodyBehindAppBar: !useIosChrome && !usesLegacyIosChrome(),
          appBar: useIosChrome
              ? IosNativeNavigationBar(
                  title: 'GenAI API',
                  leadingItems: const [
                    IosNativeNavigationBarItem(id: 'back', title: '返回', sfSymbol: 'chevron.left'),
                  ],
                  onItemPressed: (_) => Navigator.of(context).maybePop(),
                )
              : const BlurredAppBar(title: Text('GenAI API')),
          body: ListView(
            padding:
                EdgeInsets.fromLTRB(16, top, 16, MediaQuery.viewPaddingOf(context).bottom + 24),
            children: [
              Card.outlined(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                            service.loggedIn ? Icons.check_circle_outline : Icons.person_outline,),
                        title: Text(service.loggedIn ? '已登录 GenAI' : '登录 GenAI'),
                        subtitle: const Text('保存账号密码，每 2 小时自动登录'),
                        trailing: editable
                            ? TextButton(
                                onPressed: () => unawaited(
                                  pushAdaptivePage<void>(
                                    context,
                                    builder: (_) => _GenaiLoginPage(service: service),
                                  ),
                                ),
                                child: Text(service.loggedIn ? '切换账号' : '登录'),
                              )
                            : null,
                      ),
                      if (service.loggedIn && editable)
                        TextButton(
                          onPressed: () async {
                            try {
                              await service.logout();
                            } catch (_) {
                              if (context.mounted) {
                                showAdaptiveFeedback(context: context, message: '退出失败，请重试');
                              }
                            }
                          },
                          child: const Text('退出登录'),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card.outlined(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('本地 API', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _port,
                        enabled: editable,
                        decoration: const InputDecoration(labelText: '端口'),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _apiToken,
                        enabled: editable,
                        obscureText: !_showToken,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: 'API Token',
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: _showToken ? '隐藏' : '显示',
                                onPressed: () => setState(() => _showToken = !_showToken),
                                icon: Icon(
                                  _showToken
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                              ),
                              IconButton(
                                tooltip: '复制 Token',
                                onPressed: _ready ? () => unawaited(_copy(_apiToken.text)) : null,
                                icon: const Icon(Icons.copy_outlined),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('监听范围'),
                      const SizedBox(height: 8),
                      IgnorePointer(
                        ignoring: !editable,
                        child: AdaptiveSelect(
                          value: _host,
                          accessibilityLabel: '监听范围',
                          options: const [
                            AdaptiveSelectOption(value: '127.0.0.1', label: '仅本机'),
                            AdaptiveSelectOption(value: '0.0.0.0', label: '局域网'),
                          ],
                          onChanged: (value) => setState(() => _host = value),
                        ),
                      ),
                      TextButton(
                        onPressed: editable ? () => unawaited(_save()) : null,
                        child: const Text('保存设置'),
                      ),
                      const SizedBox(height: 20),
                      AdaptiveButton(
                        onPressed: !_ready ||
                                service.busy ||
                                _saving ||
                                (!service.running && !service.loggedIn)
                            ? null
                            : () => unawaited(service.running ? service.stop() : _start()),
                        icon: service.running ? Icons.stop_rounded : Icons.play_arrow_rounded,
                        sfSymbol: service.running ? 'stop.fill' : 'play.fill',
                        label: service.running ? '停止服务' : '启动服务',
                        loading: service.busy,
                        role: AdaptiveButtonRole.prominent,
                      ),
                      const SizedBox(height: 12),
                      Text(service.running ? '运行中' : '未启动', textAlign: TextAlign.center),
                      if (service.running) ...[
                        const SizedBox(height: 12),
                        SelectableText(service.endpoint),
                        TextButton(
                          onPressed: () => unawaited(_copy(service.endpoint)),
                          child: const Text('复制地址'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (service.error != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(service.error!),
                ),
              if (!_ready && service.error != null)
                TextButton(onPressed: () => unawaited(_load()), child: const Text('重试')),
            ],
          ),
        );
      },
    );
  }
}

class _GenaiLoginPage extends StatefulWidget {
  const _GenaiLoginPage({required this.service});
  final GenaiApiService service;
  @override
  State<_GenaiLoginPage> createState() => _GenaiLoginPageState();
}

class _GenaiLoginPageState extends State<_GenaiLoginPage> {
  final _account = TextEditingController();
  final _password = TextEditingController();
  @override
  void dispose() {
    _account.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final ok = await widget.service.login(_account.text, _password.text);
    if (!mounted) return;
    if (ok) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.service,
        builder: (context, _) => Scaffold(
          appBar: AppBar(title: const Text('登录 GenAI')),
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              TextField(
                controller: _account,
                enabled: !widget.service.busy,
                decoration: const InputDecoration(labelText: '学号'),
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                enableSuggestions: false,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                enabled: !widget.service.busy,
                decoration: const InputDecoration(labelText: '密码'),
                obscureText: true,
                onSubmitted: (_) {
                  if (!widget.service.busy) unawaited(_login());
                },
              ),
              const SizedBox(height: 24),
              AdaptiveButton(
                onPressed: widget.service.busy ? null : () => unawaited(_login()),
                icon: Icons.login,
                sfSymbol: 'person.crop.circle',
                label: '登录',
                loading: widget.service.busy,
                role: AdaptiveButtonRole.prominent,
              ),
              if (widget.service.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(widget.service.error!),
                ),
            ],
          ),
        ),
      );
}
