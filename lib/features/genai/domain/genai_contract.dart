import 'genai_context_usage.dart';
import 'genai_failure.dart';
import 'genai_remote_record.dart';

enum GenAiRole { user, assistant, system }

final class GenAiMessage {
  const GenAiMessage({required this.role, required this.content, this.imageUrls = const []});

  final GenAiRole role;
  final String content;

  /// Optional message attachments supported by the school's web client.
  /// Agent image selection also sets the primary request image, since providers
  /// may ignore historical attachments.
  final List<String> imageUrls;

  Map<String, Object?> toJson() => {
        'role': role.name,
        'content': content,
        if (imageUrls.isNotEmpty) 'imageUrl': imageUrls.first,
        if (imageUrls.isNotEmpty) 'imageUrls': imageUrls,
      };
}

/// Source-derived text-chat contract. History excludes the current prompt.
final class GenAiChatRequest {
  GenAiChatRequest({
    required this.chatGroupId,
    required this.prompt,
    required this.aiType,
    required this.rootAiType,
    List<GenAiMessage> history = const [],
    this.thinking = false,
    List<String> fileIds = const [],
    this.contextCompacted = false,
    this.contextGoal,
    this.stepContext,
    this.requestGuide,
    Map<String, String> documentContents = const {},
    this.imageUrl,
    List<String> imageUrls = const [],
    this.maxTokens,
    this.record = const {},
  })  : history = List.unmodifiable(history),
        fileIds = List.unmodifiable(fileIds),
        documentContents = Map.unmodifiable(documentContents),
        imageUrls = List.unmodifiable(imageUrls) {
    if ([chatGroupId, prompt, aiType, rootAiType].any((s) => s.trim().isEmpty) ||
        (maxTokens != null && maxTokens! <= 0)) {
      throw ArgumentError('Invalid GenAI chat request');
    }
  }

  /// Host-authored metadata persisted together with this exchange.
  final Map<String, Object?> record;
  String get storedPrompt => record.isEmpty
      ? prompt
      : encodeGenAiRemoteRecord({...record, 'kind': 'exchange', 'input': prompt});

  final String chatGroupId;
  final String prompt;
  final String aiType;
  final String rootAiType;
  final List<GenAiMessage> history;
  final bool thinking;
  final List<String> fileIds;

  /// Local budget metadata; never serialized into the upstream payload.
  final Map<String, String> documentContents;
  final String? contextGoal;

  /// Reconstructible per-step data, sent after history but never archived or summarized.
  final String? stepContext;
  GenAiMessage? get stepMessage =>
      stepContext == null ? null : GenAiMessage(role: GenAiRole.user, content: stepContext!);

  /// Host instructions immediately before chatInfo, outside durable history.
  final String? requestGuide;
  GenAiMessage? get guideMessage =>
      requestGuide == null ? null : GenAiMessage(role: GenAiRole.system, content: requestGuide!);
  final bool contextCompacted;
  final String? imageUrl;
  final List<String> imageUrls;
  final int? maxTokens;

  GenAiChatRequest withRecord(Map<String, Object?> value) => GenAiChatRequest(
        chatGroupId: chatGroupId,
        prompt: prompt,
        aiType: aiType,
        rootAiType: rootAiType,
        history: history,
        thinking: thinking,
        fileIds: fileIds,
        documentContents: documentContents,
        imageUrl: imageUrl,
        imageUrls: imageUrls,
        maxTokens: maxTokens,
        contextGoal: contextGoal,
        stepContext: stepContext,
        requestGuide: requestGuide,
        contextCompacted: contextCompacted,
        record: value,
      );

  Map<String, Object?> toJson() => {
        'chatInfo': storedPrompt,
        'messages': [
          ...history.map((m) => m.toJson()),
          if (stepMessage case final message?) message.toJson(),
          if (guideMessage case final message?) message.toJson(),
        ],
        'chatGroupId': chatGroupId,
        'aiType': aiType,
        'rootAiType': rootAiType,
        'type': '3',
        'stream': true,
        'thinking': thinking,
        'netGo': false,
        if (fileIds.isNotEmpty) 'fileIds': fileIds,
        if (imageUrl != null && imageUrl!.isNotEmpty) 'imageUrl': imageUrl,
        if (imageUrls.isNotEmpty) 'imageUrls': imageUrls,
        if (maxTokens != null) 'maxToken': maxTokens,
      };
}

final class GenAiProfile {
  const GenAiProfile({required this.id, required this.username});

  final String id;
  final String username;
}

final class GenAiModel {
  const GenAiModel({
    required this.name,
    required this.aiType,
    required this.rootAiType,
    this.payType,
    this.status,
    this.enableDeepThink = false,
  });

  final String name;
  final String aiType;
  final String rootAiType;
  final String? payType;
  final int? status;
  bool get isImage => status == 2;
  final bool enableDeepThink;
  bool get supportsThinking => !isImage && enableDeepThink;
}

enum GenAiFinishReason { stop, length, contentFilter, done, other }

sealed class GenAiChatEvent {
  const GenAiChatEvent();
}

final class GenAiContextUsageChanged extends GenAiChatEvent {
  const GenAiContextUsageChanged(this.usage);
  final GenAiContextUsage usage;
}

final class GenAiContextCompacted extends GenAiChatEvent {
  const GenAiContextCompacted();
}

final class GenAiTextDelta extends GenAiChatEvent {
  const GenAiTextDelta(this.text);
  final String text;
}

final class GenAiReasoningDelta extends GenAiChatEvent {
  const GenAiReasoningDelta(this.text);
  final String text;
}

final class GenAiChatFinished extends GenAiChatEvent {
  const GenAiChatFinished(this.reason);
  final GenAiFinishReason reason;
}

Map<String, dynamic> genAiObject(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const GenAiFailure(GenAiFailureKind.protocol);
  }
  return value;
}

String genAiRequiredString(Map<String, dynamic> value, String key) {
  final field = value[key];
  if (field is! String || field.trim().isEmpty) {
    throw const GenAiFailure(GenAiFailureKind.protocol);
  }
  return field;
}

/// The gateway sometimes returns business failures with HTTP 200.
Object? genAiEnvelope(Object? value) {
  final json = genAiObject(value);
  final code = json['code'];
  final rawMessage = json['message'] ?? json['errMsg'];
  final message = rawMessage is String ? rawMessage : '';
  if (code == 401 ||
      (code == 500 &&
          (message.contains('Token失效') || message.contains('重新登录') || message.contains('登录已过期')))) {
    throw const GenAiFailure(GenAiFailureKind.authenticationRequired);
  }
  if (json['success'] == false || (code is int && code != 0 && code != 200)) {
    throw const GenAiFailure(GenAiFailureKind.rejected);
  }
  if (json['success'] != true || (code != 0 && code != 200)) {
    throw const GenAiFailure(GenAiFailureKind.protocol);
  }
  return json['result'];
}
