import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/services/campus/campus_errors.dart';
import 'package:techpie/services/campus/emap_client.dart';
import 'package:techpie/services/student_leave_attachments.dart';

import 'campus/campus_fixture.dart';

const origin = 'https://egate.shanghaitech.edu.cn';
const files = [
  LeaveAttachmentFile('first.JPG', [1, 2, 3]),
  LeaveAttachmentFile('second.pdf', [4, 5]),
];

void main() {
  for (final courseProof in [false, true]) {
    test('persists and reads back all ${courseProof ? 'course' : 'ordinary'} evidence in order',
        () async {
      final checked = <String>[];
      final uploaded = <String>[];
      late String scope, token;
      final fixture = CampusFixture(origin, (r) {
        final path = r.uri.path;
        if (path.contains('getAppConfig')) return respond({});
        expect(path, startsWith('/xsfw/sys/emapcomponent/file/'));
        expect(r.method, 'POST');
        if (path.endsWith('/uploadTempFile.do')) {
          final multipart = r.data as FormData;
          final fields = Map.fromEntries(multipart.fields);
          scope = fields['scope']!;
          token = fields['fileToken']!;
          expect(token, '${scope}1');
          expect(token, matches(RegExp(r'^\d{15,16}$')));
          expect(fields['storeId'], 'file');
          expect(fields['size'], courseProof ? '0' : '5120');
          expect(fields['type'], courseProof ? '' : StudentLeaveAttachments.extensions.join(','));
          expect(multipart.files.single.key, courseProof ? 'files[]' : 'bhFile');
          uploaded.add(multipart.files.single.value.filename!);
          return respond({'success': true, 'id': 'id${uploaded.length}'});
        }
        final form = r.data as Map<String, String>;
        if (path.endsWith('/tempFileCheck.do')) {
          checked.add(form['fileId']!);
          expect(form['scope'], scope);
          expect(form['fileToken'], token);
          return respond({'check': true});
        }
        if (path.contains('/saveAttachment/')) {
          expect(path, endsWith('/$scope/$token.do'));
          final params = jsonDecode(form['attachmentParam']!) as Map;
          expect(params['orderMap'], {'id1': 1, 'id2': 2});
          expect(params['storeId'], 'file');
          expect((courseProof ? form : params)['fileToken'], token);
          expect((courseProof ? form : params)['scope'], scope);
          expect((courseProof ? params : form).containsKey('scope'), isFalse);
          return respond({'success': true, 'successCount': 2});
        }
        if (courseProof) {
          expect(path, endsWith('/getUploadedAttachment.do'));
          expect(form, {'fileToken': token});
        } else {
          expect(path, endsWith('/getUploadedAttachment/$token.do'));
          expect(form, isEmpty);
        }
        return respond({
          'success': true,
          'items': [
            {'id': 'id2'},
            {'id': 'id1'},
          ],
        });
      });
      final attachments = StudentLeaveAttachments(EmapClient(fixture.session));
      expect(
        await attachments.persist(files, courseProof: courseProof, checkAccount: () {}),
        token,
      );
      expect(uploaded, ['first.JPG', 'second.pdf']);
      expect(checked, courseProof ? isEmpty : ['id1', 'id2']);
    });
  }

  test('validates all selected files before uploading the first one', () async {
    final f = CampusFixture(origin, (_) => fail('Unexpected request'));
    final a = StudentLeaveAttachments(EmapClient(f.session));
    expect(await a.persist([], courseProof: false, checkAccount: () {}), '');
    for (final file in [
      const LeaveAttachmentFile('invalid.exe', [0]),
      const LeaveAttachmentFile('folder/first.png', [0]),
      LeaveAttachmentFile('huge.png', List.filled(StudentLeaveAttachments.maxProofBytes + 1, 0)),
    ]) {
      await expectLater(
        a.persist([files.first, file], courseProof: false, checkAccount: () {}),
        fails(CampusErrorKind.rejected),
      );
    }
    expect(f.requests, isEmpty);
  });

  test('does not return an attachment token for a false check or a different saved file', () async {
    var validCheck = false;
    final f = CampusFixture(origin, (r) {
      if (r.uri.path.endsWith('/uploadTempFile.do')) {
        return respond({'success': true, 'id': 'file'});
      }
      if (r.uri.path.endsWith('/tempFileCheck.do')) return respond({'check': validCheck});
      if (r.uri.path.contains('/saveAttachment/')) return respond({'success': true});
      if (r.uri.path.contains('/getUploadedAttachment/')) {
        return respond({
          'success': true,
          'items': [
            {'id': 'another'},
          ],
        });
      }
      return respond({});
    });
    final a = StudentLeaveAttachments(EmapClient(f.session));
    Future<String> upload() => a.persist([files.first], courseProof: false, checkAccount: () {});
    await expectLater(upload(), fails(CampusErrorKind.rejected));
    expect(f.requests.any((r) => r.uri.path.contains('/saveAttachment/')), isFalse);
    validCheck = true;
    await expectLater(upload(), fails(CampusErrorKind.rejected));
  });

  test('stops on account change before persisting a temporary attachment', () async {
    var switched = false;
    final f = CampusFixture(origin, (r) {
      if (r.uri.path.endsWith('uploadTempFile.do')) {
        switched = true;
        return respond({'success': true, 'id': 'old-account-file'});
      }
      return respond({});
    });
    final a = StudentLeaveAttachments(EmapClient(f.session));
    await expectLater(
      a.persist(
        files,
        courseProof: true,
        checkAccount: () {
          if (switched) throw CampusRequestException.expired;
        },
      ),
      fails(CampusErrorKind.sessionExpired),
    );
    expect(f.requests.last.uri.path, endsWith('/uploadTempFile.do'));
  });

  for (final code in [401, 403, 307, 308]) {
    test('does not replay a multipart upload after HTTP $code', () async {
      final f = CampusFixture(origin, (r) {
        if (r.uri.path.contains('/getAppConfig/')) return respond({});
        return respond(
          '',
          status: code,
          headers: {
            if (code == 307 || code == 308) 'location': ['/xsfw/sys/emapcomponent/file/again.do'],
          },
        );
      });
      final a = StudentLeaveAttachments(EmapClient(f.session));
      await expectLater(
        a.persist(files, courseProof: false, checkAccount: () {}),
        throwsA(isA<CampusRequestException>()),
      );
      expect(f.requests.where((r) => !r.uri.path.contains('/getAppConfig/')), hasLength(1));
    });
  }
}
