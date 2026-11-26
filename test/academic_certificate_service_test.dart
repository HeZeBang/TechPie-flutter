import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/academic_certificate.dart';
import 'package:techpie/pages/academic_certificates_page.dart';
import 'package:techpie/services/academic_certificate_service.dart';
import 'package:techpie/services/campus/campus_file_share.dart';
import 'package:techpie/services/campus/eams_client.dart';
import 'package:techpie/services/storage_service.dart';

import 'campus/campus_fixture.dart';

String rows(CertificateKind k) => '<table><tr><th>申请 时间</th><th>审核 状态</th><th>学号</th><th>操作</th></tr>'
    '<tr><td>2026-01-01</td><td>通过</td><td>Private</td><td><a href="${k.path}!downloadAttachment.action?id=42">下载</a>'
    '<a href="https://external.invalid${k.path}!downloadAttachment.action?id=42">other</a></td></tr></table>';
final formHtml =
    '<form action="${CertificateKind.transcript.submitPath}" method="post"><input type="hidden" name="token" value="fixture">'
    '<label for="kind">语言</label><select id="kind" name="lang" required><option value="">请选择</option><option value="en">英文</option></select></form>';
void main() {
  test('a session renewal after a confirmed write never replays the POST', () async {
    final f = CampusFixture(
      'https://eams.shanghaitech.edu.cn',
      (r) => respond('<input name="execution">'),
    );
    final client = EamsClient(f.session, minInterval: Duration.zero);
    await expectLater(
      client.submitFormOnce('/eams/submit.action', {'choice': 'one'}),
      throwsException,
    );
    expect(f.requests.where((r) => r.method == 'POST'), hasLength(1));
  });
  test('a 307 cannot submit the same application to a second path', () async {
    final f = CampusFixture(
      'https://eams.shanghaitech.edu.cn',
      (r) => respond(
        '',
        status: 307,
        headers: {
          'location': ['/eams/another.action'],
        },
      ),
    );
    final client = EamsClient(f.session, minInterval: Duration.zero);
    await expectLater(client.submitFormOnce('/eams/submit.action', {}), throwsException);
    expect(f.requests, hasLength(1));
  });
  test('extracts display fields, radios, Beangle labels and onclick actions', () {
    for (final k in CertificateKind.values) {
      final row = parseCertificates(k, rows(k)).single;
      expect(row.fields, {'申请时间': '2026-01-01', '审核状态': '通过'});
      expect(row.downloads.length, k == CertificateKind.transcript ? 1 : 0);
    }
    final transcript = CertificateKind.transcript;
    final withForm = rows(transcript).replaceFirst(
      RegExp(r'<a href="[^"]+">下载</a>'),
      '<form action="${transcript.path}!downloadAttachment.action" method="get">'
      '<input type="hidden" name="record" value="42"></form>',
    );
    final download = parseCertificates(transcript, withForm).single.downloads.single;
    expect(Uri.parse(download.url).queryParameters, {'record': '42'});

    // Support onclick downloads and deduplicate against identical href downloads.
    final rank = CertificateKind.ranking;
    final onclickHtml =
        '<table><tr><th>申请时间</th><th>审核状态</th><th>操作</th></tr>'
        '<tr><td>2026-01-02</td><td>完成</td><td>'
        '<a href="${rank.path}!departPrint.action?id=7">打印</a>'
        '<a href="javascript:void(0)" onclick="bg.go(\'${rank.path}!departPrint.action?id=7\')">同链接</a>'
        '<button onclick="bg.go(\'${rank.path}!majorPrint.action?id=7\')">专业</button>'
        '</td></tr></table>';
    final rankDownloads = parseCertificates(rank, onclickHtml).single.downloads;
    expect(rankDownloads, hasLength(2));
    expect(rankDownloads.map((d) => d.method), ['POST', 'POST']);
    expect(rankDownloads.map((d) => d.fields['id']), ['7', '7']);

    final form = parseCertificateForm(CertificateKind.transcript, formHtml)!;
    expect(() => form.values({'lang': 'foo'}), throwsFormatException);
    expect(form.values({'lang': 'en', 'injected': 'no'}), {'lang': 'en', 'token': 'fixture'});
    expect(parseCertificateForm(CertificateKind.average, formHtml), isNull);
    expect(
      parseCertificateForm(
        CertificateKind.transcript,
        formHtml.replaceFirst('<select', '<select multiple'),
      ),
      isNull,
    );

    // Beangle table labels, omitted method, named submit button, and radio groups.
    final beangleFormHtml =
        '<form action="${CertificateKind.transcript.submitPath}">'
        '<table>'
        '<tr><td class="title">打印类型：</td><td>'
        '<select name="type"><option value="zh" selected>中文</option><option value="en">英文</option></select>'
        '</td></tr>'
        '<tr><td>排名方式：</td><td>'
        '<input type="radio" id="r1" name="mode" value="1" checked><label for="r1">百分制</label>'
        '<input type="radio" id="r2" name="mode" value="2"><label for="r2">四分制</label>'
        '</td></tr>'
        '</table>'
        '<button type="submit" name="submitBtn">提交</button>'
        '</form>';
    final beangleForm = parseCertificateForm(CertificateKind.transcript, beangleFormHtml)!;
    expect(beangleForm.fields.map((f) => f.label), ['打印类型', '排名方式']);
    expect(beangleForm.fields[1].options, {'1': '百分制', '2': '四分制'});
    expect(beangleForm.values({}), {'type': 'zh', 'mode': '1'});

    final printed =
        parseCertificates(rank, rows(rank).replaceFirst('downloadAttachment', 'majorPrint'))
            .single
            .downloads
            .single;
    expect(printed.method, 'POST');
    expect(printed.fields, {'id': '42'});
  });

  test(
      'submits a confirmed form once, rejects server errors and non-PDF downloads, restores and clears cache',
      () async {
    var writes = 0;
    var serverReply = '<div class="error">申请次数已满</div>';
    final kind = CertificateKind.transcript;
    final f = CampusFixture('https://eams.shanghaitech.edu.cn', (r) {
      if (r.uri.path == kind.submitPath) {
        writes++;
        return respond(serverReply);
      }
      if (r.uri.path.endsWith('!search.action')) return respond(rows(kind));
      if (r.uri.path.endsWith('!downloadAttachment.action')) return respond('login needed');
      return respond(formHtml);
    });
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    final auth = ValueNotifier(0), ids = ValueNotifier(0);
    final s = AcademicCertificateService(
      EamsClient(f.session, minInterval: Duration.zero),
      storage,
      auth,
      ids,
    );
    addTearDown(s.dispose);
    await s.refresh(kind);
    await expectLater(s.pdf(s.records[kind]!.single.downloads.single), throwsFormatException);
    await expectLater(
      s.apply(kind, s.forms[kind]!, {'lang': 'en'}),
      throwsA(isA<FormatException>().having((e) => e.message, 'reason', '申请次数已满')),
    );
    expect(writes, 1);

    // Beangle .actionError and failure .message are also surfaced as errors.
    serverReply = '<div class="actionError">申请频率超限</div>';
    await expectLater(
      s.apply(kind, s.forms[kind]!, {'lang': 'en'}),
      throwsA(isA<FormatException>().having((e) => e.message, 'reason', '申请频率超限')),
    );
    serverReply = '<div class="message">操作失败，请联系教务处</div>';
    await expectLater(
      s.apply(kind, s.forms[kind]!, {'lang': 'en'}),
      throwsA(isA<FormatException>().having((e) => e.message, 'reason', '操作失败，请联系教务处')),
    );

    final offline = AcademicCertificateService(s.eams, storage, auth, ids);
    addTearDown(offline.dispose);
    expect(offline.records[kind]!.single.downloads, isEmpty);
    expect(offline.forms, isEmpty);

    await storage.clearCampusCaches();
    expect(storage.academicCertificateCache('["user","bound"]', kind.name), isNull);

    await storage.saveAcademicCertificateCache('["user","bound"]', kind.name, '[]');
    f.identity = (user: 'other', ids: 'other');
    ids.value++;
    expect(offline.records, isEmpty);
    expect(storage.academicCertificateCache('["user","bound"]', kind.name), isNull);
  });

  testWidgets('AcademicCertificatesPage opens PDF via shared CampusFileShare', (tester) async {
    final kind = CertificateKind.transcript;
    final f = CampusFixture('https://eams.shanghaitech.edu.cn', (r) {
      if (r.uri.path.endsWith('!search.action')) return respond(rows(kind));
      if (r.uri.path.endsWith('!downloadAttachment.action')) {
        return respond([0x25, 0x50, 0x44, 0x46, 0x2d, 0x31, 0x2e, 0x34]);
      }
      return respond(formHtml);
    });
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    final auth = ValueNotifier(0), ids = ValueNotifier(0);
    final s = AcademicCertificateService(
      EamsClient(f.session, minInterval: Duration.zero),
      storage,
      auth,
      ids,
    );
    addTearDown(s.dispose);

    String? sharedScope;
    String? sharedName;
    await tester.pumpWidget(
      MaterialApp(
        home: AcademicCertificatesPage(
          service: s,
          onShareFile: ({
            required scope,
            required filename,
            required bytes,
            mimeType,
            preferShare = false,
          }) async {
            sharedScope = scope;
            sharedName = filename;
            return const CampusFileOpenResult(status: CampusFileOpenStatus.opened);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('成绩单 PDF'));
    await tester.pumpAndSettle();
    expect(sharedScope, 'certificates');
    expect(sharedName, 'certificate-transcript.pdf');
  });
}
