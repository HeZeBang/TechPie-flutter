import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/catalog_course.dart';
import '../services/campus/campus_errors.dart';
import '../services/course_catalog_service.dart';
import '../services/service_provider.dart';
import '../theme/theme.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/adaptive_navigation_scaffold.dart';
import '../widgets/adaptive_select.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/campus_prerequisite_view.dart';
import '../widgets/design_system/design_system.dart';

class CourseCatalogSearchPage extends StatelessWidget {
  const CourseCatalogSearchPage({super.key, this.service});
  final CourseCatalogService? service;

  @override
  Widget build(BuildContext context) {
    final catalog = service ??
        context
            .dependOnInheritedWidgetOfExactType<ServiceProvider>()
            ?.courseCatalog;
    if (catalog == null) {
      return Scaffold(
        backgroundColor: context.tpColors.canvas,
        appBar: const BlurredAppBar(title: Text('本科课程目录')),
        body: const CampusPrerequisiteView(
          icon: TpIcons.course,
          title: '本科课程目录',
          fallbackText: '请登录并绑定学校账号',
        ),
      );
    }
    return ListenableBuilder(
      listenable: catalog,
      builder: (context, _) =>
          _Search(key: ValueKey(catalog.generation), catalog: catalog),
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
  static const _numericFilterKeys = {
    'course.credits',
    'course.period',
    'course.weekHour',
    'course.weeks',
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
        setState(
          () => filterError =
              e is CampusRequestException ? e.message : '筛选项加载失败',
        );
      }
    }
  }

  bool get _hasAnyCriteria =>
      keyword.text.trim().isNotEmpty ||
      filters.values.any((v) => v.trim().isNotEmpty);

  void queueSearch({bool clearResults = true}) {
    debounce?.cancel();
    revision++;
    setState(() {
      page = 0;
      more = false;
      busy = false;
      if (clearResults) courses.clear();
      error = null;
    });
    if (!_hasAnyCriteria) return;
    debounce = Timer(const Duration(milliseconds: 450), () => search());
  }

  void resetFilters() {
    filters.clear();
    for (final controller in _filterControllers.values) {
      controller.clear();
    }
    queueSearch(clearResults: !_hasAnyCriteria);
  }

  String _courseKey(CatalogCourse c) =>
      '${c.code}\u0000${c.name}\u0000${c.teacher}\u0000${c.department}';

