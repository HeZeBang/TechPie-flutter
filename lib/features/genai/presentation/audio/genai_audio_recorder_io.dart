import 'genai_audio_recorder.dart';
import 'genai_audio_recorder_stub.dart';

/// Native microphone support is unavailable until a recording plugin is wired.
GenAiAudioRecorder createGenAiAudioRecorder() => GenAiAudioRecorderStub();
