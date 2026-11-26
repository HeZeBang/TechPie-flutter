import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/feature.dart';
import 'package:techpie/services/usage_telemetry.dart';

class _LoopbackNetwork extends HttpOverrides {}

/// Run from the repository root with Flutter and Python 3 on PATH.
void main() {
  test('Flutter client submits every registered feature and produces a durable report', () async {
    final python = Platform.isWindows ? 'python' : 'python3';
    final directory = await Directory.systemTemp.createTemp('techpie-metrics-');
    addTearDown(() => directory.delete(recursive: true));
    final cli = ['tools/telemetry/telemetry.py', '--db', '${directory.path}/metrics.sqlite'];
    final server = await Process.start(python, [...cli, 'serve', '--port', '0']);
    addTearDown(() async {
      server.kill();
      await server.exitCode;
    });
    final started =
        await server.stdout.transform(utf8.decoder).transform(const LineSplitter()).first;
    expect(started, startsWith('Listening at 127.0.0.1:'));
    final endpoint = Uri.parse('http://${started.substring('Listening at '.length)}');
    SharedPreferences.setMockInitialValues({});
    final features = {
      ...featureEntries.map((e) => e.id),
      'home',
      'schedule',
      'deadlines',
      'settings',
      'campus_services',
      'feedback',
      'more',
    };
    await HttpOverrides.runWithHttpOverrides(
      () async {
        final metrics = UsageTelemetry(
          await SharedPreferences.getInstance(),
          endpoint: endpoint,
          version: '1.1.0+32',
          platform: 'linux',
          existingInstall: false,
        );
        addTearDown(metrics.dispose);
        await metrics.setEnabled(true);
        metrics.firstLogin();
        for (final feature in features) {
          metrics.featureOpened(feature);
        }
        metrics.beginFeedback()!
          ..feedbackAttempt()
          ..feedbackResult(false)
          ..feedbackAttempt()
          ..feedbackResult(true);
        metrics.beginRecording()!
          ..recordingReady()
          ..recordingExit();
        await metrics.flush();
      },
      _LoopbackNetwork(),
    );
    final result = await Process.run(python, [...cli, 'report']);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final report = jsonDecode(result.stdout as String);
    expect(report['adoption']['participating_first_launches'], 1);
    expect(report['adoption']['active_installations_30d'], 1);
    expect(report['adoption']['first_login_cohorts'].single['first_login_within_7d'], 1);
    expect(
      (report['daily_features'] as List).map((row) => row['feature']),
      unorderedEquals(features),
    );
    expect(report['feedback']['forms_delivered'], 1);
    expect(report['feedback']['failed_submission_responses'], 1);
    expect(report['recordings']['all']['early_exits_by_state']['ready_only'], 1);
  });
}
