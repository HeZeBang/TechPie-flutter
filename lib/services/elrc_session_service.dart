import 'package:flutter/foundation.dart';

import 'elrc_error.dart';

/// Tracks anonymous playback lifetime and discards results after disconnect.
class ElrcSessionService extends ChangeNotifier {
  static int _nextGeneration = 0;
  int _generation = 0;
  bool _connected = false;
  bool _disposed = false;

  int get generation => _generation;
  bool get isConnected => _connected;

  void check(int expected) {
    if (_disposed || !_connected || expected != _generation) {
      throw const ElrcException(ElrcErrorKind.staleSession);
    }
  }

  Future<void> connect() async {
    if (_disposed) throw const ElrcException(ElrcErrorKind.staleSession);
    if (_connected) return;
    _generation = ++_nextGeneration;
    _connected = true;
    notifyListeners();
  }

  void disconnect() {
    if (_disposed) return;
    _generation = ++_nextGeneration;
    _connected = false;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    _disposed = true;
    super.dispose();
  }
}
