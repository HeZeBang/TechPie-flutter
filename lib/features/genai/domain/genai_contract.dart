import 'genai_failure.dart';

enum GenAiRole { user, assistant, system }

final class GenAiMessage {
  const GenAiMessage({required this.role, required this.content});

  final GenAiRole role;
  final String content;

  Map<String, Object?> toJson() => {'role': role.name, 'content': content};
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
    this.netGo = false,
    List<String> fileIds = const [],
    this.imageUrl,
    List<String> imageUrls = const [],
    this.maxTokens,
  })  : history = List.unmodifiable(history),
        fileIds = List.unmodifiable(fileIds),
        imageUrls = List.unmodifiable(imageUrls) {
    if ([chatGroupId, prompt, aiType, rootAiType]
            .any((s) => s.trim().isEmpty) ||
        (maxTokens != null && maxTokens! <= 0)) {
      throw ArgumentError('Invalid GenAI chat request');
    }
  }

  final String chatGroupId;
  final String prompt;
  final String aiType;
  final String rootAiType;
  final List<GenAiMessage> history;
  final bool thinking;
  final bool netGo;
  final List<String> fileIds;
  final String? imageUrl;
  final List<String> imageUrls;
  final int? maxTokens;

  Map<String, Object?> toJson() => {
        'chatInfo': prompt,
        'messages': history.map((m) => m.toJson()).toList(),
        'chatGroupId': chatGroupId,
        'aiType': aiType,
        'rootAiType': rootAiType,
        'type': '3',
        'stream': true,
        'thinking': thinking,
        'netGo': netGo,
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
  });

  final String name;
  final String aiType;
  final String rootAiType;
  final String? payType;
  final int? status;
  bool get isImage => status == 2;
  bool get supportsThinking {
    if (isImage) return false;
    final lower = aiType.toLowerCase();
    final nameLower = name.toLowerCase();
    return lower.contains('deepseek') ||
        lower.contains('glm') ||
        lower.contains('kimi') ||
        lower.contains('gpt-6') ||
        lower.contains('demo') ||
        nameLower.contains('deepseek') ||
        nameLower.contains('glm') ||
        nameLower.contains('kimi') ||
        nameLower.contains('gpt-6');
  }
}

enum GenAiFinishReason { stop, length, contentFilter, done, other }

sealed class GenAiChatEvent {
  const GenAiChatEvent();
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
          (message.contains('Token失效') ||
              message.contains('重新登录') ||
              message.contains('登录已过期')))) {
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
