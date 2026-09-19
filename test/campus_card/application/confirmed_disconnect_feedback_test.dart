import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/application/confirmed_disconnect_feedback.dart';
import 'package:techpie/features/campus_card/data/mock/in_memory_ports.dart';
import 'package:techpie/features/campus_card/domain/models/feedback_models.dart';
import 'package:techpie/features/campus_card/domain/ports/platform_ports.dart';

void main() {
  test('initial offline state and repeated offline events stay silent',
      () async {
    late _Rig rig;
    fakeAsync((time) {
      rig = _Rig(online: false);
      _complete(rig.observer.start(), time);
      rig.network.emit(false);
      time.elapse(const Duration(seconds: 2));
      expect(rig.feedback.events, isEmpty);
    });
    await rig.dispose();
  });

  test('only a confirmed transition plays once until reconnection', () async {
    late _Rig rig;
    fakeAsync((time) {
      rig = _Rig();
      _complete(rig.observer.start(), time);
      rig.network.emit(false);
      time.elapse(const Duration(milliseconds: 599));
      expect(rig.feedback.events, isEmpty);
      time.elapse(const Duration(milliseconds: 1));
      time.flushMicrotasks();
      expect(rig.feedback.events, [FeedbackEvent.networkDisconnected]);
      rig.network.emit(false);
      time.elapse(const Duration(seconds: 1));
      expect(rig.feedback.events, hasLength(1));
      rig.network.emit(true);
      rig.network.emit(false);
      time.elapse(const Duration(milliseconds: 600));
      time.flushMicrotasks();
      expect(rig.feedback.events, hasLength(2));
    });
    await rig.dispose();
  });

  test('brief handovers and failed reconfirmations do not alert', () async {
    late _Rig rig;
    fakeAsync((time) {
      rig = _Rig();
      _complete(rig.observer.start(), time);
      rig.network.emit(false);
      time.elapse(const Duration(milliseconds: 300));
      rig.network.emit(true);
      time.elapse(const Duration(seconds: 1));
      expect(rig.feedback.events, isEmpty);
      rig.network.emit(false, updateQuery: false);
      time.elapse(const Duration(seconds: 1));
      expect(rig.feedback.events, isEmpty);
    });
    await rig.dispose();
  });

  for (final interruption in [
    AppLifecycleState.inactive,
    AppLifecycleState.paused,
  ]) {
    test('loss during $interruption is confirmed once after returning',
        () async {
      late _Rig rig;
      fakeAsync((time) {
        rig = _Rig();
        _complete(rig.observer.start(), time);
        rig.lifecycle.setState(interruption);
        rig.network.emit(false);
        time.elapse(const Duration(seconds: 2));
        expect(rig.feedback.events, isEmpty);
        rig.lifecycle.setState(AppLifecycleState.resumed);
        time.flushMicrotasks();
        time.elapse(const Duration(milliseconds: 599));
        expect(rig.feedback.events, isEmpty);
        time.elapse(const Duration(milliseconds: 1));
        time.flushMicrotasks();
        expect(rig.feedback.events, [FeedbackEvent.networkDisconnected]);
        rig.lifecycle.setState(interruption);
        rig.lifecycle.setState(AppLifecycleState.resumed);
        time.elapse(const Duration(seconds: 2));
        expect(rig.feedback.events, hasLength(1));
      });
      await rig.dispose();
    });
  }

  test('returning offline without a prior online baseline stays silent',
      () async {
    late _Rig rig;
    fakeAsync((time) {
      rig = _Rig(online: false);
      rig.lifecycle.setState(AppLifecycleState.inactive);
      _complete(rig.observer.start(), time);
      rig.network.emit(false);
      rig.lifecycle.setState(AppLifecycleState.resumed);
      time.elapse(const Duration(seconds: 2));
      expect(rig.feedback.events, isEmpty);
    });
    await rig.dispose();
  });

  test('a connection restored before returning does not alert', () async {
    late _Rig rig;
    fakeAsync((time) {
      rig = _Rig();
      _complete(rig.observer.start(), time);
      rig.lifecycle.setState(AppLifecycleState.inactive);
      rig.network.emit(false);
      time.elapse(const Duration(seconds: 1));
      rig.network.emit(true);
      rig.lifecycle.setState(AppLifecycleState.resumed);
      time.elapse(const Duration(seconds: 2));
      expect(rig.feedback.events, isEmpty);
    });
    await rig.dispose();
  });

  test('resume detects a loss even if no background event was delivered',
      () async {
    late _Rig rig;
    fakeAsync((time) {
      rig = _Rig();
      _complete(rig.observer.start(), time);
      rig.lifecycle.setState(AppLifecycleState.paused);
      rig.network.online = false;
      rig.lifecycle.setState(AppLifecycleState.resumed);
      time.elapse(const Duration(seconds: 1));
      expect(rig.feedback.events, [FeedbackEvent.networkDisconnected]);
    });
    await rig.dispose();
  });

  test('a newer network event wins over a stale resume query', () async {
    late _Rig rig;
    fakeAsync((time) {
      rig = _Rig();
      _complete(rig.observer.start(), time);
      rig.lifecycle.setState(AppLifecycleState.inactive);
      rig.network.emit(false);
      final query = Completer<bool>();
      rig.network.nextQuery = query.future;
      rig.lifecycle.setState(AppLifecycleState.resumed);
      time.flushMicrotasks();
      rig.network.emit(true);
      query.complete(false);
      time.elapse(const Duration(seconds: 1));
      expect(rig.feedback.events, isEmpty);
    });
    await rig.dispose();
  });

  test('a stale initial query cannot turn loading into a disconnect alert',
      () async {
    late _Rig rig;
    fakeAsync((time) {
      rig = _Rig();
      final initial = Completer<bool>();
      rig.network.nextQuery = initial.future;
      final ready = rig.observer.start();
      rig.network.emit(false);
      initial.complete(true);
      _complete(ready, time);
      rig.network.emit(false);
      time.elapse(const Duration(seconds: 1));
      expect(rig.feedback.events, isEmpty);
    });
    await rig.dispose();
  });

  test('a pending check is discarded after reconnecting or disposal', () async {
    late _Rig rig;
    late FakeAsync scheduler;
    fakeAsync((time) {
      scheduler = time;
      rig = _Rig();
      _complete(rig.observer.start(), time);
      final check = Completer<bool>();
      rig.network.nextQuery = check.future;
      rig.network.emit(false);
      time.elapse(const Duration(milliseconds: 600));
      rig.network.emit(true);
      check.complete(false);
      time.flushMicrotasks();
      expect(rig.feedback.events, isEmpty);
      rig.network.emit(false);
    });
    await rig.observer.dispose();
    scheduler.elapse(const Duration(seconds: 1));
    scheduler.flushMicrotasks();
    expect(rig.feedback.events, isEmpty);
    expect(scheduler.pendingTimers, isEmpty);
    await rig.dispose();
  });

  test('enabling sound while already offline does not replay an alert',
      () async {
    late _Rig rig;
    fakeAsync((time) {
      rig = _Rig();
      _complete(
        rig.feedback.setEnabled(
          FeedbackScenario.networkDisconnected,
          FeedbackChannel.sound,
          false,
        ),
        time,
      );
      _complete(
        rig.feedback.setEnabled(
          FeedbackScenario.networkDisconnected,
          FeedbackChannel.vibration,
          false,
        ),
        time,
      );
      _complete(rig.observer.start(), time);
      rig.network.emit(false);
      time.elapse(const Duration(milliseconds: 600));
      time.flushMicrotasks();
      expect(rig.feedback.events, isEmpty);
      _complete(
        rig.feedback.setEnabled(
          FeedbackScenario.networkDisconnected,
          FeedbackChannel.sound,
          true,
        ),
        time,
      );
      rig.network.emit(false);
      time.elapse(const Duration(seconds: 1));
      expect(rig.feedback.events, isEmpty);
    });
    await rig.dispose();
  });
}

void _complete(Future<void> future, FakeAsync time) {
  var completed = false;
  unawaited(future.then((_) => completed = true));
  time.flushMicrotasks();
  expect(completed, isTrue);
}

class _Rig {
  _Rig({bool online = true}) : network = _Connectivity(online) {
    observer = ConfirmedDisconnectFeedback(
      connectivity: network,
      lifecycle: lifecycle,
      feedback: feedback,
    );
  }
  final _Connectivity network;
  final lifecycle = InMemoryLifecyclePort();
  final feedback = InMemoryFeedbackPort();
  late final ConfirmedDisconnectFeedback observer;

  Future<void> dispose() async {
    await observer.dispose();
    await network.events.close();
  }
}

class _Connectivity implements ConnectivityPort {
  _Connectivity(this.online);
  bool online;
  Future<bool>? nextQuery;
  final events = StreamController<bool>.broadcast(sync: true);

  @override
  Stream<bool> get changes => events.stream;
  @override
  Future<bool> isOnline() {
    final pending = nextQuery;
    nextQuery = null;
    return pending ?? Future.value(online);
  }

  void emit(bool value, {bool updateQuery = true}) {
    if (updateQuery) online = value;
    events.add(value);
  }
}
