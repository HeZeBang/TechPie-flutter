import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html;

import '../models/pnp_and_minor.dart';
import 'campus/campus_errors.dart';
import 'campus/eams_client.dart';
import 'storage_service.dart';

enum AcademicApplicationTab { pnp, minor }

class PnpMinorService extends ChangeNotifier {
  PnpMinorService(this.client, this.storage, this.auth, this.ids) {
    auth.addListener(_changed);
    ids.addListener(_changed);
    _changed();
  }
  final EamsClient client;
  final StorageService storage;
  final Listenable auth, ids;
  static const pnp = '/eams/pnp/std-pnp-apply';
  static const minor = '/eams/minorApply';
  static const appTitles = [
    '课程名称',
    '课程名',
    '课程',
    '辅修专业名称',
    '辅修专业',
    '专业名称',
    '专业',
    '辅修项目',
    '项目名称',
    '院系名称',
    '院系',
    '培养方案名称',
    '计划名称',
    '方案名称',
  ];
  static const visibleFields = {
    '学年学期',
    '学期',
    '课程代码',
    '课程类别',
    '学分',
    '申请类型',
    '申请状态',
    '审核状态',
    '状态',
    '申请时间',
    '申请日期',
    '报名时间',
    '院系',
    '院系名称',
    '所属院系',
    '开课院系',
    '专业名称',
    '计划人数',
    '修读学期',
    '退选时间',
    '是否必修',
    '学时',
    '审核结果',
  };
  String? _owner;
  int generation = 0;
  bool get ready => _owner != null;
  final windows = <AcademicApplicationTab, ApplicationWindow>{};
  Map<String, String> semesters = {};
  String? selected;
  final sections = <String, List<AcademicApplicationRow>>{};
  final sectionErrors = <String, String>{};
  static const historyLabels = ['P/NP 历史申请', '我的辅修申请', '已退选'];
  static const _pnpLabels = ['本学期申请', 'P/NP 历史申请'];
  static const _minorLabels = ['可报名专业', '我的辅修申请', '已退选', '辅修培养方案'];

  void _changed() {
    final identity = client.session.identity();
    final owner = (identity.user?.isNotEmpty == true && identity.ids?.isNotEmpty == true)
        ? jsonEncode([identity.user, identity.ids])
        : null;
    if (owner == _owner) return;
    if (_owner != null) unawaited(storage.clearPnpMinorHistory(_owner!));
    _owner = owner;
    generation++;
    windows.clear();
    sections.clear();
    sectionErrors.clear();
    semesters = {};
    selected = null;
    if (owner != null) {
      final raw = storage.pnpMinorHistory(owner);
      if (raw != null) {
        try {
          final cache = jsonDecode(raw) as Map<String, dynamic>;
          for (final label in historyLabels) {
            final list = cache[label] as List?;
            if (list != null) {
              sections[label] =
                  list.cast<Map<String, dynamic>>().map(AcademicApplicationRow.fromJson).toList();
            }
          }
        } on FormatException {
          sections.clear();
        } on TypeError {
          sections.clear();
        }
      }
    }
    notifyListeners();
  }

  Future<void> refresh(AcademicApplicationTab tab, {String? semester}) async {
    final owner = _owner;
    if (owner == null) {
      throw const CampusRequestException(CampusErrorKind.idsNotBound, '请登录并绑定学校账号');
    }
    final version = generation;
    void check() {
      if (version != generation) throw CampusRequestException.expired;
    }

    Future<String> get(String path, {Map<String, String>? query}) async {
      check();
      final result = await client.getHtml(path, query: query);
      check();
      return result;
    }

    final pending = <String, List<AcademicApplicationRow>>{};
    final pendingErrors = <String, String>{};
    Object? firstError;

    Future<T?> runSection<T>(String label, Future<T> Function() task) async {
      try {
        return await task();
      } on CampusRequestException catch (e) {
        if (version != generation ||
            e.kind == CampusErrorKind.sessionExpired ||
            e.kind == CampusErrorKind.idsNotBound ||
            e.kind == CampusErrorKind.rateLimited ||
            e == CampusRequestException.expired) {
          rethrow;
        }
        firstError ??= e;
        pendingErrors[label] = e.message;
        return null;
      } on FormatException catch (e) {
        if (version != generation) throw CampusRequestException.expired;
        firstError ??= e;
        pendingErrors[label] = e.message;
        return null;
      }
    }

    final entry = await get('${tab == AcademicApplicationTab.pnp ? pnp : minor}.action');
    var window = parseWindow(entry);
    Map<String, String>? pendingTerms;
    String? pendingSelected;
    if (tab == AcademicApplicationTab.pnp) {
      final terms = await runSection('本学期申请', () async {
        final result = await client.fetchSemesters();
        check();
        return result;
      });
      if (terms != null) {
        final selectedOption = html
            .parse(entry)
            .querySelector(
              'select[name="semester.id"] option[selected],select[name="semesterId"] option[selected]',
            )
            ?.attributes['value'];
        final term = [semester, selected, selectedOption, ...terms.keys]
            .whereType<String>()
            .where(terms.containsKey)
            .firstOrNull;
        if (term != null) {
          final rows = await runSection(
            '本学期申请',
            () async => parseRows(await get('$pnp!myApplies.action', query: {'semesterId': term})),
          );
          if (rows != null) pending['本学期申请'] = rows;
        }
        pendingTerms = terms;
        pendingSelected = term;
      }
      final historyRows = await runSection(
        'P/NP 历史申请',
        () async => parseRows(await get('$pnp!historyList.action')),
      );
      if (historyRows != null) pending['P/NP 历史申请'] = historyRows;
    } else {
      final innerHtml = await runSection('可报名专业', () => get('$minor!innerIndex.action'));
      if (innerHtml != null) {
        if (window == ApplicationWindow.unknown) {
          window = parseWindow(innerHtml);
        }
        final innerRows = await runSection('可报名专业', () async => parseRows(innerHtml));
        if (innerRows != null) pending['可报名专业'] = innerRows;
      }
      for (final item in const [
        (label: '我的辅修申请', path: '$minor!myApplies.action'),
        (label: '已退选', path: '$minor!myOldApplies.action'),
        (label: '辅修培养方案', path: '/eams/myMinorPlan.action'),
      ]) {
        final rows = await runSection(item.label, () async => parseRows(await get(item.path)));
        if (rows != null) pending[item.label] = rows;
      }
    }
    check();
    if (pending.isEmpty && firstError != null) {
      Error.throwWithStackTrace(firstError!, StackTrace.current);
    }
    if (pendingTerms != null) {
      semesters = pendingTerms;
      selected = pendingSelected;
    }
    final labels = tab == AcademicApplicationTab.pnp ? _pnpLabels : _minorLabels;
    for (final label in labels) {
      sectionErrors.remove(label);
      final err = pendingErrors[label];
      if (err != null) sectionErrors[label] = err;
    }
    sections.addAll(pending);
    await storage.savePnpMinorHistory(
      owner,
      jsonEncode({
        for (final key in historyLabels)
          if (sections[key] != null) key: sections[key]!.map((r) => r.toJson()).toList(),
      }),
    );
    check();
    windows[tab] = window;
    notifyListeners();
  }

