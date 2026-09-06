import 'dart:convert';

import 'package:flutter/services.dart';

const String elrcCourseCatalogAsset = 'assets/config/elrc_courses.json';
const String _elrcHost = 'elrc.shanghaitech.edu.cn';
final RegExp _safeCourseId = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

class ElrcCourse {
  const ElrcCourse({
    required this.name,
    required this.id,
    this.courseNo,
    this.reviewId,
    this.schoolYear,
    this.semester,
    this.classNo,
    this.term,
  });

  final String name;
  final String id;
  final String? courseNo;
  final String? reviewId;
  final String? schoolYear;
  final String? semester;
  final String? classNo;
  final String? term;

  String get key => jsonEncode([id, reviewId, schoolYear, semester]);
  String get description =>
      [courseNo, classNo, term].whereType<String>().where((part) => part.isNotEmpty).join(' · ');

  Uri get recordingUri {
    final parameters = {
      if (reviewId != null) 'id': reviewId!,
      if (schoolYear != null) 'schoolYear': schoolYear!,
      if (semester != null) 'semester': semester!,
      if (courseNo != null) 'courseNo': courseNo!,
    };
    return Uri.https(
      _elrcHost,
      '/learn/videoreview/$id',
      parameters.isEmpty ? null : parameters,
    );
  }
}

List<ElrcCourse> parseElrcCourseCatalog(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! List) {
    throw const FormatException('ELRC 课程清单必须是 JSON 数组。');
  }

  final courses = <ElrcCourse>[];
  final ids = <String>{};
  for (var index = 0; index < decoded.length; index++) {
    final item = decoded[index];
    if (item is! Map) {
      throw FormatException('ELRC 课程清单第 ${index + 1} 项必须是对象。');
    }

    final name = item['name'] is String ? (item['name'] as String).trim() : '';
    final id = item['id'] is String ? (item['id'] as String).trim() : '';
    if (name.isEmpty) {
      throw FormatException('ELRC 课程清单第 ${index + 1} 项缺少 name。');
    }
    if (!_safeCourseId.hasMatch(id)) {
      throw FormatException('ELRC 课程“$name”的 id 格式不合法。');
    }
    String? optionalParameter(String key) {
      final value = item[key];
      if (value == null) {
        return null;
      }
      if (value is! String ||
          value.trim().isEmpty ||
          value.length > 128 ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
        throw FormatException('ELRC 课程清单第 ${index + 1} 项的 $key 格式不合法。');
      }
      return value.trim();
    }

    final course = ElrcCourse(
      name: name,
      id: id,
      courseNo: optionalParameter('courseNo'),
      reviewId: optionalParameter('reviewId'),
      schoolYear: optionalParameter('schoolYear'),
      semester: optionalParameter('semester'),
      classNo: optionalParameter('classNo'),
      term: optionalParameter('term'),
    );
    if (!ids.add(course.key)) {
      throw FormatException('ELRC 课程开课记录重复：$id');
    }
    courses.add(course);
  }

  return List<ElrcCourse>.unmodifiable(courses);
}

Future<List<ElrcCourse>> loadElrcCourseCatalog({
  AssetBundle? bundle,
}) async {
  final source = await (bundle ?? rootBundle).loadString(elrcCourseCatalogAsset);
  return parseElrcCourseCatalog(source);
}
