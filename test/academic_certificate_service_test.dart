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
    '<textarea title="申请理由" name="stdPrinterApply.applyReason"></textarea><input type="hidden" name="stdPrinterApply.id" value="">'
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
  testWidgets('average certificate opens a blank school form and saves only on confirmation',
      (tester) async {
    const list = """
      <script>var action=bar.addEntityAction('stdAverageApply',page_grid123);
      bar.addItem("申请",action.add());</script>
      <table><tr><th>申请理由</th><th>申请时间</th></tr></table>""";
    const editor = '''
      <form action="/eams/stdAverageApply!save.action" method="post">
      <input type="hidden" name="params" value="from-school">
      <textarea name="stdAverageApply.applyReason" title="申请理由"></textarea>
      <input type="hidden" name="stdAverageApply.id" value="">
      </form>''';
    final k = CertificateKind.average;
    expect(parseCertificateForm(k, editor.replaceFirst('value=""', 'value="42"')), isNull);
    var showApply = true;
    var saves = 0;
    final f = CampusFixture('https://eams.shanghaitech.edu.cn', (r) {
      if (!r.uri.path.startsWith(k.path)) return respond('暂无申请记录');
      if (r.uri.path == '${k.path}.action') return respond('');
      expect(r.method, 'POST');
      if (r.uri.path == '${k.path}!search.action') {
        return respond(showApply ? list : list.replaceFirst('action.add()', 'action.remove()'));
      }
      if (r.uri.path == '${k.path}!edit.action') {
        expect(r.data, {'stdAverageApply.id': ''});
        return respond(editor);
      }
      expect(r.uri.path, k.submitPath);
      expect(r.data, {
        'stdAverageApply.applyReason': '用于实习',
        'stdAverageApply.id': '',
        'params': 'from-school',
      });
      saves++;
      return respond('<div class="success">申请已提交</div>');
    });
    SharedPreferences.setMockInitialValues({});
    final s = AcademicCertificateService(
      EamsClient(f.session, minInterval: Duration.zero),
      StorageService(await SharedPreferences.getInstance()),
      ValueNotifier(0),
      ValueNotifier(0),
    );
    addTearDown(s.dispose);
    await tester.pumpWidget(MaterialApp(home: AcademicCertificatesPage(service: s)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(k.label));
    await tester.pumpAndSettle();
    expect(s.canApply(k), isTrue);
    expect(s.forms, isEmpty);
    Future<void> review() async {
      await tester.tap(find.text('新申请'));
      await tester.pumpAndSettle();
      expect(find.text('申请理由'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '用于实习');
      await tester.tap(find.text('核对申请'));
      await tester.pumpAndSettle();
      expect(find.text('申请理由 · 用于实习'), findsOneWidget);
      expect(saves, 0);
    }

    await review();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(saves, 0);
    await review();
    final form = s.forms[k]!;
    expect(form.fields.single.multiline, isTrue);
    showApply = false;
    await tester.tap(find.text('确认提交'));
    await tester.pumpAndSettle();
    expect(s.canApply(k), isFalse);
    await expectLater(s.apply(k, form, {}), throwsFormatException);
    expect(saves, 1);
  });
  test('transcript requires a language and submits the school option value without reset controls',
      () {
    final k = CertificateKind.transcript;
    final form = parseCertificateForm(k, '''
      <form action="${k.submitPath}" method="post">
      <input type="hidden" name="params" value="from-school">
      <select title="成绩单类型" name="stdPrinterApply.type">
      <option value="0">...</option><option value="zh">中文</option><option value="en">英文</option></select>
      <textarea title="申请理由" name="stdPrinterApply.applyReason"></textarea>
      <input type="hidden" name="stdPrinterApply.id" value="">
      <input type="reset" name="gradeBatchReset">
      </form>''')!;
    expect(() => form.values({}), throwsFormatException);
    expect(() => form.values({'stdPrinterApply.type': '0'}), throwsFormatException);
    expect(form.values({'stdPrinterApply.type': 'en'}), {
      'stdPrinterApply.type': 'en',
      'stdPrinterApply.applyReason': '',
      'stdPrinterApply.id': '',
      'params': 'from-school',
    });
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
    expect(form.values({'lang': 'en', 'injected': 'no'}), {
      'lang': 'en',
      'token': 'fixture',
      'stdPrinterApply.id': '',
      'stdPrinterApply.applyReason': '',
    });
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
        '<form action="${rank.submitPath}">'
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
    final beangleForm = parseCertificateForm(rank, beangleFormHtml)!;
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
