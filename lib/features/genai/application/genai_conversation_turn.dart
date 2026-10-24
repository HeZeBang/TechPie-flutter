import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../domain/genai_agent_contract.dart';
import '../domain/genai_agent_protocol.dart';
import '../domain/genai_context_usage.dart';
import '../domain/genai_contract.dart';
import '../domain/genai_failure.dart';
import '../domain/genai_platform_contract.dart';
import 'genai_chat_service.dart';

final class GenAiConversationTurn {
  GenAiConversationTurn(
    this.prompt, {
    this.isAgent = false,
    this.isHistoryGap = false,
  });

  final String prompt;
  final bool isAgent;
  final bool isHistoryGap;
  final agentEvents = <String, GenAiAgentEvent>{};
  final agentActivity = <GenAiAgentEvent>[];

  /// Display data only, never reused as executable model history.
  void recordAgentActivity(GenAiAgentEvent event) {
    if (event.kind == GenAiAgentEventKind.reasoningDelta) {
      if (agentActivity.isNotEmpty &&
          agentActivity.last.kind == GenAiAgentEventKind.reasoningDelta &&
          agentActivity.last.turn == event.turn) {
        final previous = agentActivity.removeLast();
        agentActivity.add(
          GenAiAgentEvent(
            kind: event.kind,
            turn: event.turn,
            text: '${previous.text ?? ''}${event.text ?? ''}',
          ),
        );
      } else {
        agentActivity.add(event);
      }
    } else if (event.call != null) {
      final index = agentActivity.indexWhere(
        (entry) => entry.turn == event.turn && entry.call?.id == event.call!.id,
      );
      if (index < 0) {
        agentActivity.add(event);
      } else {
        agentActivity[index] = event;
      }
    } else if (event.kind == GenAiAgentEventKind.protocolError) {
      agentActivity.add(event);
    }
  }

  /// Source evidence for follow-up requests, including server-only imports.
  /// No preparation, approval or mutation-ledger state is reconstructed.
  List<GenAiAgentHistoryEntry> get evidenceEntries => [
        GenAiAgentHistoryEntry.text(GenAiRole.user, prompt),
        for (final event in agentEvents.values)
          if (event.call != null && event.result != null) ...[
            GenAiAgentHistoryEntry.call(event.call!),
            GenAiAgentHistoryEntry.result(event.result!),
          ],
        if (answer.isNotEmpty) GenAiAgentHistoryEntry.text(GenAiRole.assistant, answer),
      ];

  String agentStatus = '';
  // Legacy archives may contain this redundant wire history. New turns use
  // only the typed transcript below.
  List<GenAiMessage> agentHistory = const [];
  List<GenAiAgentHistoryEntry> agentTranscript = const [];

  /// Older archives stored a cumulative checkpoint on every agent turn.
  /// New turns retain only their own entries, keeping memory and storage linear.
  bool agentTranscriptIsDelta = false;
  bool contextCompacted = false;

  /// Status of the latest request in this turn; never persisted as live progress.
  GenAiContextUsage? contextUsage;
  String answer = '';
  String reasoning = '';
  bool isAgentThinking = false;
  int? thinkingDurationMs;
  DateTime? thinkingStartTime;
  bool isSearching = false;
  List<GenAiWebSearchCitation> citations = const [];
  List<String> attachedFileNames = const [];
  List<String> attachedFileIds = const [];
  Map<String, String> attachedFileContents = const {};
  String? attachedImageUrl;
  List<String> attachedImageUrls = const [];
  Uint8List? attachedImageBytes;
  List<Uint8List> attachedImageBytesList = const [];
  GenAiChatPhase phase = GenAiChatPhase.preparing;
  GenAiFailure? failure;
  GenAiFinishReason? finishReason;
}

/// Versioned local records contain data only. Restored preparation receipts
/// have no executable capability and never recreate a pending approval.
extension GenAiConversationTurnArchive on GenAiConversationTurn {
  Map<String, Object?> toArchiveJson() => {
        'kind': 'conversation_turn',
        'prompt': prompt,
        'isAgent': isAgent,
        'isHistoryGap': isHistoryGap,
        'answer': answer,
        'contextCompacted': contextCompacted,
        'reasoning': reasoning,
        'phase': phase.name,
        'thinkingDurationMs': thinkingDurationMs,
        'agentStatus': agentStatus,
        'agentHistory': [
          for (final message in agentHistory)
            {'role': message.role.name, 'content': message.content},
        ],
        'agentTranscriptIsDelta': agentTranscriptIsDelta,
        'agentTranscript': [
          for (final entry in agentTranscript) entry.toJson(),
        ],
        'agentEvents': [
          for (final event in agentEvents.values) _agentEventToArchive(event),
        ],
        'agentActivity': [
          for (final event in agentActivity) _agentEventToArchive(event),
        ],
        'attachedFileNames': attachedFileNames,
        'attachedFileIds': attachedFileIds,
        'attachedFileContents': attachedFileContents,
        'attachedImageUrl': attachedImageUrl,
        'attachedImageUrls': attachedImageUrls,
        'attachedImageBytes': attachedImageUrls.isNotEmpty ||
                attachedImageBytes == null ||
                attachedImageBytes!.length > 512 * 1024
            ? null
            : base64Encode(attachedImageBytes!),
        'attachedImageBytesList': [
          if (attachedImageUrls.isEmpty)
            for (final bytes in attachedImageBytesList)
              if (bytes.length <= 512 * 1024) base64Encode(bytes),
        ],
        'citations': [
          for (final citation in citations)
            {
              'num': citation.num,
              'title': citation.title,
              'link': citation.link,
              'snippet': citation.snippet,
            },
        ],
        'failure': failure?.kind.name,
        'finishReason': finishReason?.name,
      };
}

