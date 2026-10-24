import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../application/genai_workspace_controller.dart';
import '../picker/genai_picker.dart';
import 'genai_audio_player.dart';
import 'genai_audio_recorder.dart';

typedef _MediaScope = (GenAiWorkspaceController, int, int);
typedef GenAiTranscriptionCallback = void Function(
  String text, {
  required bool requestFocus,
});

/// Presentation lifetime for pickers, microphone recording, and speech playback.
/// Late results are ignored after an account, conversation, or screen change.
class GenAiWorkspaceMedia extends ChangeNotifier {
  GenAiWorkspaceMedia({
    required GenAiWorkspaceController workspace,
    required this.onMessage,
    required this.onTranscription,
    GenAiPicker? picker,
    GenAiAudioPlayer? audioPlayer,
    GenAiAudioRecorder? audioRecorder,
  })  : _workspace = workspace,
        _picker = picker ?? GenAiPicker(),
        _audioPlayer = audioPlayer ?? GenAiAudioPlayer(),
        _audioRecorder = audioRecorder ?? GenAiAudioRecorder() {
    _mediaScope = _scope;
    _workspace.addListener(_workspaceChanged);
    _audioPlayer.onFinished = () {
      if (!_disposed) _update(() => _playingTtsTurnIndex = null);
    };
  }

  GenAiWorkspaceController _workspace;
  final GenAiPicker _picker;
  final GenAiAudioPlayer _audioPlayer;
  final GenAiAudioRecorder _audioRecorder;
  final ValueChanged<String> onMessage;
  final GenAiTranscriptionCallback onTranscription;
  bool _disposed = false;
  bool _recordingAudio = false;
  bool _startingAudio = false;
  int _recordingSeconds = 0;
  Timer? _recordingTimer;
  int _ttsOperation = 0;
  int? _playingTtsTurnIndex;
  bool _loadingTts = false;
  late _MediaScope _mediaScope;

  bool get supportsDocuments => _picker.supportsDocuments;
  bool get supportsAudio => _picker.supportsAudio;
  bool get supportsRecording => _audioRecorder.isSupported;
  bool get supportsPlayback => _audioPlayer.isSupported;
  bool get recording => _recordingAudio;
  bool get startingRecording => _startingAudio;
  int get recordingSeconds => _recordingSeconds;
  int? get playingTtsTurnIndex => _playingTtsTurnIndex;
  bool get loadingTts => _loadingTts;

  _MediaScope get _scope => (
        _workspace,
        _workspace.sessions.revision,
        _workspace.conversationRevision
      );
  bool _isCurrent(_MediaScope scope) => !_disposed && scope == _scope;

  void _update(VoidCallback update) {
    if (_disposed) return;
    update();
    notifyListeners();
  }

  void bindWorkspace(GenAiWorkspaceController workspace) {
    if (identical(workspace, _workspace)) return;
    _workspace.removeListener(_workspaceChanged);
    _workspace = workspace;
    _workspace.addListener(_workspaceChanged);
    _workspaceChanged();
  }

  void _workspaceChanged() {
    if (_mediaScope == _scope) return;
    _mediaScope = _scope;
    _ttsOperation++;
    _playingTtsTurnIndex = null;
    _loadingTts = false;
    _recordingAudio = false;
    _recordingTimer?.cancel();
    unawaited(_audioRecorder.cancel());
    unawaited(_audioPlayer.stop());
    notifyListeners();
  }

  Future<void> toggleTts(int index, String text) async {
    if (!_audioPlayer.isSupported) return;
    final scope = _scope;
    final operation = ++_ttsOperation;
    bool current() => _isCurrent(scope) && operation == _ttsOperation;
    if (_playingTtsTurnIndex == index) {
      await _audioPlayer.stop();
      if (!current()) return;
      _update(() {
        _playingTtsTurnIndex = null;
        _loadingTts = false;
      });
      return;
    }
    await _audioPlayer.stop();
    if (!current()) return;
    _update(() {
      _playingTtsTurnIndex = index;
      _loadingTts = true;
    });
    try {
      final cleanText = text
          .replaceAll(RegExp(r'```[\s\S]*?```'), '')
          .replaceAll(RegExp(r'[#*`_~]'), '')
          .trim();
      final wavBytes = await scope.$1.synthesizeSpeech(
        cleanText.length > 500 ? cleanText.substring(0, 500) : cleanText,
      );
      if (!current()) return;
      _update(() => _loadingTts = false);
      await _audioPlayer.playWav(wavBytes);
    } catch (_) {
      if (!_disposed && current()) {
        _update(() {
          _playingTtsTurnIndex = null;
          _loadingTts = false;
        });
        onMessage('语音播报失败，请稍后重试');
      }
    }
  }

