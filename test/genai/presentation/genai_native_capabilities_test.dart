import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/presentation/audio/genai_audio_player.dart';
import 'package:techpie/features/genai/presentation/audio/genai_audio_recorder.dart';
import 'package:techpie/features/genai/presentation/picker/genai_picker.dart';

void main() {
  test('native audio reports unavailable and refuses simulated success',
      () async {
    final player = GenAiAudioPlayer();
    final recorder = GenAiAudioRecorder();
    expect(player.isSupported, isFalse);
    expect(recorder.isSupported, isFalse);
    expect(await recorder.hasPermission(), isFalse);
    await expectLater(player.playWav([0, 1]), throwsUnsupportedError);
    await expectLater(recorder.start(), throwsUnsupportedError);
    expect(player.isPlaying, isFalse);
    expect(recorder.isRecording, isFalse);
    player.dispose();
    recorder.dispose();
  });

  test(
      'native file capabilities distinguish unsupported actions from cancellation',
      () async {
    final picker = GenAiPicker();
    expect(picker.supportsDocuments, isFalse);
    expect(picker.supportsAudio, isFalse);
    await expectLater(picker.pickDocument(), throwsUnsupportedError);
    await expectLater(picker.pickAudio(), throwsUnsupportedError);
  });
}
