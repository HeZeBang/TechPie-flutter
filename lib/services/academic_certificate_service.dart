import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html;

import '../models/academic_certificate.dart';
import 'campus/campus_errors.dart';
import 'campus/eams_client.dart';
import 'storage_service.dart';

class AcademicCertificateService extends ChangeNotifier {
  AcademicCertificateService(this.eams, this.storage, this.auth, this.ids) {
    auth.addListener(_account);
    ids.addListener(_account);
    _account();
  }
  final EamsClient eams;
  final StorageService storage;
  final Listenable auth, ids;
  String? _owner;
  bool get ready => _owner != null;
  int generation = 0;
  final records = <CertificateKind, List<AcademicCertificate>>{};
  final forms = <CertificateKind, CertificateForm>{};
  void _account() {
    final id = eams.session.identity();
    final owner = (id.user?.isNotEmpty == true && id.ids?.isNotEmpty == true)
        ? jsonEncode([id.user, id.ids])
        : null;
    if (_owner == owner) return;
    if (_owner != null) unawaited(storage.clearAcademicCertificateCache(_owner!));
    _owner = owner;
    generation++;
    records.clear();
    forms.clear();
    if (owner != null) {
      for (final k in CertificateKind.values) {
        final raw = storage.academicCertificateCache(owner, k.name);
        if (raw == null) continue;
        try {
          records[k] = (jsonDecode(raw) as List)
              .map((v) => AcademicCertificate(Map<String, String>.from(v as Map)))
              .toList();
        } on FormatException {
          continue;
        } on TypeError {
          continue;
        }
      }
    }
    notifyListeners();
  }

  Future<void> refresh(CertificateKind kind) async {
    final owner = _owner;
    if (owner == null) {
      throw const CampusRequestException(CampusErrorKind.idsNotBound, '请登录并绑定学校账号');
    }
    final version = generation;
    final index = await eams.getHtml('${kind.path}.action');
    if (version != generation) return;
    final data = await eams.postForm('${kind.path}!search.action', {});
    if (version != generation) return;
    final list = parseCertificates(kind, data);
    final form = parseCertificateForm(kind, index) ?? parseCertificateForm(kind, data);
    await storage.saveAcademicCertificateCache(
      owner,
      kind.name,
      jsonEncode(list.map((r) => r.fields).toList()),
    );
    if (version != generation) return;
    records[kind] = list;
    forms.remove(kind);
    if (form != null) forms[kind] = form;
    notifyListeners();
  }

  Future<String> apply(
    CertificateKind kind,
    CertificateForm form,
    Map<String, String> input,
  ) async {
    if (!identical(form, forms[kind])) throw const FormatException('表单已更新，请刷新后重试');
    final result = await eams.submitFormOnce(form.action, form.values(input));
    final document = html.parse(result);
    final error = document
        .querySelector('.error,.alert-danger,.fieldError,.errorMessage,.actionError,#error,.error_msg')
        ?.text
        .trim();
    if (error != null && error.isNotEmpty) throw FormatException(error);
    final message =
        document.querySelector('.success,.alert-success,.message,.tip')?.text.trim();
    if (message != null &&
        message.isNotEmpty &&
        RegExp(r'操作失败|申请失败|提交失败').hasMatch(message)) {
      throw FormatException(message);
    }
    return message != null && message.isNotEmpty ? message : '请求已发送，请在申请记录中核对结果';
  }

  Future<List<int>> pdf(CertificateDownload d) async {
    final bytes = await eams.downloadBytes(
      d.url,
      method: d.method,
      form: d.method == 'POST' ? d.fields : null,
    );
    if (bytes.length < 5 || ascii.decode(bytes.take(5).toList(), allowInvalid: true) != '%PDF-') {
      throw const FormatException('教务系统未返回 PDF 文件');
    }
    return bytes;
  }

  @override
  void dispose() {
    generation++;
    auth.removeListener(_account);
    ids.removeListener(_account);
    super.dispose();
  }
}
