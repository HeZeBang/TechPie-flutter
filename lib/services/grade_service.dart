import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html;

import '../models/grade_record.dart';
import 'auth_service.dart';
import 'campus/campus_errors.dart';
import 'campus/eams_client.dart';
import 'storage_service.dart';
import 'third_party_auth_service.dart';

enum GradeScope {
  major('主修', 'MAJOR'),
  all('全部', ''),
  minor('辅修', 'MINOR');

  const GradeScope(this.label, this.project);
  final String label, project;
}

class GradeService extends ChangeNotifier {
  GradeService(this.eams, this.storage, this.auth, this.bindings) {
    auth.addListener(_accountChanged);
    bindings.addListener(_accountChanged);
    _accountChanged();
  }

  final EamsClient eams;
  final StorageService storage;
  final AuthService auth;
  final ThirdPartyAuthService bindings;
  final _courses = <GradeScope, List<CourseGrade>>{};
  final _updated = <GradeScope, DateTime>{};
  final _english = <String, List<OtherEnglishGrade>>{};
  Map<String, String> semesters = {};
  String? _owner;
  int _generation = 0;
  int get generation => _generation;
  bool get ready => _owner != null;
  List<CourseGrade> courses(GradeScope scope) => _courses[scope] ?? const [];
  DateTime? updated(GradeScope scope) => _updated[scope];
  List<OtherEnglishGrade> english(String term) => _english[term] ?? const [];

  void _accountChanged() {
    final identity = eams.session.identity();
    final user = identity.user ?? '';
    final student = identity.ids ?? '';
    final owner = user.isEmpty || student.isEmpty ? null : jsonEncode([user, student]);
    if (_owner == owner) return;
    if (_owner != null) unawaited(storage.clearGradeCache(_owner!));
    _generation++;
    _owner = owner;
    _courses.clear();
    _updated.clear();
    _english.clear();
    semesters = {};
    if (owner != null) {
      for (final scope in GradeScope.values) {
        final cache = storage.loadGradeCache(owner, scope.name);
        if (cache == null) continue;
        try {
          final data = jsonDecode(cache) as Map<String, dynamic>;
          final records = (data['courses'] as List).cast<Map<String, dynamic>>();
          final date = DateTime.parse(data['updated'] as String);
          _courses[scope] = records.map(CourseGrade.fromJson).toList();
          _updated[scope] = date;
        } on FormatException {
          continue;
        } on TypeError {
          continue;
        }
      }
    }
    notifyListeners();
  }

  Future<void> refresh(GradeScope scope) async {
    final owner = _owner;
    if (owner == null) {
      throw const CampusRequestException(CampusErrorKind.idsNotBound, '请登录并绑定学校账号');
    }
    final generation = _generation;
    const base = '/eams/teach/grade/course/person';
    Future<List<CourseGrade>> fetchTranscript() async {
      final source = await eams.getHtml(
        '$base!historyCourseGrade.action',
        query: {'projectType': scope.project},
      );
      return parseCourseGrades(source);
    }

    late final List<CourseGrade> grades;
    try {
      grades = await fetchTranscript();
    } on CampusRequestException catch (e) {
      if (e.kind != CampusErrorKind.parseFailed || generation != _generation) rethrow;
      await eams.getHtml('$base.action');
      if (generation != _generation) return;
      grades = await fetchTranscript();
    }
    if (generation != _generation) return;
    final date = DateTime.now();
    await storage.saveGradeCache(
      owner,
      scope.name,
      jsonEncode({
        'updated': date.toIso8601String(),
        'courses': grades.map((g) => g.toJson()).toList(),
      }),
    );
    if (generation != _generation) return;
    _courses[scope] = grades;
    _updated[scope] = date;
    notifyListeners();
  }

  Future<void> loadEnglishTerms() async {
    final generation = _generation;
    await eams.getHtml('/eams/myOtherEngGrade.action');
    if (generation != _generation) return;
    final terms = await eams.fetchSemesters();
    if (generation != _generation) return;
    semesters = terms;
    notifyListeners();
  }

