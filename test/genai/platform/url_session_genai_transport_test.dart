import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';
import 'package:techpie/features/genai/platform/url_session_genai_transport.dart';
import 'package:techpie/features/genai/platform/url_session_task.dart';

import '../support/fakes.dart' show failure;

void main() {
  final uri = Uri.https('example.invalid', '/htk/chat/start/chat');

  test('delivers headers and partial SSE before native completion', () async {
    final native = _Native();
    final transport = UrlSessionGenAiTransport(createTask: native.create);
    addTearDown(transport.dispose);
    final pending = transport.send(
      method: 'POST',
      uri: uri,
      cancellation: GenAiCancellation(),
      headers: {'Accept': 'text/event-stream'},
      body: '你好',
    );
    final task = native.tasks.single;
    task.onHeaders(200, {'Content-Type': 'text/event-stream'});
    final response = await pending;
    expect(response.headers['content-type'], 'text/event-stream');
    expect(task.body, [228, 189, 160, 229, 165, 189]);
    final iterator = StreamIterator(response.bytes);
    final first = iterator.moveNext();
    task.onData([1, 2]);
    expect(await first, isTrue);
    expect(iterator.current, [1, 2]);
    expect(task.finishes, 0);
    final done = iterator.moveNext();
    task.onComplete(null);
    expect(await done, isFalse);
    expect(task.finishes, 1);
    expect(task.cancels, 0);
  });

  test('account change before headers cancels the native task promptly', () async {
    final native = _Native();
    final transport = UrlSessionGenAiTransport(createTask: native.create);
    final cancellation = GenAiCancellation();
    final pending = transport.send(method: 'GET', uri: uri, cancellation: cancellation);
    final expected = expectLater(pending, throwsA(failure(GenAiFailureKind.accountChanged)));
    cancellation.cancel(GenAiFailureKind.accountChanged);
    await expected;
    expect(native.tasks.single.cancels, 1);
    expect(native.tasks.single.finishes, 1);
    native.tasks.single.onHeaders(200, {});
    native.tasks.single.onComplete(const GenAiFailure(GenAiFailureKind.transport));
    transport.dispose();
  });

  test('stopping an SSE stream cancels only its native task', () async {
    final native = _Native();
    final transport = UrlSessionGenAiTransport(createTask: native.create);
    addTearDown(transport.dispose);
    final cancellation = GenAiCancellation();
    final first = transport.send(method: 'POST', uri: uri, cancellation: cancellation);
    final second = transport.send(method: 'GET', uri: uri, cancellation: GenAiCancellation());
    native.tasks[0].onHeaders(200, {});
    native.tasks[1].onHeaders(200, {});
    final response = await first;
    final other = await second;
    final iterator = StreamIterator(response.bytes);
    final stopped = expectLater(iterator.moveNext(), throwsA(failure(GenAiFailureKind.cancelled)));
    cancellation.cancel();
    await stopped;
    expect(native.tasks[0].cancels, 1);
    expect(native.tasks[1].cancels, 0);
    await iterator.cancel();
    other.close();
  });

  test('closing an unread redirect response cancels without draining its body', () async {
    final native = _Native();
    final transport = UrlSessionGenAiTransport(createTask: native.create);
    final pending = transport.send(method: 'GET', uri: uri, cancellation: GenAiCancellation());
    final task = native.tasks.single;
    task.onHeaders(302, {'Location': '/next'});
    final response = await pending;
    response.close();
    response.close();
    task.onData([99]);
    task.onComplete(null);
    expect(await response.bytes.toList(), isEmpty);
    expect(task.cancels, 1);
    expect(task.finishes, 1);
    transport.dispose();
  });

  test('header and idle timeouts stop native work', () async {
    final uri = Uri.https('example.invalid', '/htk/user/info');
    final native = _Native();
    final transport = UrlSessionGenAiTransport(
      createTask: native.create,
      headerTimeout: const Duration(milliseconds: 15),
      idleTimeout: const Duration(milliseconds: 15),
    );
    addTearDown(transport.dispose);
    await expectLater(
      transport.send(method: 'GET', uri: uri, cancellation: GenAiCancellation()),
      throwsA(failure(GenAiFailureKind.timeout)),
    );
    expect(native.tasks[0].cancels, 1);
    final pending = transport.send(method: 'GET', uri: uri, cancellation: GenAiCancellation());
    native.tasks[1].onHeaders(200, {});
    final response = await pending;
    await expectLater(response.bytes.drain<void>(), throwsA(failure(GenAiFailureKind.timeout)));
    expect(native.tasks[1].cancels, 1);
  });

  test('chat prefill uses its longer header budget', () async {
    final native = _Native();
    final transport = UrlSessionGenAiTransport(
      createTask: native.create,
      headerTimeout: const Duration(milliseconds: 5),
      chatHeaderTimeout: const Duration(milliseconds: 250),
    );
    addTearDown(transport.dispose);
    final pending = transport.send(
      method: 'POST',
      uri: uri,
      cancellation: GenAiCancellation(),
      headers: {'Accept': 'text/event-stream'},
    );
    await Future<void>.delayed(const Duration(milliseconds: 25));
    native.tasks.single.onHeaders(200, {});
    (await pending).close();
  });

  test('consumer backpressure suspends the idle deadline', () async {
    final native = _Native();
    final transport = UrlSessionGenAiTransport(
      createTask: native.create,
      idleTimeout: const Duration(milliseconds: 10),
    );
    addTearDown(transport.dispose);
    final pending = transport.send(method: 'GET', uri: uri, cancellation: GenAiCancellation());
    final task = native.tasks.single;
    task.onHeaders(200, {});
    final response = await pending;
    final first = Completer<void>();
    final subscription = response.bytes.listen((_) => first.complete());
    subscription.pause();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(task.cancels, 0);
    subscription.resume();
    task.onData([1]);
    await first.future;
    final done = subscription.asFuture<void>();
    task.onComplete(null);
    await done;
  });

  test('dispose aborts pending requests and rejects new ones', () async {
    final native = _Native();
    final transport = UrlSessionGenAiTransport(createTask: native.create);
    final pending = transport.send(method: 'GET', uri: uri, cancellation: GenAiCancellation());
    final expected = expectLater(pending, throwsA(failure(GenAiFailureKind.cancelled)));
    transport.dispose();
    await expected;
    expect(native.tasks.single.cancels, 1);
    await expectLater(
      transport.send(method: 'GET', uri: uri, cancellation: GenAiCancellation()),
      throwsA(failure(GenAiFailureKind.cancelled)),
    );
  });
}

final class _Native {
  final tasks = <_Task>[];
  GenAiUrlSessionTask create({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required List<int>? body,
    required void Function(int, Map<String, String>) onHeaders,
    required void Function(List<int>) onData,
    required void Function(GenAiFailure?) onComplete,
  }) {
    final task = _Task(body, onHeaders, onData, onComplete);
    tasks.add(task);
    return task;
  }
}

final class _Task implements GenAiUrlSessionTask {
  _Task(this.body, this.onHeaders, this.onData, this.onComplete);
  final List<int>? body;
  final void Function(int, Map<String, String>) onHeaders;
  final void Function(List<int>) onData;
  final void Function(GenAiFailure?) onComplete;
  int cancels = 0;
  int finishes = 0;
  @override
  void resume() {}
  @override
  void suspend() {}
  @override
  void cancel() => cancels++;
  @override
  void finish() => finishes++;
}
