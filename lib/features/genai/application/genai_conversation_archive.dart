import 'dart:convert';

import '../domain/genai_agent_contract.dart';
import '../domain/genai_platform_contract.dart';
import 'genai_conversation_turn.dart';

/// Immutable export/view of reconstructed server history. This is not a store.
final class GenAiConversationArchive {
  GenAiConversationArchive({
    required this.id,
    required this.title,
    required this.updatedAt,
    DateTime? lastMessageAt,
    required List<GenAiConversationTurn> turns,
    required this.agentEnabled,
    required this.netSearchEnabled,
    required this.thinkingEnabled,
    required this.modelAiType,
    required this.modelRootAiType,
    required Map<String, Object?> mutations,
    Map<String, Object?> contextMemory = const {},
  }) : _json = genAiAgentJsonMap({
          'version': 1,
          'id': id,
          'title': title,
          'updatedAt': updatedAt.toUtc().toIso8601String(),
          'lastMessageAt': (lastMessageAt ?? updatedAt).toUtc().toIso8601String(),
          'turns': [for (final turn in turns) turn.toArchiveJson()],
          'agentEnabled': agentEnabled,
          'netSearchEnabled': netSearchEnabled,
          'thinkingEnabled': thinkingEnabled,
          'modelAiType': modelAiType,
          'modelRootAiType': modelRootAiType,
          'mutations': mutations,
          'contextMemory': contextMemory,
        });

  GenAiConversationArchive._(this._json)
      : id = _json['id']! as String,
        title = _json['title']! as String,
        updatedAt = DateTime.parse(_json['updatedAt']! as String),
        agentEnabled = _json['agentEnabled']! as bool,
        netSearchEnabled = _json['netSearchEnabled']! as bool,
        thinkingEnabled = _json['thinkingEnabled']! as bool,
        modelAiType = _json['modelAiType'] as String?,
        modelRootAiType = _json['modelRootAiType'] as String?;

  factory GenAiConversationArchive.fromJson(Map<String, Object?> json) {
    if (json['version'] != 1 ||
        json['id'] is! String ||
        (json['id']! as String).isEmpty ||
        json['turns'] is! List) {
      throw const FormatException('Unsupported conversation archive');
    }
    final result = GenAiConversationArchive._(
      genAiAgentJsonMap(
        _migrateArchivedImageUrls({
          ...json,
          'lastMessageAt': json['lastMessageAt'] ?? json['updatedAt'],
        }),
      ),
    );
    // Validate every turn before exposing an archive as authoritative.
    result.restoreTurns();
    result.mutations;
    result.lastMessageAt;
    return result;
  }

  final Map<String, Object?> _json;
  final String id;
  final String title;
  final DateTime updatedAt;
  DateTime get lastMessageAt => DateTime.parse(
        (_json['lastMessageAt'] ?? _json['updatedAt'])! as String,
      );
  final bool agentEnabled;
  final bool netSearchEnabled;
  final bool thinkingEnabled;
  final String? modelAiType;
  final String? modelRootAiType;

  bool get isEmpty => (_json['turns']! as List).isEmpty;

  List<GenAiConversationTurn> restoreTurns() => [
        for (final raw in _json['turns']! as List)
          genAiTurnFromArchive(Map<String, Object?>.from(raw as Map)),
      ];
  Map<String, Object?> get mutations => Map<String, Object?>.from(_json['mutations']! as Map);
  Map<String, Object?> get contextMemory => Map<String, Object?>.from(
        _json['contextMemory'] as Map? ?? const {},
      );
  Map<String, Object?> toJson() => _json;
  String encode() => jsonEncode(_json);
  GenAiConversationSummary get summary => GenAiConversationSummary(
        id: id,
        title: title,
        time: lastMessageAt.toLocal().toIso8601String(),
      );
}

// Earlier development builds persisted proxy URLs in tool receipts. Convert
// only structured image fields from that exact loopback/static route. Prompt,
// answer and other literal text must never be rewritten during restoration.
Map<String, Object?> _migrateArchivedImageUrls(Map<String, Object?> source) {
  final json = Map<String, Object?>.from(jsonDecode(jsonEncode(source)) as Map);
  void receipt(Object? raw) {
    if (raw is! Map || raw['name'] != 'generate_image' || raw['ok'] != true) {
      return;
    }
    final result = raw['result'];
    if (result is! Map || result['status'] != 'generated') return;
    final images = result['images'];
    if (images is List) {
      result['images'] = [
        for (final image in images) _canonicalArchivedImage(image),
      ];
    }
  }

  final turns = json['turns'];
  if (turns is List) {
    for (final turn in turns) {
      if (turn is! Map) continue;
      turn['attachedImageUrl'] = _canonicalArchivedImage(turn['attachedImageUrl']);
      final images = turn['attachedImageUrls'];
      if (images is List) {
        turn['attachedImageUrls'] = [
          for (final image in images) _canonicalArchivedImage(image),
        ];
      }
      final events = turn['agentEvents'];
      if (events is List) {
        for (final event in events) {
          if (event is Map) receipt(event['result']);
        }
      }
      final transcript = turn['agentTranscript'];
      if (transcript is List) {
        for (final entry in transcript) {
          if (entry is Map && entry['kind'] == 'result') {
            receipt(entry['value']);
          }
        }
      }
    }
  }
  final mutations = json['mutations'];
  if (mutations is Map && mutations['effects'] is Map) {
    for (final result in (mutations['effects'] as Map).values) {
      receipt(result);
    }
  }
  return json;
}

Object? _canonicalArchivedImage(Object? value) {
  if (value is! String) return value;
  try {
    final uri = Uri.parse(value);
    if (uri.scheme != 'http' ||
        !const ['127.0.0.1', 'localhost', '::1'].contains(uri.host) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !uri.path.startsWith('/sys/common/static/') ||
        uri.pathSegments.any(
          (part) => part == '.' || part == '..' || part.contains('/') || part.contains('\\'),
        )) {
      return value;
    }
    return genAiImageUri(
      Uri(
        scheme: 'https',
        host: 'genaipic.shanghaitech.edu.cn',
        path: uri.path,
      ).toString(),
    ).toString();
  } catch (_) {
    return value;
  }
}
