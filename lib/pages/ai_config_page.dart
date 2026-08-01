import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_ai_provider_anthropic/flutter_ai_provider_anthropic.dart';

import '../models/ai_chat.dart';
import '../services/ai_service.dart';
import '../services/service_provider.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/ios_liquid/ios_native_navigation_bar.dart';

/// Edit the AI assistant's API configuration.
///
/// Fields: base URL, auth token (obscured), model, system prompt, temperature,
/// max tokens. A "测试连接" button sends a trivial non-streaming probe so the
/// user can confirm their key/endpoint before chatting.
class AiConfigPage extends StatefulWidget {
  const AiConfigPage({super.key});

  @override
  State<AiConfigPage> createState() => _AiConfigPageState();
}

class _AiConfigPageState extends State<AiConfigPage> {
  late final TextEditingController _baseUrlCtrl;
  late final TextEditingController _tokenCtrl;
  late final TextEditingController _modelCtrl;
  late final TextEditingController _systemCtrl;
  late final TextEditingController _maxTokensCtrl;
  late final TextEditingController _tempCtrl;

  bool _obscureToken = true;
  bool _testing = false;
  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    // Controllers created empty; populated in didChangeDependencies where
    // ServiceProvider (an InheritedWidget) is safe to access.
    _baseUrlCtrl = TextEditingController();
    _tokenCtrl = TextEditingController();
    _modelCtrl = TextEditingController();
    _systemCtrl = TextEditingController();
    _maxTokensCtrl = TextEditingController();
    _tempCtrl = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) return;
    _seeded = true;
    final config = ServiceProvider.of(context).aiService.config;
    _baseUrlCtrl.text = config.baseUrl;
    _tokenCtrl.text = config.authToken;
    _modelCtrl.text = config.model;
    _systemCtrl.text = config.systemPrompt;
    _maxTokensCtrl.text = config.maxTokens.toString();
    _tempCtrl.text = config.temperature?.toString() ?? '';
  }

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    _tokenCtrl.dispose();
    _modelCtrl.dispose();
    _systemCtrl.dispose();
    _maxTokensCtrl.dispose();
    _tempCtrl.dispose();
    super.dispose();
  }

  AiConfig _buildConfig() {
    final maxTokens = int.tryParse(_maxTokensCtrl.text.trim()) ?? 2048;
    final temp = double.tryParse(_tempCtrl.text.trim());
    return AiConfig(
      baseUrl: _baseUrlCtrl.text.trim().isEmpty
          ? AiConfig.defaultBaseUrl
          : _baseUrlCtrl.text.trim(),
      authToken: _tokenCtrl.text.trim(),
      model: _modelCtrl.text.trim().isEmpty
          ? AiConfig.defaultModel
          : _modelCtrl.text.trim(),
      systemPrompt: _systemCtrl.text,
      temperature: temp,
      maxTokens: maxTokens,
    );
  }

  Future<void> _save() async {
    final aiService = ServiceProvider.of(context).aiService;
    await aiService.saveConfig(_buildConfig());
    if (mounted) {
      showAdaptiveFeedback(message: '已保存', style: AdaptiveFeedbackStyle.success);
    }
  }

  Future<void> _testConnection() async {
    if (_testing) return;
    setState(() => _testing = true);
    final config = _buildConfig();
    AnthropicProvider? provider;
    StreamSubscription<AiStreamEvent>? sub;
    try {
      if (!config.hasAuthToken) {
        showAdaptiveFeedback(
          message: '请先填写 API 令牌',
          style: AdaptiveFeedbackStyle.error,
        );
        return;
      }
      // Build a one-off provider + a trivial "ping" turn and listen for the
      // first text delta — that confirms auth + endpoint end-to-end.
      provider = AnthropicProvider(
        apiKey: config.authToken,
        baseUrl: Uri.parse(normalizeAiBaseUrl(config.baseUrl)),
        defaultModel: config.model,
        defaultMaxTokens: config.maxTokens,
        timeout: const Duration(seconds: 30),
      );
      final systemMsg = config.systemPrompt.trim().isEmpty
          ? null
          : AiMessage(
              id: 'probe-system',
              role: AiRole.system,
              parts: [TextPart(config.systemPrompt)],
            );
      final conv = AiConversation(
        id: 'probe',
        messages: [
          if (systemMsg != null) systemMsg,
          AiMessage.text(
            id: 'probe-user',
            role: AiRole.user,
            text: 'ping',
          ),
        ],
      );
      final got = Completer<void>();
      final buffer = StringBuffer();
      sub = provider.send(conv, options: _probeOptions(config)).listen(
        (event) {
          if (event is TextDelta) {
            buffer.write(event.delta);
            if (buffer.length > 8 && !got.isCompleted) got.complete();
          } else if (event is StreamErrorEvent) {
            if (!got.isCompleted) got.completeError(event.error);
          }
        },
        onError: (Object e) {
          if (!got.isCompleted) got.completeError(e);
        },
      );
      await got.future.timeout(const Duration(seconds: 30));
      await sub.cancel();
      if (mounted) {
        showAdaptiveFeedback(
          message: '连接成功，模型已回复',
          style: AdaptiveFeedbackStyle.success,
        );
      }
    } on LlmException catch (e) {
      if (mounted) {
        showAdaptiveFeedback(
          message: '请求失败（${e.statusCode}）：${e.body.isEmpty ? e.toString() : e.body}',
          style: AdaptiveFeedbackStyle.error,
          duration: const Duration(seconds: 5),
        );
      }
    } on TimeoutException {
      if (mounted) {
        showAdaptiveFeedback(
          message: '请求超时，请稍后重试',
          style: AdaptiveFeedbackStyle.error,
        );
      }
    } catch (e) {
      if (mounted) {
        showAdaptiveFeedback(
          message: '连接失败：$e',
          style: AdaptiveFeedbackStyle.error,
          duration: const Duration(seconds: 5),
        );
      }
    } finally {
      await sub?.cancel();
      provider?.close();
      if (mounted) setState(() => _testing = false);
    }
  }

  AiRequestOptions _probeOptions(AiConfig config) => AiRequestOptions(
        model: config.model,
        temperature: config.temperature,
        maxOutputTokens: config.maxTokens,
      );

  Future<void> _clearAll(AiService aiService) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空所有会话？'),
        content: const Text('此操作不可撤销，将删除全部本地对话记录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await aiService.clearAllConversations();
      if (mounted) {
        showAdaptiveFeedback(message: '已清空', style: AdaptiveFeedbackStyle.success);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final useIosChrome = isIos();
    final useLegacyIosChrome = usesLegacyIosChrome();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      extendBodyBehindAppBar: !useIosChrome && !useLegacyIosChrome,
      appBar: useIosChrome
          ? IosNativeNavigationBar(
              title: 'AI 设置',
              leadingItems: const [
                IosNativeNavigationBarItem(
                  id: 'back',
                  title: 'Chat',
                  sfSymbol: 'chevron.left',
                  accessibilityLabel: '返回对话',
                  placementGroup: 'leading-main',
                ),
              ],
              trailingItems: const [
                IosNativeNavigationBarItem(
                  id: 'save',
                  title: '保存',
                  placementGroup: 'trailing-main',
                ),
              ],
              onItemPressed: (id) {
                switch (id) {
                  case 'back':
                    unawaited(Navigator.maybePop(context));
                  case 'save':
                    unawaited(_save());
                }
              },
            )
          : BlurredAppBar(
              title: const Text('AI 设置'),
              actions: [
                TextButton(
                  onPressed: _save,
                  child: const Text('保存'),
                ),
              ],
            ),
      body: ListView(
        padding: EdgeInsets.only(
          top: useIosChrome || useLegacyIosChrome
              ? 8
              : adaptiveTopBarHeight() + MediaQuery.viewPaddingOf(context).top + 8,
          bottom: 32,
        ),
        children: [
          _section(theme, '接口', [
            _field(
              theme: theme,
              controller: _baseUrlCtrl,
              label: 'Base URL',
              hint: 'https://api.deepseek.com/anthropic',
              keyboardType: TextInputType.url,
            ),
            _tokenField(theme, colorScheme),
            _field(
              theme: theme,
              controller: _modelCtrl,
              label: '模型',
              hint: 'deepseek-v4-flash',
            ),
          ]),
          _section(theme, '生成', [
            _field(
              theme: theme,
              controller: _tempCtrl,
              label: '温度 (temperature, 留空使用默认)',
              hint: '0.7',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            _field(
              theme: theme,
              controller: _maxTokensCtrl,
              label: '最大输出 tokens',
              hint: '2048',
              keyboardType: TextInputType.number,
            ),
          ]),
          _section(theme, '系统提示词', [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _systemCtrl,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _testing ? null : _testConnection,
                    icon: _testing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.network_check),
                    label: const Text('测试连接'),
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined, color: Colors.red),
            title: const Text('清空所有会话'),
            subtitle: const Text('删除本地全部对话记录'),
            onTap: () =>
                unawaited(_clearAll(ServiceProvider.of(context).aiService)),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '支持任何 Anthropic 兼容端点。令牌仅保存在设备安全存储中。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(ThemeData theme, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        ...children,
      ],
    );
  }

  Widget _field({
    required ThemeData theme,
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _tokenField(ThemeData theme, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: _tokenCtrl,
        obscureText: _obscureToken,
        keyboardType: TextInputType.visiblePassword,
        decoration: InputDecoration(
          labelText: 'API 令牌 (auth token)',
          hintText: 'sk-…',
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            icon: Icon(
              _obscureToken ? Icons.visibility_off : Icons.visibility,
            ),
            onPressed: () => setState(() => _obscureToken = !_obscureToken),
          ),
        ),
      ),
    );
  }
}