  Future<void> search({bool append = false}) async {
    debounce?.cancel();
    final rev = ++revision;
    final next = append ? page + 1 : 1;
    final text = keyword.text.trim();
    final isCode =
        RegExp(r'^[a-zA-Z]+[- ]?\d', caseSensitive: false).hasMatch(text);
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
        {
          ...filters,
          if (text.isNotEmpty) (isCode ? 'course.code' : 'course.name'): text,
        },
        next,
      );
      if (!mounted || rev != revision) return;
      setState(() {
        if (append) {
          final seen = courses.map(_courseKey).toSet();
          final fresh = rows.where((c) => seen.add(_courseKey(c))).toList();
          courses.addAll(fresh);
          page = next;
          more = fresh.isNotEmpty &&
              rows.length == CourseCatalogService.pageSize;
        } else {
          courses.addAll(rows);
          page = next;
          more = rows.length == CourseCatalogService.pageSize;
        }
      });
    } catch (e) {
      if (mounted && rev == revision) {
        setState(
          () => error = e is CampusRequestException ? e.message : '课程检索失败',
        );
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

  Future<void> _copyCourseCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) {
      showAdaptiveFeedback(
        context: context,
        message: '已复制课程代码 $code',
        style: AdaptiveFeedbackStyle.success,
      );
    }
  }

  void detail(CatalogCourse c) => AdaptiveNavigationScaffold.showSheet<void>(
        context: context,
        builder: (sheetContext, padding) {
          final colors = sheetContext.tpColors;
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.78,
            ),
            child: SingleChildScrollView(
              padding: padding,
              child: TpPageBody(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      c.name,
                      style:
                          TpTypography.cardTitle(colors).copyWith(fontSize: 17),
                    ),
                    if (c.code.isNotEmpty) ...[
                      const SizedBox(height: TpTokens.space2),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: () => _copyCourseCode(c.code),
                          icon: const Icon(TpIcons.copy, size: TpTokens.iconS),
                          label: Text('复制代码 ${c.code}'),
                        ),
                      ),
                    ],
                    const SizedBox(height: TpTokens.space3),
                    TpCard(
                      child: Column(
                        children: [
                          for (final d in c.details.entries)
                            if (d.value.isNotEmpty)
                              ListTile(
                                dense: true,
                                title: Text(
                                  d.key,
                                  style: TpTypography.itemMeta(colors),
                                ),
                                subtitle: SelectableText(
                                  d.value,
                                  style: TpTypography.itemTitle(colors),
                                ),
                              ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final activeFilterCount =
        filters.values.where((v) => v.trim().isNotEmpty).length;
    final hasFilters = activeFilterCount > 0;

    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: const BlurredAppBar(title: Text('本科课程目录')),
      body: widget.catalog.owner == null
          ? const CampusPrerequisiteView(
              icon: TpIcons.course,
              title: '本科课程目录',
              fallbackText: '请登录并绑定学校账号',
            )
          : TpPageBody(
              maxWidth: 880,
              child: ListView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  TpTokens.pageHorizontalPadding,
                  TpTokens.space4,
                  TpTokens.pageHorizontalPadding,
                  AppShellMetrics.bottomContentPaddingOf(context),
                ),
                children: [
                      TextField(
                        controller: keyword,
                        decoration: InputDecoration(
                          labelText: '课程名称或代码',
                          prefixIcon: const Icon(TpIcons.search),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (keyword.text.isNotEmpty)
                                IconButton(
                                  tooltip: '清除搜索',
                                  onPressed: () {
                                    keyword.clear();
                                    queueSearch();
                                  },
                                  icon: const Icon(TpIcons.close),
                                ),
                              IconButton(
                                tooltip: '搜索',
                                icon: const Icon(TpIcons.search),
                                onPressed: () => search(),
                              ),
                            ],
                          ),
                        ),
                        textInputAction: TextInputAction.search,
                        onChanged: (_) => queueSearch(),
                        onSubmitted: (_) => search(),
                      ),
                      if (widget.catalog.history.isNotEmpty) ...[
                        const SizedBox(height: TpTokens.space2),
                        Wrap(
                          spacing: TpTokens.space2,
                          runSpacing: TpTokens.space1,
                          children: [
                            for (final h in widget.catalog.history)
                              ActionChip(
                                label: Text(h),
                                onPressed: () {
                                  keyword.text = h;
                                  keyword.selection = TextSelection.collapsed(
                                    offset: h.length,
                                  );
                                  unawaited(search());
                                },
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: TpTokens.space3),
                      TpCard(
                        child: Theme(
                          data: Theme.of(context)
                              .copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            maintainState: true,
                            leading: const Icon(TpIcons.filter),
                            title: Row(
                              children: [
                                const Text('筛选条件'),
                                if (activeFilterCount > 0) ...[
                                  const SizedBox(width: TpTokens.space2),
                                  TpBadge(
                                    label: '$activeFilterCount',
                                    tone: TpBadgeTone.brand,
                                  ),
                                ],
                              ],
                            ),
                            childrenPadding: const EdgeInsets.fromLTRB(
                              TpTokens.space3,
                              TpTokens.space2,
                              TpTokens.space3,
                              TpTokens.space3,
                            ),
                            children: [
                              if (filterError != null)
                                TextButton(
                                  onPressed: loadOptions,
                                  child: Text('$filterError · 重试'),
                                ),
                              for (final f in
                                  CourseCatalogService.dictionaryFields.entries)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: TpTokens.space3,
                                  ),
                                  child: Builder(
                                    builder: (context) {
                                      final selected = filters[f.key] ?? '';
                                      final valid = selected.isEmpty ||
                                              (options[f.key]
                                                      ?.containsKey(selected) ??
                                                  false)
                                          ? selected
                                          : '';
                                      return AdaptiveSelect(
                                        key: ValueKey(
                                          '${f.key}:${options[f.key]?.length ?? 0}:$valid',
                                        ),
                                        label: f.value,
                                        width: double.infinity,
                                        value: valid,
                                        placeholder: '不限',
                                        options: [
                                          const AdaptiveSelectOption(
                                            value: '',
                                            label: '不限',
                                          ),
                                          for (final opt
                                              in (options[f.key] ?? {})
                                                  .entries
                                                  .where((e) => e.key != ''))
                                            AdaptiveSelectOption(
                                              value: opt.key,
                                              label: opt.value,
                                            ),
                                        ],
                                        onChanged: (v) {
                                          setState(() => filters[f.key] = v);
                                          queueSearch();
                                        },
                                      );
                                    },
                                  ),
                                ),
                              for (final f in _textFilterLabels.entries)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: TpTokens.space3,
                                  ),
                                  child: TextField(
                                    controller: _filterControllers[f.key],
                                    keyboardType:
                                        _numericFilterKeys.contains(f.key)
                                            ? const TextInputType
                                                .numberWithOptions(
                                                decimal: true,
                                              )
                                            : null,
                                    decoration: InputDecoration(
                                      labelText: f.value,
                                    ),
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
                        ),
                      ),
                      if (busy && page == 0) ...[
                        const SizedBox(height: TpTokens.space2),
                        const LinearProgressIndicator(),
                      ],
                      if (error != null) ...[
                        const SizedBox(height: TpTokens.space3),
                        TpStateCard.error(
                          title: '课程检索失败',
                          message: error,
                          compact: true,
                          onPrimaryAction: () => search(append: page > 0),
                        ),
                      ],
                      if (page == 0 && courses.isEmpty && !busy && error == null)
                        const Padding(
                          padding: EdgeInsets.only(top: TpTokens.space4),
                          child: TpStateCard.empty(
                            icon: TpIcons.course,
                            title: '输入课程名称、代码或筛选条件开始检索',
                            compact: true,
                          ),
                        ),
                      if (page > 0 && courses.isEmpty && !busy)
                        const Padding(
                          padding: EdgeInsets.only(top: TpTokens.space4),
                          child: TpStateCard.empty(
                            icon: TpIcons.search,
                            title: '没有符合条件的课程',
                            compact: true,
                          ),
                        ),
                      if (courses.isNotEmpty) ...[
                        const SizedBox(height: TpTokens.space3),
                        Padding(
                          padding: const EdgeInsets.only(bottom: TpTokens.space2),
                          child: Row(
                            children: [
                              Text('检索结果', style: TpTypography.cardTitle(colors)),
                              const Spacer(),
                              TpBadge(
                                label: '${courses.length} 门',
                                tone: TpBadgeTone.muted,
                              ),
                            ],
                          ),
                        ),
                        for (final c in courses)
                          Padding(
                            padding: const EdgeInsets.only(bottom: TpTokens.space2),
                            child: TpCard(
                              child: ListTile(
                                title: Text(c.name),
                                subtitle: Text(
                                  [
                                    c.code,
                                    c.department,
                                    if (c.credits.isNotEmpty) '${c.credits} 学分',
                                    c.teacher,
                                  ].where((s) => s.isNotEmpty).join(' · '),
                                ),
                                trailing: const Icon(
                                  TpIcons.chevronRight,
                                  size: TpTokens.iconS,
                                ),
                                onTap: () => detail(c),
                              ),
                            ),
                          ),
                      ],
                      if (more && busy)
                        const Padding(
                          padding: EdgeInsets.all(TpTokens.space4),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      if (more && !busy)
                        Padding(
                          padding: const EdgeInsets.only(top: TpTokens.space2),
                          child: Center(
                            child: TextButton(
                              onPressed: () => search(append: true),
                              child: const Text('加载更多'),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}
