import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/services/campus/campus_errors.dart';
import 'package:techpie/services/campus/elearning_client.dart';
import 'package:techpie/services/elearning_service.dart';

import 'campus/campus_fixture.dart';

const origin = 'https://elearning.shanghaitech.edu.cn:8443';
const stream = '/webapps/bb-mygrades-BBLEARN/myGrades';
const receiptPath = '/webapps/gradebook/do/instructor/viewAttemptReceipts';
const receiptLink = '$receiptPath?course_id=course-A&amp;user_id=student&amp;is_stream=yes';
String counter(String count, {String href = receiptLink}) =>
    '<div id="submissionReceipts"><a href="$href">$count</a></div>';
const detail = '''
<table id="listContainer_datatable">
<thead><tr><th>确认编号</th><th>提交者</th><th>课程作业</th><th>日期</th><th>提交</th><th>大小</th></tr></thead>
<tbody><tr><th>sample-confirmation</th><td>Student Fixture</td><td>Practice report</td>
<td>2024-01-03</td><td>example.pdf</td><td>1 KB</td></tr></tbody></table>
''';

void main() {
  test('uses the student link and reads the receipt number from its row header', () async {
    final fixture = CampusFixture(origin, (request) {
      expect(request.method, 'GET');
      if (request.uri.path == stream) {
        expect(request.uri.queryParameters, {'course_id': 'course-A', 'stream_name': 'mygrades'});
        return respond(counter('2'));
      }
      expect(request.uri.toString(), '$origin${receiptLink.replaceAll('&amp;', '&')}');
      return respond(detail);
    });
    final result =
        await ElearningService(ElearningClient(fixture.session)).submissionReceipts('course-A');
    final receipt = result.receipts.single;
    expect(result.total, 2);
    expect(
      [receipt.number, receipt.assignment, receipt.date, receipt.submission, receipt.size],
      ['sample-confirmation', 'Practice report', '2024-01-03', 'example.pdf', '1 KB'],
    );
    expect(fixture.requests.length, 2);
  });

  test('zero is read from the course counter without opening receipt details', () async {
    final fixture = CampusFixture(origin, (_) => respond(counter('0')));
    final page =
        await ElearningService(ElearningClient(fixture.session)).submissionReceipts('course-A');
    expect(page.receipts, isEmpty);
    expect(page.total, 0);
    expect(fixture.requests.length, 1);
  });

  test('does not follow links outside the student course and receipt handler', () async {
    for (final href in [
      'https://example.org$receiptLink',
      receiptLink.replaceFirst('course-A', 'course-B'),
      receiptLink.replaceFirst('user_id=student', 'another=field'),
      receiptLink.replaceFirst(receiptPath, '/not-a-receipt'),
    ]) {
      final fixture = CampusFixture(origin, (_) => respond(counter('1', href: href)));
      await expectLater(
        ElearningService(ElearningClient(fixture.session)).submissionReceipts('course-A'),
        fails(CampusErrorKind.parseFailed),
      );
      expect(fixture.requests.length, 1);
    }
  });

  test('missing counter, missing user and a malformed result never become an empty list', () async {
    for (final pair in [
      ('<p>课程不可用</p>', ''),
      (counter('1'), '<h2>提交确认</h2><h3>找不到用户</h3>'),
      (counter('1'), detail.replaceFirst('<th>sample-confirmation</th>', '<th></th>')),
      (counter('1'), detail.replaceFirst('课程作业', '未知字段')),
    ]) {
      final fixture = CampusFixture(
        origin,
        (request) => respond(request.uri.path == stream ? pair.$1 : pair.$2),
      );
      await expectLater(
        ElearningService(ElearningClient(fixture.session)).submissionReceipts('course-A'),
        fails(CampusErrorKind.parseFailed),
      );
    }
  });
}