  Future<void> loadEnglish(String term) async {
    final generation = _generation;
    final source =
        await eams.getHtml('/eams/myOtherEngGrade!search.action', query: {'semester.id': term});
    if (generation != _generation) return;
    _english[term] = parseEnglishGrades(source, semesters[term] ?? '');
    notifyListeners();
  }

  @override
  void dispose() {
    _generation++;
    auth.removeListener(_accountChanged);
    bindings.removeListener(_accountChanged);
    super.dispose();
  }
}

String _normalizeHeader(String raw) => raw.replaceAll(RegExp(r'\s+'), '');

List<Map<String, String>> _gradeRows(String source, Set<String> titles) {
  final document = html.parse(source);
  final records = <Map<String, String>>[];
  var found = false;
  for (final table in document.querySelectorAll('table')) {
    List<String>? headers;
    for (final row in table.querySelectorAll('tr')) {
      if (row.parent != table && row.parent?.parent != table) continue;
      final rawCells = row.children
          .where((c) => c.localName == 'td' || c.localName == 'th')
          .map((c) => c.text.trim())
          .toList();
      final headerCells = rawCells.map(_normalizeHeader).toList();
      if (headerCells.any(titles.contains)) {
        headers = headerCells;
        found = true;
      } else if (headers != null && rawCells.length >= headers.length) {
        records.add(Map.fromIterables(headers, rawCells.take(headers.length)));
      }
    }
  }
  if (!found && !RegExp('暂无(?:成绩|记录|数据)|没有(?:成绩|记录|数据)').hasMatch(document.body?.text ?? '')) {
    throw CampusRequestException.invalid;
  }
  return records;
}

String _first(Map<String, String> row, List<String> keys) {
  for (final key in keys) {
    final value = row[key];
    if (value != null && value.isNotEmpty && value != '--') return value;
  }
  return '';
}

List<CourseGrade> parseCourseGrades(String source) {
  final result = <CourseGrade>[];
  for (final row in _gradeRows(source, {'课程名称', '课程名'})) {
    final name = _first(row, ['课程名称', '课程名']);
    if (name.isEmpty) continue;
    final score = _first(row, ['最终成绩', '最终', '总评成绩', '课程成绩', '成绩']);
    final point = {'', 'P', 'NP', 'W', 'I', '通过', '不通过', '缓考', '缺考'}.contains(score.toUpperCase())
        ? null
        : double.tryParse(_first(row, ['绩点', '课程绩点']));
    final status = _first(row, ['是否通过', '是否及格']);
    final numericScore = double.tryParse(score);
    final passed = switch (status) {
      '是' || '通过' || '及格' => true,
      '否' || '不通过' || '不及格' => false,
      _ => switch (score.toUpperCase()) {
          'P' || '通过' => true,
          'NP' || 'F' || '不通过' || '不及格' => false,
          'W' || 'I' || '' => null,
          _ => point != null
              ? point > 0
              : numericScore != null
                  ? numericScore >= 60
                  : null,
        },
    };
    result.add(
      CourseGrade(
        semester: {
          _first(row, ['学年学期', '学年']),
          _first(row, ['学期']),
        }.where((s) => s.isNotEmpty).join(' '),
        courseCode: _first(row, ['课程代码', '课程编码']),
        courseName: name,
        courseType: _first(row, ['课程类别', '课程类型']),
        credits: double.tryParse(row['学分'] ?? '') ?? 0,
        scoreText: score,
        gradePoint: point,
        passed: passed,
        isRetake: ['是', '重修', '补考'].contains(_first(row, ['是否重修', '修读类别', '考试性质'])),
      ),
    );
  }
  return result;
}

List<OtherEnglishGrade> parseEnglishGrades(String source, String term) {
  const titles = ['考试名称', '考试类别', '考试类型', '考试项目', '语种'];
  return [
    for (final row in _gradeRows(source, titles.toSet()))
      if (_first(row, titles).isNotEmpty)
        OtherEnglishGrade(
          _first(row, titles),
          _first(row, ['学年学期', '学期']).isEmpty ? term : _first(row, ['学年学期', '学期']),
          _first(row, ['成绩', '考试成绩', '分数']),
          _first(row, ['通过状态', '是否通过', '是否合格']),
        ),
  ];
}
