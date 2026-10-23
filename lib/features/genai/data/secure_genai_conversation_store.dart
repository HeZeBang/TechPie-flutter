import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';

import '../../../utils/secure_storage.dart';
import '../application/genai_conversation_store.dart';
import '../domain/genai_failure.dart';
import '../domain/genai_platform_contract.dart';

/// Local encrypted storage; no conversation, receipt, or image is cloud-synced.
final class SecureGenAiConversationStore implements GenAiConversationStore {
  SecureGenAiConversationStore({FlutterSecureStorage? storage})
      : _storage = storage ?? appSecureStorage;

  final FlutterSecureStorage _storage;
  // Runtimes can briefly overlap during account or app lifecycle changes. A
  // shared queue keeps their read/modify/write index transactions serialized.
  static Future<void> _tail = Future.value();

  String _prefix(String scope) =>
      'techpie.genai.conversations.v1.${sha256.convert(utf8.encode(scope))}';
  String _recordKey(String scope, String id) =>
      '${_prefix(scope)}.${sha256.convert(utf8.encode(id))}';

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _tail.then((_) async {
      try {
        return await operation();
      } catch (_) {
        throw const GenAiFailure(GenAiFailureKind.storage);
      }
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<Map<String, Object?>> _readIndex(String scope) async {
    final raw = await _storage.read(key: '${_prefix(scope)}.index');
    if (raw == null) {
      return {
        'version': 1,
        'records': <String, Object?>{},
        'deleted': <String>[],
        'pendingDeletions': <String>[],
      };
    }
    final json = Map<String, Object?>.from(jsonDecode(raw) as Map);
    if (json['version'] != 1 ||
        json['records'] is! Map ||
        json['deleted'] is! List ||
        (json['pendingDeletions'] != null &&
            json['pendingDeletions'] is! List)) {
      throw const FormatException('Unsupported conversation index');
    }
    json['pendingDeletions'] ??= <String>[];
    return json;
  }

  bool _hidden(Map<String, Object?> index, String id) =>
      (index['deleted']! as List).contains(id) ||
      (index['pendingDeletions']! as List).contains(id);

  Future<void> _saveIndex(String scope, Map<String, Object?> index) =>
      _storage.write(
        key: '${_prefix(scope)}.index',
        value: jsonEncode(index),
      );

  Future<void> _begin(String scope, String id, String operation) =>
      _storage.write(
        key: '${_prefix(scope)}.pending',
        value: jsonEncode({
          'version': 1,
          'scope': scope,
          'id': id,
          'operation': operation,
        }),
      );

  Future<void> _complete(String scope) =>
      _storage.delete(key: '${_prefix(scope)}.pending');

  GenAiConversationArchive _decode(String raw, String scope, String id) {
    final json = Map<String, Object?>.from(jsonDecode(raw) as Map);
    if (json['version'] != 1 || json['scope'] != scope) {
      throw const FormatException('Conversation scope mismatch');
    }
    final record = GenAiConversationArchive.fromJson(
      Map<String, Object?>.from(json['archive']! as Map),
    );
    if (record.id != id) {
      throw const FormatException('Conversation id mismatch');
    }
    return record;
  }

  void _addSummary(
    Map<String, Object?> index,
    GenAiConversationArchive archive,
  ) {
    (index['records']! as Map)[archive.id] = {
      'title': archive.title,
      'time': archive.updatedAt.toLocal().toIso8601String(),
    };
  }

  Future<Map<String, Object?>> _index(String scope) async {
    final index = await _readIndex(scope);
    final raw = await _storage.read(key: '${_prefix(scope)}.pending');
    if (raw == null) return index;
    final pending = Map<String, Object?>.from(jsonDecode(raw) as Map);
    final id = pending['id'];
    final operation = pending['operation'];
    if (pending['version'] != 1 ||
        pending['scope'] != scope ||
        id is! String ||
        id.isEmpty ||
        !const ['write', 'delete', 'beginDeletion', 'rollbackDeletion']
            .contains(operation)) {
      throw const FormatException('Invalid conversation transaction');
    }
    final deleted = index['deleted']! as List;
    final pendingDeletions = index['pendingDeletions']! as List;
    if (operation == 'delete') {
      (index['records']! as Map).remove(id);
      pendingDeletions.remove(id);
      if (!deleted.contains(id)) deleted.add(id);
    } else if (operation == 'beginDeletion') {
      if (!deleted.contains(id) && !pendingDeletions.contains(id)) {
        pendingDeletions.add(id);
      }
    } else if (operation == 'rollbackDeletion') {
      pendingDeletions.remove(id);
    } else if (!_hidden(index, id)) {
      // The record may have committed before a crash or failed index write.
      // If it did not, keep the previous record/index state. Never reconstruct
      // an index from record keys: that would lose durable deletion tombstones.
      final record = await _storage.read(key: _recordKey(scope, id));
      if (record != null) _addSummary(index, _decode(record, scope, id));
    }
    await _saveIndex(scope, index);
    if (operation == 'delete') {
      await _storage.delete(key: _recordKey(scope, id));
    }
    await _complete(scope);
    return index;
  }

  @override
  Future<GenAiConversationArchive?> read(String scope, String id) =>
      _serialize(() async {
        final index = await _index(scope);
        if (_hidden(index, id)) return null;
        final raw = await _storage.read(key: _recordKey(scope, id));
        if (raw == null) return null;
        return _decode(raw, scope, id);
      });

  @override
  Future<List<GenAiConversationSummary>> list(String scope) =>
      _serialize(() async {
        final index = await _index(scope);
        final records = Map<String, Object?>.from(index['records']! as Map);
        return [
          for (final entry in records.entries)
            if (!_hidden(index, entry.key))
              GenAiConversationSummary(
                id: entry.key,
                title: (entry.value! as Map)['title'] as String,
                time: (entry.value! as Map)['time'] as String,
              ),
        ]..sort((a, b) => b.time.compareTo(a.time));
      });

  @override
  Future<Set<String>> deletedIds(String scope) => _serialize(() async {
        final index = await _index(scope);
        return {
          ...List<String>.from(index['deleted']! as List),
          ...List<String>.from(index['pendingDeletions']! as List),
        };
      });

  @override
  Future<Set<String>> pendingDeletionIds(String scope) => _serialize(() async {
        final index = await _index(scope);
        return Set<String>.from(index['pendingDeletions']! as List);
      });

  @override
  Future<void> beginDeletion(String scope, String id) =>
      _changeDeletionIntent(scope, id, begin: true);

  @override
  Future<void> rollbackDeletion(String scope, String id) =>
      _changeDeletionIntent(scope, id, begin: false);

  Future<void> _changeDeletionIntent(
    String scope,
    String id, {
    required bool begin,
  }) =>
      _serialize(() async {
        final index = await _index(scope);
        if ((index['deleted']! as List).contains(id)) return;
        await _begin(scope, id, begin ? 'beginDeletion' : 'rollbackDeletion');
        final ids = index['pendingDeletions']! as List;
        if (begin) {
          if (!ids.contains(id)) ids.add(id);
        } else {
          ids.remove(id);
        }
        await _saveIndex(scope, index);
        await _complete(scope);
      });

  @override
  Future<void> write(String scope, GenAiConversationArchive archive) =>
      _serialize(() async {
        final index = await _index(scope);
        if (_hidden(index, archive.id)) return;
        await _begin(scope, archive.id, 'write');
        await _storage.write(
          key: _recordKey(scope, archive.id),
          value: jsonEncode({
            'version': 1,
            'scope': scope,
            'archive': archive.toJson(),
          }),
        );
        _addSummary(index, archive);
        await _saveIndex(scope, index);
        await _complete(scope);
      });

  @override
  Future<void> delete(String scope, String id) => _serialize(() async {
        final index = await _index(scope);
        await _begin(scope, id, 'delete');
        (index['records']! as Map).remove(id);
        (index['pendingDeletions']! as List).remove(id);
        if (!(index['deleted']! as List).contains(id)) {
          (index['deleted']! as List).add(id);
        }
        // Tombstone first: a crash after this point must not resurrect content.
        await _saveIndex(scope, index);
        await _storage.delete(key: _recordKey(scope, id));
        await _complete(scope);
      });
}
