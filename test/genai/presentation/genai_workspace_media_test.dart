import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_chat_service.dart';
import 'package:techpie/features/genai/application/genai_repository.dart';
import 'package:techpie/features/genai/application/genai_session_service.dart';
import 'package:techpie/features/genai/application/genai_workspace_controller.dart';
import 'package:techpie/features/genai/data/genai_api_client.dart';
import 'package:techpie/features/genai/domain/genai_session.dart';
import 'package:techpie/features/genai/presentation/audio/genai_audio_player.dart';
import 'package:techpie/features/genai/presentation/audio/genai_workspace_media.dart';

import '../support/fakes.dart';

class _Player implements GenAiAudioPlayer {
  int plays = 0;
  @override
  bool get isSupported => true;
  @override
  bool get isPlaying => false;
  @override
  set onFinished(void Function()? callback) {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> playWav(List<int> bytes) async => plays++;
  @override
  void dispose() {}
}

void main() {
  test('speech skips non-readable replies and sends readable link text without math or URLs',
      () async {
    final spoken = <String>[];
    final transport = ScriptedTransport((request) async {
      if (request.uri.path.endsWith('convert2wav')) {
        spoken.add((jsonDecode(request.body!) as Map)['text'] as String);
        return response(type: 'audio/wav', text: 'audio');
      }
      return profileResponse();
    });
    final api = GenAiApiClient(transport: transport);
    final sessions = GenAiSessionService(api: api, store: MemorySessionStore());
    await sessions.setOwner(ownerA);
    await sessions.connect(const GenAiCredential(token: 'fixture'));
    final repository = GenAiRepository(api: api, sessions: sessions);
    final chat = GenAiChatService(repository);
    final workspace =
        GenAiWorkspaceController(sessions: sessions, repository: repository, chat: chat);
    final player = _Player();
    final notices = <String>[];
    final media = GenAiWorkspaceMedia(
      workspace: workspace,
      audioPlayer: player,
      onMessage: notices.add,
      onTranscription: (_, {required requestFocus}) {},
    );
    addTearDown(() {
      media.dispose();
      workspace.dispose();
      chat.dispose();
      sessions.dispose();
    });
    await media.toggleTts(0, '```dart\nprint(1);\n```\n---\n##');
    expect(spoken, isEmpty);
    expect(player.plays, 0);
    expect(media.loadingTts, false);
    expect(media.playingTtsTurnIndex, isNull);
    expect(notices, ['没有可供语音播报的文本内容']);
    await media.toggleTts(1, r'Read [notes](https://example.com) $$\frac{1}{2}$$ $x=y$ now.');
    expect(spoken.single, contains('Read notes'));
    expect(spoken.single, isNot(contains('https')));
    expect(spoken.single, isNot(contains('frac')));
    expect(spoken.single, isNot(contains('x=y')));
    expect(player.plays, 1);
  });
}