  Future<void> pickDocument() async {
    final scope = _scope;
    try {
      if (!_picker.supportsDocuments) return;
      final file = await _picker.pickDocument();
      if (file == null || !_isCurrent(scope)) return;
      await scope.$1.addDocumentAttachment(file.name, file.bytes);
    } catch (_) {
      if (!_disposed && _isCurrent(scope)) {
        onMessage('无法选择文档');
      }
    }
  }

  Future<void> pickImage() async {
    final scope = _scope;
    try {
      final file = await _picker.pickImage();
      if (file == null || !_isCurrent(scope)) return;
      await scope.$1.addImageAttachment(file.name, file.bytes);
    } catch (_) {
      if (!_disposed && _isCurrent(scope)) {
        onMessage('无法选择图片');
      }
    }
  }

  Future<void> startAudioRecording() async {
    if (!_audioRecorder.isSupported ||
        _recordingAudio ||
        _startingAudio ||
        _workspace.sending ||
        _workspace.recognizingAudio) {
      return;
    }
    final scope = _scope;
    _startingAudio = true;
    try {
      final hasPerm = await _audioRecorder.hasPermission();
      if (!_isCurrent(scope)) return;
      if (!hasPerm) {
        if (!_disposed && _isCurrent(scope)) {
          onMessage('无法访问麦克风，请检查权限设置');
        }
        return;
      }
      await _audioRecorder.start();
      if (!_isCurrent(scope)) {
        await _audioRecorder.cancel();
        return;
      }
      _update(() {
        _recordingAudio = true;
        _recordingSeconds = 0;
      });
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_disposed) {
          timer.cancel();
          return;
        }
        _update(() {
          _recordingSeconds++;
        });
        if (_recordingSeconds >= 120) {
          unawaited(stopAudioRecording());
        }
      });
    } catch (_) {
      if (!_disposed && _isCurrent(scope)) {
        onMessage('无法启动麦克风录音，请检查权限设置');
      }
    } finally {
      _startingAudio = false;
    }
  }

  Future<void> stopAudioRecording() async {
    final scope = _scope;
    if (!_recordingAudio) return;
    _recordingTimer?.cancel();
    _update(() => _recordingAudio = false);
    try {
      final wavBytes = await _audioRecorder.stop();
      if (wavBytes == null || wavBytes.isEmpty || !_isCurrent(scope)) return;
      final text = await scope.$1.transcribeAudio('recording.wav', wavBytes);
      if (text != null && text.isNotEmpty && _isCurrent(scope)) {
        onTranscription(text, requestFocus: true);
      }
    } catch (_) {
      if (!_disposed && _isCurrent(scope)) {
        onMessage('语音识别失败，请稍后重试');
      }
    }
  }

  Future<void> cancelAudioRecording() async {
    if (!_recordingAudio) return;
    _recordingTimer?.cancel();
    _update(() => _recordingAudio = false);
    await _audioRecorder.cancel();
  }

  Future<void> pickAudioFile() async {
    final scope = _scope;
    try {
      if (!_picker.supportsAudio) return;
      final file = await _picker.pickAudio();
      if (file == null || !_isCurrent(scope)) return;
      final text = await scope.$1.transcribeAudio(file.name, file.bytes);
      if (text != null && text.isNotEmpty && _isCurrent(scope)) {
        onTranscription(text, requestFocus: false);
      }
    } catch (_) {
      if (!_disposed && _isCurrent(scope)) {
        onMessage('语音识别失败，请稍后重试');
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _workspace.removeListener(_workspaceChanged);
    _recordingTimer?.cancel();
    _audioPlayer.onFinished = null;
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }
}
