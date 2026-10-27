import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/domain/genai_session.dart';
import 'package:techpie/features/genai/presentation/audio/genai_audio_recorder.dart';
import 'package:techpie/features/genai/presentation/genai_workspace.dart';
import 'package:techpie/features/genai/presentation/picker/genai_picker.dart';

import '../support/workspace_server.dart';

class DeferredPicker implements GenAiPicker {
  final selected = Completer<GenAiPickedFile?>();
  @override
  bool get supportsDocuments => true;
  @override
  bool get supportsAudio => true;
  @override
  Future<GenAiPickedFile?> pickDocument() => selected.future;
  @override
  Future<GenAiPickedFile?> pickImage() => selected.future;
  @override
  Future<GenAiPickedFile?> pickAudio() => selected.future;
}

class DeferredRecorder implements GenAiAudioRecorder {
  final granted = Completer<void>();
  bool active = false;
  @override
  bool get isSupported => true;
  @override
  bool get isRecording => active;
  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<void> start() async {
    await granted.future;
    active = true;
  }

  @override
  Future<Uint8List?> stop() async {
    active = false;
    return null;
  }

  @override
  Future<void> cancel() async {
    active = false;
  }

  @override
  void dispose() {
    active = false;
  }
}

void main() {
  for (final kind in ['document', 'image', 'audio']) {
    for (final boundary in ['account', 'conversation', 'controller']) {
      testWidgets('pending $kind selection cannot cross $boundary scope', (tester) async {
        final demo = await TestGenAiWorkspace.create();
        final picker = DeferredPicker();
        addTearDown(demo.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: GenAiWorkspace(
              controller: demo.workspace,
              picker: picker,
              login: (_) async => null,
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (kind == 'audio') {
          await tester.longPress(find.byKey(const ValueKey('genai-audio-stt')));
        } else {
          await tester.tap(find.byKey(const ValueKey('genai-composer-more')));
          await tester.pumpAndSettle();
          await tester.tap(find.text(kind == 'document' ? '上传文档' : '上传图片'));
        }
        await tester.pump();
        if (boundary == 'conversation') {
          demo.workspace.newConversation();
        } else if (boundary == 'controller') {
          final replacement = await TestGenAiWorkspace.create();
          addTearDown(replacement.dispose);
          await tester.pumpWidget(
            MaterialApp(
              home: GenAiWorkspace(
                controller: replacement.workspace,
                picker: picker,
                login: (_) async => null,
              ),
            ),
          );
        } else {
          await demo.sessions.setOwner(
            const GenAiOwner(
              primaryUserId: 'another-primary',
              studentId: FakeGenAiServer.studentId,
              bindingId: 'another-binding',
            ),
          );
          await demo.sessions.connect(const GenAiCredential(token: FakeGenAiServer.token));
        }
        await tester.pumpAndSettle();
        picker.selected.complete(
          GenAiPickedFile(
            name: 'old-owner-private.txt',
            bytes: Uint8List.fromList([65]),
          ),
        );
        await tester.pumpAndSettle();
        final current = tester.widget<GenAiWorkspace>(find.byType(GenAiWorkspace)).controller;
        final attachments = current.attachments;
        expect(
          tester.widget<TextField>(find.byKey(const ValueKey('genai-prompt'))).controller!.text,
          isEmpty,
        );
        await tester.pumpWidget(const SizedBox());
        expect(
          attachments,
          isEmpty,
          reason:
              'A file chosen under the old account was uploaded and attached under the new account',
        );
      });
    }
  }
  for (final boundary in ['dispose', 'conversation', 'account']) {
    testWidgets('pending microphone start must stop after $boundary', (tester) async {
      final demo = await TestGenAiWorkspace.create();
      final recorder = DeferredRecorder();
      addTearDown(demo.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: GenAiWorkspace(
            controller: demo.workspace,
            audioRecorder: recorder,
            login: (_) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('genai-audio-stt')));
      await tester.pump();
      if (boundary == 'dispose') {
        await tester.pumpWidget(const SizedBox());
      } else if (boundary == 'conversation') {
        demo.workspace.newConversation();
      } else {
        await demo.sessions.disconnect();
      }
      recorder.granted.complete();
      await tester.pump();
      final remainedActive = recorder.active;
      await recorder.cancel();
      await tester.pumpWidget(const SizedBox());
      expect(
        remainedActive,
        isFalse,
        reason: 'Microphone start completed after dispose and left the recorder active',
      );
    });
  }
}
