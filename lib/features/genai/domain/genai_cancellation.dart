import 'dart:async';

import 'genai_failure.dart';

/// Per-operation cancellation, including requests still awaiting headers.
final class GenAiCancellation {
  final _cancelled = Completer<void>();
  final _listeners = <void Function()>{};
  GenAiFailure? _failure;

  bool get isCancelled => _failure != null;
  Future<void> get whenCancelled => _cancelled.future;

  void cancel([GenAiFailureKind kind = GenAiFailureKind.cancelled]) {
    if (isCancelled) return;
    _failure = GenAiFailure(kind);
    _cancelled.complete();
    final listeners = _listeners.toList();
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }

  void throwIfCancelled() {
    final failure = _failure;
    if (failure != null) throw failure;
  }

  /// Returns a disposer so completed requests do not accumulate listeners.
  void Function() onCancel(void Function() listener) {
    if (isCancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
    return () => _listeners.remove(listener);
  }

  Future<T> race<T>(Future<T> operation) {
    final result = Completer<T>();
    final remove = onCancel(() {
      if (!result.isCompleted) result.completeError(_failure!);
    });
    unawaited(
      operation.then<void>(
        (value) {
          if (!result.isCompleted) result.complete(value);
        },
        onError: (Object error, StackTrace stack) {
          if (!result.isCompleted) result.completeError(error, stack);
        },
      ),
    );
    return result.future.whenComplete(remove);
  }
}
