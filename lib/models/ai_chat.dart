import 'package:flutter/material.dart';
import 'package:flutter_ai_core/flutter_ai_core.dart';

// Re-export the library's chat-domain types so the rest of TechPie keeps a
// single import (`ai_chat.dart`) for everything AI — the parts-based
// AiMessage/AiRole/... come from flutter_ai_core, while TechPie-specific
// AiConfig / AiPromptTemplate / AiThread / gallery stay below.
export 'package:flutter_ai_core/flutter_ai_core.dart'
    show
        AiMessage,
        AiConversation,
        AiRole,
        AiMessageStatus,
        AiPart,
        TextPart;

/// A persisted conversation thread.
///
/// The library's [AiConversation] only carries `{id, messages}` — it has no
/// title or timestamp. TechPie's history page needs both, so this wrapper adds
/// them and bundles the library conversation as the message payload. It is the
/// unit persisted by [StorageService] and exchanged with [AiService].
class AiThread {
  final String id;
  final String title;
  final List<AiMessage> messages;
  final DateTime updatedAt;

  const AiThread({
    required this.id,
    required this.title,
    required this.messages,
    required this.updatedAt,
  });

  /// The underlying library conversation (messages only, no metadata).
  AiConversation get conversation =>
      AiConversation(id: id, messages: messages);

