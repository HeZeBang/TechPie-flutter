import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/services/usage_telemetry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late DateTime now;
  late List<Map<String, dynamic>> batches;
  late int status;

  UsageTelemetry create({bool existing = false, http.Client Function()? transport}) {
    return UsageTelemetry(
      prefs,
      endpoint: Uri.parse('http://localhost/api/telemetry'),
      version: '1.1.0+32',
      platform: 'linux',
      existingInstall: existing,
      clock: () => now,
      clientFactory: transport ??
          () => MockClient((request) async {
                expect(request.followRedirects, isFalse);
                expect(request.headers.containsKey('authorization'), isFalse);
                expect(request.headers.containsKey('cookie'), isFalse);
                batches.add(jsonDecode(request.body) as Map<String, dynamic>);
                return http.Response('', status);
              }),
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    now = DateTime.utc(2026, 11, 2);
    batches = [];
    status = 204;
  });

  test('first-run consent, login and method-specific anonymous events', () async {
    final metrics = create();
    addTearDown(metrics.dispose);
    final launch = now;
    now = now.add(const Duration(minutes: 1));
    metrics.firstLogin();
    metrics.featureOpened('grades');
    expect(metrics.beginFeedback(), isNull);
    await metrics.flush();
    expect(batches, isEmpty);
    expect(prefs.getKeys().where((key) => prefs.get(key) is String), isEmpty);

    await metrics.setEnabled(true);
    metrics.opened();
    metrics.firstLogin();
    metrics.featureOpened('arbitrary private text');
    metrics.featureOpened('grades');
    metrics.beginFeedback()!
      ..feedbackAttempt()
      ..feedbackResult(false)
      ..feedbackAttempt()
      ..feedbackResult(true);
    metrics.beginRecording()!
      ..recordingReady()
      ..recordingReady()
      ..recordingError()
      ..recordingExit()
      ..recordingError();
    await metrics.flush();

    final batch = batches.single;
    expect(batch.keys, unorderedEquals(['installation', 'events']));
    expect(batch['installation'], matches(RegExp(r'^[0-9a-f]{32}$')));
    final events = (batch['events'] as List).cast<Map<String, dynamic>>();
    expect(events.map((e) => e['kind']), [
      'first_launch',
      'first_login',
      'app_open',
      'feature_open',
      'feedback_open',
      'feedback_attempt',
      'feedback_failure',
      'feedback_attempt',
      'feedback_success',
      'recording_open',
      'recording_ready',
      'recording_error',
      'recording_exit',
    ]);
    expect(events.first['at'], launch.millisecondsSinceEpoch);
    expect(events[1]['at'], now.millisecondsSinceEpoch);
    expect(events[3]['feature'], 'grades');
    expect(events.map((e) => e['id']).toSet(), hasLength(events.length));
    expect(events.sublist(4, 9).map((e) => e['visit']).toSet(), hasLength(1));
    expect(events.sublist(9).map((e) => e['visit']).toSet(), hasLength(1));
    expect(events[4]['visit'], isNot(events[9]['visit']));
    expect(events.last['elapsed'], isNonNegative);
    expect(jsonEncode(batch), isNot(contains('arbitrary private text')));
  });

  test('existing installs and late consent do not enter new-install cohorts', () async {
    final existing = create(existing: true);
    await existing.setEnabled(true);
    await existing.flush();
    expect(batches.single['events'].single['kind'], 'app_open');
    await existing.setEnabled(false);
    existing.dispose();

    final next = create();
    addTearDown(next.dispose);
    await next.setEnabled(true);
    now = now.add(const Duration(days: 1));
    next.opened();
    await next.flush();
    expect((batches.last['events'] as List).map((e) => e['kind']), ['app_open', 'app_open']);
    expect(batches.first['installation'], isNot(batches.last['installation']));
  });

  test('unacknowledged batches survive a restart with stable event IDs', () async {
    status = 200; // An HTML success response is not a collector acknowledgement.
    final first = create();
    await first.setEnabled(true);
    await first.flush();
    first.dispose();
    final next = create();
    addTearDown(next.dispose);
    status = 204;
    await next.flush();
    expect(batches.last['installation'], batches.first['installation']);
    expect((batches.last['events'] as List).take(2), batches.first['events']);
    await next.flush();
    expect(batches, hasLength(2));
  });

  test('delayed acknowledgements and open forms cannot cross opt-out', () async {
    final entered = Completer<void>();
    final ack = Completer<void>();
    final metrics = create(
      transport: () => MockClient((req) async {
        batches.add(jsonDecode(req.body) as Map<String, dynamic>);
        if (!entered.isCompleted) {
          entered.complete();
          await ack.future;
        }
        return http.Response('', 204);
      }),
    );
    addTearDown(metrics.dispose);
    await metrics.setEnabled(true);
    final oldForm = metrics.beginFeedback()!;
    final oldFlush = metrics.flush();
    await entered.future;
    await metrics.setEnabled(false);
    expect(prefs.getKeys().where((key) => prefs.get(key) is String), isEmpty);
    await metrics.setEnabled(true);
    oldForm.feedbackResult(true);
    metrics.featureOpened('schedule');
    ack.complete();
    await oldFlush;
    await metrics.flush();
    expect(batches, hasLength(2));
    expect(batches.first['installation'], isNot(batches.last['installation']));
    expect((batches.last['events'] as List).map((e) => e['kind']), ['app_open', 'feature_open']);
  });

  test('drops permanently rejected 4xx batches while retaining 408/429/5xx', () async {
    final metrics = create();
    addTearDown(metrics.dispose);
    status = 400;
    await metrics.setEnabled(true);
    await metrics.flush();
    expect(batches, hasLength(1));

    // The 400 batch was discarded, so only newly queued events are sent next.
    status = 422;
    metrics.featureOpened('grades');
    await metrics.flush();
    expect(batches, hasLength(2));
    expect(
      (batches.last['events'] as List).map((e) => e['kind']),
      ['feature_open'],
    );

    // 429, 408 and 500 must retain the batch so a later flush resends the same IDs.
    for (final retryStatus in [429, 408, 500]) {
      batches.clear();
      status = retryStatus;
      metrics.featureOpened('schedule');
      await metrics.flush();
      status = 204;
      await metrics.flush();
      expect(batches, hasLength(2));
      expect(batches.last['events'], batches.first['events']);
    }
  });
}