  static ApplicationWindow parseWindow(String source) {
    final doc = html.parse(source);
    for (final hidden
        in doc.querySelectorAll('script,style,template,[hidden],[aria-hidden="true"]')) {
      hidden.remove();
    }
    final hiddenByStyle = RegExp(
      r'(?:^|;)\s*(?:display\s*:\s*none|visibility\s*:\s*hidden)\b',
      caseSensitive: false,
    );
    for (final elem in doc.querySelectorAll('[style]')) {
      if (hiddenByStyle.hasMatch(elem.attributes['style'] ?? '')) {
        elem.remove();
      }
    }
    final text = (doc.body?.text ?? '').replaceAll(RegExp(r'\s+'), '');
    if (RegExp(
      '未开放|暂不开放|暂未开放|尚未开始|尚未开启|还未开始|未开启|已截止|已结束|不在申请时间|不在报名时间|非申请时间|非报名时间|未在开放时间|不在.*?(?:时间|期间)',
    ).hasMatch(text)) {
      return ApplicationWindow.closed;
    }
    if (RegExp('开放中|报名进行中|申请进行中').hasMatch(text)) return ApplicationWindow.open;
    for (final elem in doc.querySelectorAll(
      'a[href],a[onclick],button,input[type=submit],input[type=button],[data-action]',
    )) {
      if (elem.attributes.containsKey('disabled') ||
          elem.classes.contains('disabled') ||
          elem.attributes['aria-disabled'] == 'true') {
        continue;
      }
      final label = (elem.attributes['value'] ?? elem.text).replaceAll(RegExp(r'\s+'), '');
      final hasActionAttr = elem.attributes.containsKey('onclick') ||
          elem.attributes.containsKey('data-action');
      if (RegExp(r'^(?:新增申请|提交申请|申请P/NP|报名|我要报名|申请报名|新增报名)$').hasMatch(label)) {
        return ApplicationWindow.open;
      }
      if (hasActionAttr && RegExp(r'^(?:申请|提交|选择|新增|报名)$').hasMatch(label)) {
        return ApplicationWindow.open;
      }
    }
    return ApplicationWindow.unknown;
  }

  static List<AcademicApplicationRow> parseRows(String source) {
    final doc = html.parse(source);
    final rows = <AcademicApplicationRow>[];
    var recognized = false;
    for (final table in doc.querySelectorAll('table')) {
      List<String>? headers;
      for (final tr in table.querySelectorAll('tr')) {
        if (tr.parent != table && tr.parent?.parent != table) continue;
        final rawCells = tr.children.where((c) => ['td', 'th'].contains(c.localName)).toList();
        final normalizedHeaders =
            rawCells.map((c) => c.text.replaceAll(RegExp(r'\s+'), '')).toList();
        if (normalizedHeaders.any(appTitles.contains)) {
          headers = normalizedHeaders;
          recognized = true;
          continue;
        }
        final cells = rawCells.map((c) => c.text.trim()).toList();
        if (headers == null || cells.length < headers.length) continue;
        final data = Map.fromIterables(headers, cells.take(headers.length));
        final key = appTitles.firstWhere((h) => data[h]?.isNotEmpty == true, orElse: () => '');
        if (key.isEmpty) continue;
        rows.add(
          AcademicApplicationRow(data[key]!, {
            for (final entry in data.entries)
              if (visibleFields.contains(entry.key) && entry.key != key && entry.value.isNotEmpty)
                entry.key: entry.value,
          }),
        );
      }
    }
    if (!recognized &&
        !RegExp('未绑定|没有绑定|尚未绑定|暂无|没有.*(?:记录|数据)|未开放|未开始|尚未开放')
            .hasMatch(doc.body?.text ?? '')) {
      throw CampusRequestException.invalid;
    }
    return rows;
  }

  @override
  void dispose() {
    generation++;
    auth.removeListener(_changed);
    ids.removeListener(_changed);
    super.dispose();
  }
}