  AiThread copyWith({
    String? title,
    List<AiMessage>? messages,
    DateTime? updatedAt,
  }) {
    return AiThread(
      id: id,
      title: title ?? this.title,
      messages: messages ?? this.messages,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'messages': [for (final m in messages) m.toJson()],
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory AiThread.fromJson(Map<String, dynamic> json) {
    final rawMessages = (json['messages'] as List<dynamic>? ?? const [])
        .map((e) => AiMessage.fromJson((e as Map).cast<String, dynamic>()))
        // Drop only messages with no content at all (e.g. an aborted
        // streaming placeholder with a single empty text part). Filtering on
        // `text` alone would drop AiRole.tool messages — tool results have no
        // text part — leaving every historical tool_use unanswered, which
        // providers reject on the next request.
        .where(
          (m) =>
              m.role == AiRole.system ||
              m.parts.any((p) => p is! TextPart || p.text.isNotEmpty),
        )
        .toList();
    return AiThread(
      id: json['id'] as String,
      title: json['title'] as String? ?? '新对话',
      messages: rawMessages,
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}


/// API configuration for the Anthropic-format endpoint.
///
/// Defaults are seeded for DeepSeek's Anthropic-compatible endpoint so the
/// assistant works out of the box. The user can override base URL / model /
/// key in the config page.
///
/// Note: [baseUrl] should point at the API *root* **including** the `/v1`
/// segment — the underlying `AnthropicProvider` appends `/messages`. See
/// [normalizeAiBaseUrl], which massages whatever the user typed into that form.
class AiConfig {
  /// `ANTHROPIC_BASE_URL` — the endpoint root, e.g.
  /// `https://api.deepseek.com/anthropic/v1`. `AnthropicProvider` appends
  /// `/messages`, so this MUST include the version segment.
  final String baseUrl;

  /// `ANTHROPIC_AUTH_TOKEN` — sent as `x-api-key` by `AnthropicProvider`.
  final String authToken;

  /// `ANTHROPIC_MODEL` — e.g. `deepseek-v4-flash`.
  final String model;

  /// Optional system prompt prepended to every request (injected as a leading
  /// `AiRole.system` message, which the provider folds into the top-level
  /// `system` field).
  final String systemPrompt;

  /// Sampling temperature, 0.0–2.0. Null = server default.
  final double? temperature;

  /// Max output tokens per turn.
  final int maxTokens;

  const AiConfig({
    required this.baseUrl,
    required this.authToken,
    required this.model,
    this.systemPrompt = _defaultSystemPrompt,
    this.temperature,
    this.maxTokens = 2048,
  });

  /// Default endpoint: DeepSeek's Anthropic-compatible API. The `/v1` segment
  /// is included because `AnthropicProvider` appends `/messages` itself.
  static const defaultBaseUrl = 'https://api.deepseek.com/anthropic/v1';
  static const defaultModel = 'deepseek-v4-flash';
  static const _defaultSystemPrompt =
      '你是 TechPie AI 助手，为上海科技大学师生提供帮助。请用中文简洁、准确地回答问题。\n\n'
      '你可以调用以下工具查询校园数据（数据来自上海科技大学校园系统）：\n'
      '- get_current_time：当前时间、星期几、第几教学周\n'
      '- get_semesters：可用学期列表及当前选中学期\n'
      '- get_week_schedule：指定学期指定周的课程表（可按学期/周过滤，默认当前）\n'
      '- get_assignments：作业与考试截止时间列表（可按平台/类型过滤）\n\n'
      '当用户询问时间、课程表、作业、考试、截止日期等信息时，请主动调用相应工具获取真实数据，'
      '不要凭空编造。工具返回的 error 字段说明查询失败（如未绑定 eGate），应如实告知用户并引导其在设置中绑定校园账号。';

  factory AiConfig.defaults() => const AiConfig(
        baseUrl: defaultBaseUrl,
        authToken: '',
        model: defaultModel,
      );

  bool get hasAuthToken => authToken.isNotEmpty;

  AiConfig copyWith({
    String? baseUrl,
    String? authToken,
    String? model,
    String? systemPrompt,
    double? temperature,
    int? maxTokens,
  }) {
    return AiConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      authToken: authToken ?? this.authToken,
      model: model ?? this.model,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
    );
  }

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'authToken': authToken,
        'model': model,
        'systemPrompt': systemPrompt,
        'temperature': temperature,
        'maxTokens': maxTokens,
      };

  factory AiConfig.fromJson(Map<String, dynamic> json) {
    return AiConfig(
      baseUrl: normalizeAiBaseUrl(json['baseUrl'] as String? ?? defaultBaseUrl),
      authToken: json['authToken'] as String? ?? '',
      model: json['model'] as String? ?? defaultModel,
      systemPrompt: json['systemPrompt'] as String? ?? _defaultSystemPrompt,
      temperature: (json['temperature'] as num?)?.toDouble(),
      maxTokens: json['maxTokens'] as int? ?? 2048,
    );
  }
}

/// Normalizes a user-entered base URL into the form `AnthropicProvider`
/// expects: a root ending in `/v1` (it appends `/messages` itself).
///
/// Tolerates the legacy default (no `/v1`), a fully-qualified
/// `/v1/messages` URL, and trailing slashes — so existing saved configs and
/// hand-typed endpoints keep working after the switch to the library provider.
String normalizeAiBaseUrl(String raw) {
  var url = raw.trim();
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  if (url.isEmpty) return AiConfig.defaultBaseUrl;
  if (url.endsWith('/v1/messages')) {
    return url.substring(0, url.length - '/messages'.length);
  }
  if (url.endsWith('/messages')) {
    return url.substring(0, url.length - '/messages'.length);
  }
  if (url.endsWith('/v1')) {
    return url;
  }
  return '$url/v1';
}

/// A reusable prompt template shown in the gallery. Tapping one starts a new
/// conversation with the template text pre-filled (and optionally a custom
/// system prompt scoped to that category).
class AiPromptTemplate {
  final String id;
  final String title;
  final String subtitle;
  final String prompt;
  final IconData icon;

  const AiPromptTemplate({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.prompt,
    required this.icon,
  });
}

/// Built-in gallery of prompt templates. Hard-coded (not user-editable) to
/// keep the feature simple.
const List<AiPromptTemplate> aiPromptGallery = [
  AiPromptTemplate(
    id: 'translate-en-zh',
    title: '翻译 英文 → 中文',
    subtitle: '把一段英文翻译成通顺的中文',
    prompt: '请把下面这段英文翻译成自然流畅的中文：\n\n',
    icon: Icons.translate,
  ),
  AiPromptTemplate(
    id: 'translate-zh-en',
    title: '翻译 中文 → 英文',
    subtitle: '把一段中文翻译成地道的英文',
    prompt: 'Please translate the following Chinese text into natural English:\n\n',
    icon: Icons.translate_outlined,
  ),
  AiPromptTemplate(
    id: 'summarize',
    title: '总结摘要',
    subtitle: '提取一段文字的要点',
    prompt: '请用中文为以下内容生成一份要点摘要，使用无序列表：\n\n',
    icon: Icons.summarize,
  ),
  AiPromptTemplate(
    id: 'polish',
    title: '润色改写',
    subtitle: '让文字更通顺、更专业',
    prompt: '请润色下面这段文字，使其更通顺、专业，并保留原意：\n\n',
    icon: Icons.auto_fix_high,
  ),
  AiPromptTemplate(
    id: 'explain-code',
    title: '解释代码',
    subtitle: '逐行讲解一段代码',
    prompt: '请用中文逐行解释下面这段代码的作用，并指出潜在问题：\n\n```\n\n```',
    icon: Icons.code,
  ),
  AiPromptTemplate(
    id: 'study-plan',
    title: '制定学习计划',
    subtitle: '为某个主题安排学习路径',
    prompt: '我想学习',
    icon: Icons.school,
  ),
  AiPromptTemplate(
    id: 'email-draft',
    title: '撰写邮件',
    subtitle: '起草一封正式邮件',
    prompt: '请帮我起草一封邮件。背景：\n收件人：\n主要目的：\n语气：正式\n\n',
    icon: Icons.mail,
  ),
  AiPromptTemplate(
    id: 'brainstorm',
    title: '头脑风暴',
    subtitle: '为一个问题发散想法',
    prompt: '请围绕以下主题，给我 10 个有创意的点子，每个一句话：\n\n',
    icon: Icons.lightbulb,
  ),
];
