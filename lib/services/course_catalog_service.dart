import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:html/parser.dart' as html;

import '../models/catalog_course.dart';
import 'campus/campus_errors.dart';
import 'campus/eams_client.dart';
import 'campus/eams_html_parser.dart';
import 'storage_service.dart';

class CourseCatalogService extends ChangeNotifier {
  CourseCatalogService(this.eams, this.storage, this.auth, this.ids) {
    _previous = owner;
    auth.addListener(_accountChanged);
    ids.addListener(_accountChanged);
  }
  final Listenable auth, ids;
  String? _previous;
  int generation = 0;
  void _accountChanged() {
    final next = owner;
    if (next == _previous) return;
    final old = _previous;
    if (old != null) unawaited(storage.clearCatalogHistory(old));
    _previous = next;
    generation++;
    _options = null;
    notifyListeners();
  }

  @override
  void dispose() {
    auth.removeListener(_accountChanged);
    ids.removeListener(_accountChanged);
    generation++;
    super.dispose();
  }

  final EamsClient eams;
  final StorageService storage;
  static const base = '/eams/courseSearchOther';
  static const dictionaryFields = {
    'course.education.id': '学历层次',
    'course.courseType.id': '课程类别',
    'course.department.id': '开课院系',
  };
  static const pageSize = 20;
  Map<String, Map<String, String>>? _options;
  String? get owner {
    final identity = eams.session.identity();
    final user = identity.user ?? '';
    final ids = identity.ids ?? '';
    if (user.isEmpty || ids.isEmpty) return null;
    return jsonEncode([user, ids]);
  }

  Future<Map<String, Map<String, String>>> options() async {
    if (_options != null) return _options!;
    final version = generation;
    final source = await eams.getHtml('$base.action');
    if (version != generation) throw CampusRequestException.expired;
    return _options = {
      for (final name in dictionaryFields.keys) name: EamsHtmlParser.options(source, name: name),
    };
  }

  List<String> get history => owner == null ? [] : storage.catalogHistory(owner!);

  Future<List<CatalogCourse>> search(Map<String, String> filters, int page) async {
    final account = owner;
    final source = await eams.postForm('$base!search.action', {
      ...filters,
      'pageNo': '$page',
      'pageSize': '$pageSize',
    });
    final result = parseResults(source);
    final keyword = (filters['course.name'] ?? '').isNotEmpty
        ? filters['course.name']!
        : filters['course.code'] ?? '';
    if (page == 1 && keyword.isNotEmpty && account != null && owner == account) {
      await storage.saveCatalogHistory(account, {keyword, ...history}.take(8).toList());
    }
    return result;
  }

  static List<CatalogCourse> parseResults(String source) {
    final doc = html.parse(source);
    if (doc.querySelector('table.gridtable') == null &&
        !RegExp('没有.*(?:记录|数据)|暂无').hasMatch(doc.body?.text ?? '')) {
      throw CampusRequestException.invalid;
    }
    return EamsHtmlParser.gridTable(source)
        .map(CatalogCourse.fromRow)
        .where((c) => c.name.isNotEmpty)
        .toList();
  }
}
