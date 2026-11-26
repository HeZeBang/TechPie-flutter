import 'dart:async';

import 'package:flutter/material.dart';

import '../models/catalog_course.dart';
import '../services/campus/campus_errors.dart';
import '../services/course_catalog_service.dart';
import '../services/service_provider.dart';
import '../theme/theme.dart';

class CourseCatalogSearchPage extends StatelessWidget {
  const CourseCatalogSearchPage({super.key, this.service});
  final CourseCatalogService? service;

  @override
  Widget build(BuildContext context) {
    final catalog = service ?? ServiceProvider.of(context).courseCatalog!;
    return ListenableBuilder(
      listenable: catalog,
      builder: (context, _) => _Search(key: ValueKey(catalog.generation), catalog: catalog),
    );
  }
}

class _Search extends StatefulWidget {
  const _Search({super.key, required this.catalog});
  final CourseCatalogService catalog;
  @override
  State<_Search> createState() => _SearchState();
}

class _SearchState extends State<_Search> {
  static const _textFilterLabels = {
    'course.credits': '学分',
    'course.period': '总学时',
    'course.weekHour': '周学时',
    'course.weeks': '周数',
    'syllabus.subjectTeacher.name': '教师',
  };

  final keyword = TextEditingController();
  late final Map<String, TextEditingController> _filterControllers = {
    for (final key in _textFilterLabels.keys) key: TextEditingController(),
  };
  final filters = <String, String>{};
  final courses = <CatalogCourse>[];
  Map<String, Map<String, String>> options = {};
  Timer? debounce;
  int revision = 0, page = 0;
  bool busy = false, more = false;
  String? error, filterError;

  @override
  void initState() {
    super.initState();
    if (widget.catalog.owner != null) unawaited(loadOptions());
  }

