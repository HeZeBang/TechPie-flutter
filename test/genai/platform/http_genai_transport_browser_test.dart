@TestOn('browser')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:techpie/features/genai/data/genai_api_client.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/domain/genai_contract.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';
import 'package:techpie/features/genai/platform/http_genai_transport.dart';

import '../support/fakes.dart';

void main() {
  const origin = String.fromEnvironment('GENAI_TEST_ORIGIN');
  if (origin.isEmpty) {
    test(
      'local streaming fixture must be explicitly configured',
      () {},
      skip: 'See docs/genai-api-contract.md for the Chrome fixture command.',
    );
    return;
  }
  final uri = Uri.parse(origin);
  if (uri.scheme != 'http' || uri.host != '127.0.0.1' || uri.path.isNotEmpty) {
    throw ArgumentError(
      'Browser streaming tests require a loopback fixture origin',
    );
  }

  for (final cancel in [false, true]) {
    test(
        cancel
            ? 'Fetch cancellation aborts an active streamed POST'
            : 'Fetch receives text before the server finishes its POST response',
        () async {
      final group = cancel ? 'browser-cancel' : 'browser-complete';
      final transport = HttpGenAiTransport();
      final control = http.Client();
      addTearDown(() {
        transport.dispose();
        control.close();
      });
      final api = GenAiApiClient(
        transport: transport,
        apiBase: Uri.parse('$origin/htk/'),
      );
      final cancellation = GenAiCancellation();
      final partial = Completer<void>();
      final events = <GenAiChatEvent>[];
      var completed = false;
      final streaming = api
          .streamChat(
        GenAiChatRequest(
          chatGroupId: group,
          prompt: 'synthetic only',
          aiType: 'fixture',
          rootAiType: 'fixture',
        ),
        'synthetic-browser-token',
        cancellation,
      )
          .forEach((event) {
        events.add(event);
        if (event is GenAiTextDelta && !partial.isCompleted) partial.complete();
      }).whenComplete(() => completed = true);
      final expected = cancel
          ? expectLater(streaming, throwsA(failure(GenAiFailureKind.cancelled)))
          : expectLater(streaming, completes);
      await partial.future.timeout(const Duration(seconds: 5));
      expect(completed, isFalse);
      expect(events.whereType<GenAiTextDelta>().single.text, '你好');
      if (cancel) cancellation.cancel();
      await control.get(Uri.parse('$origin/release/$group'));
      await expected;
      expect(events.whereType<GenAiChatFinished>().length, cancel ? 0 : 1);
    });
  }
}
