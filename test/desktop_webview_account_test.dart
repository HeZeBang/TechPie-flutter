import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/pages/webview_host.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('webview_window');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  test('account change closes the parent and child but leaves ordinary desktop windows open',
      () async {
    var id = 0;
    final closed = <int>[];
    final childReady = Completer<void>();
    final account = ValueNotifier('first');
    final owner = DesktopWebviewAccount(account, () => account.value == 'first');
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'create') return ++id;
      final viewId = (call.arguments as Map)['viewId'] as int;
      if (call.method == 'launch' && viewId == 2) childReady.complete();
      if (call.method == 'close') closed.add(viewId);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final parent =
        await openDesktopWebview(title: '测试', url: 'https://example.invalid', account: owner);
    final host = DesktopWebviewHost(parent!, null, account: owner);
    host.openUrl('https://example.invalid/child');
    await childReady.future;
    await openDesktopWebview(title: '普通网页', url: 'https://example.invalid/other');
    account.value = 'next';
    await Future<void>.delayed(Duration.zero);
    expect(closed, [1, 2]);
    host.openUrl('https://example.invalid/stale');
    await Future<void>.delayed(Duration.zero);
    expect(id, 3);
    expect(
      await openDesktopWebview(title: '过期', url: 'https://example.invalid/stale', account: owner),
      isNull,
    );
    expect(id, 3);
  });

  test('an account change during window creation cancels before cookie injection or navigation',
      () async {
    final creating = Completer<void>(), finish = Completer<int>();
    final calls = <String>[];
    final account = ValueNotifier(true);
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'create') {
        creating.complete();
        return finish.future;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final window = openDesktopWebview(
      title: '测试',
      url: 'https://example.invalid',
      account: DesktopWebviewAccount(account, () => account.value),
      cookies: const [
        WebViewCookie(name: 'session', value: 'fixture', domain: 'example.invalid'),
      ],
    );
    await creating.future;
    account.value = false;
    finish.complete(4);
    expect(await window, isNull);
    expect(calls, ['create', 'close']);
  });
}