GenAiConversationTurn genAiTurnFromArchive(Map<String, Object?> json) {
  if (json['kind'] != 'conversation_turn' ||
      json['prompt'] is! String ||
      json['answer'] is! String ||
      json['isAgent'] is! bool) {
    throw const FormatException('Invalid conversation turn');
  }
  final savedPhase = GenAiChatPhase.values.byName(json['phase']! as String);
  final interrupted =
      savedPhase == GenAiChatPhase.preparing || savedPhase == GenAiChatPhase.streaming;
  final turn = GenAiConversationTurn(
    json['prompt']! as String,
    isAgent: json['isAgent']! as bool,
    isHistoryGap: json['isHistoryGap'] as bool? ?? false,
  )
    ..answer = json['answer']! as String
    ..contextCompacted = json['contextCompacted'] as bool? ?? false
    ..reasoning = json['reasoning']! as String
    ..phase = interrupted ? GenAiChatPhase.cancelled : savedPhase
    ..thinkingDurationMs = json['thinkingDurationMs'] as int?
    ..agentStatus = interrupted ? '任务已中断。已提交的操作可能完成，请先查看工具记录。' : json['agentStatus']! as String
    ..agentHistory = [
      for (final raw in json['agentHistory']! as List)
        GenAiMessage(
          role: _archiveRole((raw as Map)['role'] as String),
          content: raw['content'] as String,
        ),
    ]
    ..agentTranscriptIsDelta = json['agentTranscriptIsDelta'] as bool? ?? false
    ..agentTranscript = [
      for (final raw in json['agentTranscript']! as List)
        GenAiAgentHistoryEntry.fromJson(_archiveMap(raw)),
    ]
    ..attachedFileNames = _archiveStrings(json['attachedFileNames'])
    ..attachedFileIds = _archiveStrings(json['attachedFileIds'])
    ..attachedFileContents = Map<String, String>.from(
      json['attachedFileContents'] as Map? ?? const {},
    )
    ..attachedImageUrl = json['attachedImageUrl'] as String?
    ..attachedImageUrls = _archiveStrings(json['attachedImageUrls'])
    ..attachedImageBytes = json['attachedImageBytes'] == null
        ? null
        : base64Decode(json['attachedImageBytes']! as String)
    ..attachedImageBytesList = [
      for (final encoded in _archiveStrings(json['attachedImageBytesList'])) base64Decode(encoded),
    ]
    ..citations = [
      for (final raw in json['citations']! as List)
        GenAiWebSearchCitation.fromJson(
          Map<String, dynamic>.from(_archiveMap(raw)),
        ),
    ]
    ..failure = json['failure'] == null
        ? null
        : GenAiFailure(
            GenAiFailureKind.values.byName(json['failure']! as String),
          )
    ..finishReason = json['finishReason'] == null
        ? null
        : GenAiFinishReason.values.byName(json['finishReason']! as String);
  for (final raw in json['agentEvents']! as List) {
    final entry = _agentEventFromArchive(_archiveMap(raw));
    if (entry.call == null) continue;
    var key = entry.call!.id;
    var duplicate = 1;
    while (turn.agentEvents.containsKey(key)) {
      key = '${entry.call!.id}:${duplicate++}';
    }
    turn.agentEvents[key] = entry;
  }
  for (final raw in json['agentActivity'] as List? ?? const []) {
    turn.agentActivity.add(_agentEventFromArchive(_archiveMap(raw)));
  }
  return turn;
}

Map<String, Object?> _agentEventToArchive(GenAiAgentEvent event) => {
      'kind': event.kind.name,
      'turn': event.turn,
      'call': event.call?.toJson(),
      'result': event.result,
      'text': event.text,
      'failure': event.failure?.kind.name,
      if (event.prepared case final prepared?)
        'receipt': {'summary': prepared.summary, 'details': prepared.details},
    };

GenAiAgentEvent _agentEventFromArchive(Map<String, Object?> event) {
  final rawCall = event['call'];
  final call = rawCall == null ? null : _archiveMap(rawCall);
  final receipt = event['receipt'] == null ? null : _archiveMap(event['receipt']);
  return GenAiAgentEvent(
    kind: GenAiAgentEventKind.values.byName(event['kind']! as String),
    turn: event['turn']! as int,
    call: call == null
        ? null
        : GenAiAgentToolCall(
            id: call['call_id']! as String,
            name: call['name']! as String,
            arguments: _archiveMap(call['arguments']),
          ),
    result: event['result'] == null ? null : _archiveMap(event['result']),
    text: event['text'] as String?,
    prepared: receipt == null
        ? null
        : GenAiAgentPreparedTool(
            summary: receipt['summary'] as String?,
            details: _archiveMap(receipt['details']),
            execute: () => Future<Object?>.error(
              const GenAiFailure(GenAiFailureKind.cancelled),
            ),
          ),
    failure: event['failure'] == null
        ? null
        : GenAiFailure(
            GenAiFailureKind.values.byName(event['failure']! as String),
          ),
  );
}

Map<String, Object?> _archiveMap(Object? value) => Map<String, Object?>.from(value! as Map);
List<String> _archiveStrings(Object? value) =>
    List<String>.unmodifiable((value! as List).cast<String>());

GenAiRole _archiveRole(String name) {
  final role = GenAiRole.values.byName(name);
  if (role == GenAiRole.system) {
    throw const FormatException('Invalid history role');
  }
  return role;
}