  Future<void> loadOptions() async {
    try {
      final values = await widget.catalog.options();
      if (mounted) {
        setState(() {
          options = values;
          filterError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => filterError = e is CampusRequestException ? e.message : '筛选项加载失败');
      }
    }
  }

  void queueSearch() {
    debounce?.cancel();
    revision++;
    setState(() {
      page = 0;
      more = false;
      busy = false;
      courses.clear();
      error = null;
    });
    debounce = Timer(const Duration(milliseconds: 450), () => search());
  }

  void resetFilters() {
    filters.clear();
    for (final controller in _filterControllers.values) {
      controller.clear();
    }
    queueSearch();
  }

  String _courseKey(CatalogCourse c) =>
      '${c.code}\u0000${c.name}\u0000${c.teacher}\u0000${c.department}';

  Future<void> search({bool append = false}) async {
    debounce?.cancel();
    final rev = ++revision;
    final next = append ? page + 1 : 1;
    final text = keyword.text.trim();
    final isCode = RegExp(r'^[a-zA-Z]+[- ]?\d', caseSensitive: false).hasMatch(text);
    setState(() {
      busy = true;
      error = null;
      if (!append) {
        courses.clear();
        page = 0;
        more = false;
      }
    });
    try {
      final rows = await widget.catalog.search(
        {...filters, if (text.isNotEmpty) (isCode ? 'course.code' : 'course.name'): text},
        next,
      );
      if (!mounted || rev != revision) return;
      setState(() {
        if (append) {
          final seen = courses.map(_courseKey).toSet();
          final fresh = rows.where((c) => seen.add(_courseKey(c))).toList();
          courses.addAll(fresh);
          page = next;
          more = fresh.isNotEmpty && rows.length == CourseCatalogService.pageSize;
        } else {
          courses.addAll(rows);
          page = next;
          more = rows.length == CourseCatalogService.pageSize;
        }
      });
    } catch (e) {
      if (mounted && rev == revision) {
        setState(() => error = e is CampusRequestException ? e.message : '课程检索失败');
      }
    } finally {
      if (mounted && rev == revision) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    keyword.dispose();
    for (final controller in _filterControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void detail(CatalogCourse c) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.name, style: Theme.of(context).textTheme.headlineSmall),
                for (final d in c.details.entries)
                  if (d.value.isNotEmpty) ListTile(title: Text(d.value), subtitle: Text(d.key)),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final hasFilters = filters.values.any((v) => v.isNotEmpty);
    return Scaffold(
      appBar: AppBar(title: const Text('本科课程目录')),
      body: widget.catalog.owner == null
          ? const Center(child: Text('请登录并绑定学校账号'))
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 840),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    TextField(
                      controller: keyword,
                      decoration: InputDecoration(
                        labelText: '课程名称或代码',
                        suffixIcon: IconButton(
                          tooltip: '搜索',
                          icon: const Icon(Icons.search),
                          onPressed: () => search(),
                        ),
                      ),
                      textInputAction: TextInputAction.search,
                      onChanged: (_) => queueSearch(),
                      onSubmitted: (_) => search(),
                    ),
                    if (widget.catalog.history.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final h in widget.catalog.history)
                            ActionChip(
                              label: Text(h),
                              onPressed: () {
                                keyword.text = h;
                                unawaited(search());
                              },
                            ),
                        ],
                      ),
                    ExpansionTile(
                      maintainState: true,
                      title: const Text('筛选条件'),
                      childrenPadding: const EdgeInsets.fromLTRB(
                        TpTokens.space3,
                        TpTokens.space2,
                        TpTokens.space3,
                        TpTokens.space3,
                      ),
                      children: [
                        if (filterError != null)
                          TextButton(onPressed: loadOptions, child: Text('$filterError · 重试')),
                        for (final f in CourseCatalogService.dictionaryFields.entries)
                          Padding(
                            padding: const EdgeInsets.only(bottom: TpTokens.space3),
                            child: Builder(
                              builder: (context) {
                                final selected = filters[f.key] ?? '';
                                final valid = selected.isEmpty ||
                                        (options[f.key]?.containsKey(selected) ?? false)
                                    ? selected
                                    : '';
                                return DropdownButtonFormField<String>(
                                  key: ValueKey('${f.key}:${options[f.key]?.length ?? 0}:$valid'),
                                  decoration: InputDecoration(labelText: f.value),
                                  initialValue: valid,
                                  items: [
                                    const DropdownMenuItem(value: '', child: Text('不限')),
                                    for (final opt
                                        in (options[f.key] ?? {}).entries.where((e) => e.key != ''))
                                      DropdownMenuItem(value: opt.key, child: Text(opt.value)),
                                  ],
                                  onChanged: (v) {
                                    filters[f.key] = v ?? '';
                                    queueSearch();
                                  },
                                  isExpanded: true,
                                );
                              },
                            ),
                          ),
                        for (final f in _textFilterLabels.entries)
                          Padding(
                            padding: const EdgeInsets.only(bottom: TpTokens.space3),
                            child: TextField(
                              controller: _filterControllers[f.key],
                              decoration: InputDecoration(labelText: f.value),
                              onChanged: (v) {
                                filters[f.key] = v.trim();
                                queueSearch();
                              },
                            ),
                          ),
                        if (hasFilters)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: resetFilters,
                              child: const Text('重置筛选'),
                            ),
                          ),
                      ],
                    ),
                    if (busy) const LinearProgressIndicator(),
                    if (error != null)
                      TextButton(
                        onPressed: () => search(append: page > 0),
                        child: Text('$error · 重试'),
                      ),
                    if (page > 0 && courses.isEmpty) const ListTile(title: Text('没有符合条件的课程')),
                    for (final c in courses)
                      ListTile(
                        title: Text(c.name),
                        subtitle: Text(
                          [
                            c.code,
                            c.department,
                            if (c.credits.isNotEmpty) '${c.credits} 学分',
                            c.teacher,
                          ].where((s) => s.isNotEmpty).join(' · '),
                        ),
                        onTap: () => detail(c),
                      ),
                    if (more && !busy)
                      TextButton(
                        onPressed: () => search(append: true),
                        child: const Text('加载更多'),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}
