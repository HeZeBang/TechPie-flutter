import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/services/campus/campus_errors.dart';
import 'package:techpie/services/campus/eams_client.dart';
import 'package:techpie/services/campus/eams_html_parser.dart';

import 'campus_fixture.dart';

const origin = 'https://eams.shanghaitech.edu.cn';
void main() {
  test('coalesces equivalent requests, serializes distinct ones at the default interval', () async {
    final starts = <Duration>[];
    final clock = Stopwatch()..start();
    var running = 0;
    final f = CampusFixture(origin, (r) async {
      starts.add(clock.elapsed);
      expect(++running, 1);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      running--;
      return respond(r.uri.path);
    });
    final c = EamsClient(f.session);
    final values = await Future.wait([
      c.getHtml('/a', query: {'a': '1', 'b': '2'}),
      c.getHtml('/a', query: {'b': '2', 'a': '1'}),
      c.getHtml('/b'),
    ]);
    expect(values, ['/a', '/a', '/b']);
    expect(starts, hasLength(2));
    expect(c.minInterval, const Duration(milliseconds: 1600));
    // Observe adapter entry after the scheduler's cookie lookup and Dio dispatch.
    expect((starts.last - starts.first).inMilliseconds, greaterThanOrEqualTo(1550));
  });

  test('rate notice holds the queue, retries once and leaves it usable', () async {
    var limited = true;
    final clock = Stopwatch()..start();
    final times = <int>[];
    final f = CampusFixture(origin, (r) {
      times.add(clock.elapsedMilliseconds);
      return respond(limited ? '请不要过快点击' : 'ok');
    });
    final c = EamsClient(
      f.session,
      minInterval: Duration.zero,
      retryDelay: const Duration(milliseconds: 80),
    );
    await expectLater(c.postForm('/page', {'choice': 'term'}), fails(CampusErrorKind.rateLimited));
    expect(times, hasLength(2));
    expect(times.last - times.first, greaterThanOrEqualTo(75));
    limited = false;
    expect(await c.getHtml('/page'), 'ok');
    expect(f.renewals, 0);
  });

  test('semesters are cached per account and refresh on demand', () async {
    var term = 0;
    final f = CampusFixture(origin, (r) => respond('<option value="s">Term ${++term}</option>'));
    final c = EamsClient(f.session, minInterval: Duration.zero);
    expect(await c.fetchSemesters(), {'s': 'Term 1'});
    expect(await c.fetchSemesters(), {'s': 'Term 1'});
    expect(await c.fetchSemesters(forceRefresh: true), {'s': 'Term 2'});
    f.identity = (user: 'other', ids: 'other');
    expect(await c.fetchSemesters(), {'s': 'Term 3'});
    expect(f.requests.first.data, {'dataType': 'semester'});
    expect(f.requests.first.uri.path, '/eams/dataQuery.action');
    expect(f.requests.first.method, 'POST');
  });

  test('parses grid columns, selected dictionaries and hidden inputs', () {
    const source =
        '<table class="gridtable"><thead><tr><th>Course</th><th>Grade</th></tr></thead><tbody><tr><td>A &amp; B</td><td> 85 </td></tr></tbody></table>'
        '<select name="terms"><option value="">Choose</option><option value="9">Autumn</option></select>'
        '<select name="other"><option value="8">Other</option></select><input type="hidden" name="formId" value="7">';
    expect(EamsHtmlParser.gridTable(source), [
      {'Course': 'A & B', 'Grade': '85'},
    ]);
    expect(EamsHtmlParser.options(source, name: 'terms'), {'9': 'Autumn'});
    expect(EamsHtmlParser.hiddenInputs(source), {'formId': '7'});
    expect(EamsHtmlParser.isLoginPage('<input name="execution">'), isTrue);
    expect(
      EamsHtmlParser.isLoginPage('<a href="https://ids.shanghaitech.edu.cn/">Support</a>'),
      isFalse,
    );
  });

  test('CAS redirects trigger cookie renewal, then JSON and binary data are readable', () async {
    final f = CampusFixture(origin, (r) {
      if (r.headers['Cookie'] == 'SESSION=v0') {
        return respond(
          '',
          status: 302,
          headers: {
            'location': ['https://ids.shanghaitech.edu.cn/authserver/login'],
          },
        );
      }
      return r.method == 'POST' ? respond([0, 255]) : respond({'ok': true});
    });
    final c = EamsClient(f.session, minInterval: Duration.zero);
    expect(await c.getJson('/eams/example'), {'ok': true});
    expect(f.renewals, 1);
    expect(await c.downloadBytes('/eams/file', method: 'POST', form: {'type': 'pdf'}), [0, 255]);
    expect(f.requests.every((r) => r.uri.origin == origin), isTrue);
  });

  test('account change discards an in-flight reply and a queued request', () async {
    final started = Completer<void>();
    final release = Completer<ResponseBody>();
    final f = CampusFixture(origin, (r) {
      started.complete();
      return release.future;
    });
    final c = EamsClient(f.session, minInterval: Duration.zero);
    final first = c.getHtml('/one');
    await started.future;
    final second = c.getHtml('/two');
    await Future<void>.delayed(Duration.zero);
    final checks = Future.wait([
      expectLater(first, fails(CampusErrorKind.sessionExpired)),
      expectLater(second, fails(CampusErrorKind.sessionExpired)),
    ]);
    f.identity = (user: 'new', ids: 'new');
    release.complete(respond('old account data'));
    await checks;
    expect(f.requests, hasLength(1));
  });
}
