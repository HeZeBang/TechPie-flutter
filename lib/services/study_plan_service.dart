import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../models/study_plan.dart';
import 'campus/eams_client.dart';
import 'storage_service.dart';
import 'study_plan_parser.dart';

class StudyPlanService extends ChangeNotifier {
  StudyPlanService(this.eams, this.storage, this.account, this.changes) {
    changes.addListener(_changed);
    _restore();
  }
  final EamsClient eams;
  final StorageService storage;
  final ({String? user, String? ids}) Function() account;
  final Listenable changes;
  String? _owner;
  int _generation = 0;
  int get accountRevision => _generation;
  final _plans = <bool, StudyPlanSnapshot>{};
  final _pending = <bool, Future<StudyPlanSnapshot>>{};
  Map<String, String>? _exportFormFields;
  StudyPlanSnapshot? cached({required bool full}) => _plans[full];
  String? get _current {
    final id = account();
    return id.user?.isNotEmpty != true || id.ids?.isNotEmpty != true
        ? null
        : jsonEncode([id.user, id.ids]);
  }

  void _restore() {
    _owner = _current;
    for (final full in [false, true]) {
      final entry = storage.studyPlanCache(full);
      if (entry == null) continue;
      if (_owner != null && entry['owner'] == _owner) {
        try {
          _plans[full] = StudyPlanSnapshot.fromJson(entry['snapshot'] as Map<String, dynamic>);
        } catch (_) {
          unawaited(storage.clearStudyPlanCache(full));
        }
      } else if (_owner != null) {
        unawaited(storage.clearStudyPlanCache(full));
      }
    }
  }

  void _changed() {
    if (_current == _owner) return;
    _generation++;
    if (_owner != null) {
      for (final full in [false, true]) {
        unawaited(storage.clearStudyPlanCache(full));
      }
    }
    _pending.clear();
    _plans.clear();
    _exportFormFields = null;
    _restore();
    notifyListeners();
  }

  void _check(int revision) {
    if (_current == null) throw const FormatException('请先登录并绑定 IDS');
    if (revision != _generation || _owner != _current) throw const FormatException('学校账号已切换');
  }

  Future<StudyPlanSnapshot> load({bool full = false, bool refresh = false}) {
    final existing = _plans[full];
    if (!refresh && existing != null) return Future.value(existing);
    final generation = _generation;
    return _pending.putIfAbsent(full, () async {
      try {
        await Future<void>.value();
        _check(generation);
        final page = await eams.getHtml(full ? '/eams/myPlan.action' : '/eams/myPlanCompl.action');
        _check(generation);
        final exportFields = full ? await compute(_exportFields, page) : null;
        _check(generation);
        var detail = '';
        if (!full && page.contains('compulsoryInfo.action')) {
          final form = await compute(_detailFields, page);
          _check(generation);
          detail = await eams.postForm('/eams/myPlanCompl!compulsoryInfo.action', form);
        }
        final snapshot = await compute(parseStudyPlan, (page: page, detail: detail, full: full));
        _check(generation);
        await storage.saveStudyPlanCache(full, {'owner': _owner, 'snapshot': snapshot.toJson()});
        _check(generation);
        if (exportFields != null) _exportFormFields = exportFields;
        _plans[full] = snapshot;
        notifyListeners();
        return snapshot;
      } finally {
        if (generation == _generation) _pending.remove(full)?.ignore();
      }
    });
  }

  Future<List<int>> exportPdf() async {
    final generation = _generation;
    _check(generation);
    var fields = _exportFormFields;
    if (fields == null) {
      final page = await eams.getHtml('/eams/myPlan.action');
      fields = await compute(_exportFields, page);
      _check(generation);
      _exportFormFields = fields;
    }
    final bytes = await eams.downloadBytes(
      '/eams/myPlan!exportPdf.action',
      method: 'POST',
      form: fields,
    );
    _check(generation);
    if (bytes.length < 5 || ascii.decode(bytes.take(5).toList(), allowInvalid: true) != '%PDF-') {
      throw const FormatException('教务系统未返回 PDF 文件');
    }
    return bytes;
  }

  @override
  void dispose() {
    _generation++;
    changes.removeListener(_changed);
    super.dispose();
  }
}

Map<String, String> _exportFields(String source) => _formFields(source, 'myPlan!exportPdf.action');
Map<String, String> _detailFields(String source) =>
    _formFields(source, 'myPlanCompl!compulsoryInfo.action');
Map<String, String> _formFields(String source, String action) {
  final form = html.parse(source).querySelector('form[action\$="$action"]');
  return {
    for (final input in form?.querySelectorAll('input[type="hidden"][name]') ?? <Element>[])
      input.attributes['name']!: input.attributes['value'] ?? '',
  };
}
