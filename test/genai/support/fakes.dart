import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/domain/genai_contract.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';
import 'package:techpie/features/genai/domain/genai_session.dart';
import 'package:techpie/features/genai/platform/genai_transport.dart';
import 'package:techpie/features/genai/presentation/audio/genai_audio_recorder.dart';
import 'package:techpie/features/genai/presentation/picker/genai_picker.dart';

const ownerA = GenAiOwner(
  primaryUserId: 'primary-a',
  studentId: '20240001',
  bindingId: 'binding-a',
);
const ownerB = GenAiOwner(
  primaryUserId: 'primary-b',
  studentId: '20240002',
  bindingId: 'binding-b',
);

GenAiChatRequest chatRequest() => GenAiChatRequest(
      chatGroupId: 'synthetic-conversation',
      prompt: '你好',
      aiType: 'fixture-model',
      rootAiType: 'fixture-provider',
    );

Matcher failure(GenAiFailureKind kind) =>
    isA<GenAiFailure>().having((e) => e.kind, 'kind', kind);

String sseChunk({String? text, String? reasoning, String? finish}) =>
    'data: ${jsonEncode({
          'choices': [
            {
              'index': 0,
              'delta': {
                if (text != null) 'content': text,
                if (reasoning != null) 'reasoning_content': reasoning,
              },
              if (finish != null) 'finish_reason': finish,
            },
          ],
        })}\n\n';

GenAiResponse response({
  int status = 200,
  String type = 'application/json',
  Object? json,
  String? text,
  Stream<List<int>>? bytes,
  void Function()? close,
}) =>
    GenAiResponse(
      statusCode: status,
      headers: {'Content-Type': type},
      bytes: bytes ?? Stream.value(utf8.encode(text ?? jsonEncode(json))),
      close: close ?? () {},
    );

GenAiResponse profileResponse([String username = '20240001']) => response(
      json: {
        'success': true,
        'code': 200,
        'result': {
          'userInfo': {'id': 'synthetic-user', 'username': username},
        },
      },
    );

final class RecordedRequest {
  const RecordedRequest(
    this.method,
    this.uri,
    this.headers,
    this.body,
    this.cancellation, {
    this.bodyBytes,
  });
  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String? body;
  final List<int>? bodyBytes;
  final GenAiCancellation cancellation;
}

final class ScriptedTransport implements GenAiTransport {
  ScriptedTransport(this.handle);
  Future<GenAiResponse> Function(RecordedRequest) handle;
  final requests = <RecordedRequest>[];
  bool disposed = false;

  @override
  Future<GenAiResponse> send({
    required String method,
    required Uri uri,
    required GenAiCancellation cancellation,
    Map<String, String> headers = const {},
    String? body,
    List<int>? bodyBytes,
  }) {
    final request = RecordedRequest(
      method,
      uri,
      headers,
      body,
      cancellation,
      bodyBytes: bodyBytes,
    );
    requests.add(request);
    return handle(request);
  }

  @override
  void dispose() {
    disposed = true;
  }
}

final class MemorySessionStore implements GenAiSessionStore {
  final records = <String, GenAiSession>{};
  int reads = 0;
  int writes = 0;
  bool failDelete = false;

  @override
  Future<GenAiSession?> read(GenAiOwner owner) async {
    reads++;
    return records[owner.storageId];
  }

  @override
  Future<void> write(GenAiSession session) async {
    writes++;
    records[session.owner.storageId] = session;
  }

  @override
  Future<void> delete(GenAiOwner owner) async {
    if (failDelete) throw StateError('synthetic storage error');
    records.remove(owner.storageId);
  }
}

final class CallbackIssuer implements GenAiSessionIssuer {
  CallbackIssuer(this.callback);
  final Future<GenAiCredential> Function(GenAiOwner, GenAiCancellation)
      callback;
  int calls = 0;
  @override
  Future<GenAiCredential> issue(
    GenAiOwner owner,
    GenAiCancellation cancellation,
  ) {
    calls++;
    return callback(owner, cancellation);
  }
}

final class FakeGenAiAudioRecorder implements GenAiAudioRecorder {
  FakeGenAiAudioRecorder({
    this.permission = true,
    this.recordedBytes,
  });

  bool permission;
  Uint8List? recordedBytes;
  bool recording = false;
  int startCalls = 0;
  int stopCalls = 0;
  int cancelCalls = 0;
  int disposeCalls = 0;

  @override
  bool get isRecording => recording;

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<void> start() async {
    startCalls++;
    recording = true;
  }

  @override
  Future<Uint8List?> stop() async {
    stopCalls++;
    recording = false;
    return recordedBytes;
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
    recording = false;
  }

  @override
  void dispose() {
    disposeCalls++;
    recording = false;
  }
}

final class FakeGenAiPicker implements GenAiPicker {
  FakeGenAiPicker({
    this.nextDocument,
    this.nextImage,
    this.nextAudio,
  });

  GenAiPickedFile? nextDocument;
  GenAiPickedFile? nextImage;
  GenAiPickedFile? nextAudio;
  int pickImageCalls = 0;
  int pickDocumentCalls = 0;
  int pickAudioCalls = 0;

  @override
  Future<GenAiPickedFile?> pickDocument() async {
    pickDocumentCalls++;
    return nextDocument;
  }

  @override
  Future<GenAiPickedFile?> pickImage() async {
    pickImageCalls++;
    return nextImage;
  }

  @override
  Future<GenAiPickedFile?> pickAudio() async {
    pickAudioCalls++;
    return nextAudio;
  }
}
