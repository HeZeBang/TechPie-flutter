import 'package:flutter/material.dart';

import '../models/feature.dart';
import '../models/quick_shortcuts.dart';
import '../services/storage_service.dart';
import '../theme/theme.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/design_system/design_system.dart';
import 'campus_feature_navigation.dart';

class CampusServicesPage extends StatefulWidget {
  const CampusServicesPage({super.key, required this.storage});
  final StorageService storage;

  @override
  State<CampusServicesPage> createState() => _CampusServicesPageState();
}

class _CampusServicesPageState extends State<CampusServicesPage> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _clear() {
    _search.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final query = _query.trim().toLowerCase();
    final results = featureEntries.where(
      (f) => [f.description, f.subtitle, ...f.keywords]
          .any((text) => text.toLowerCase().contains(query)),
    );
    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(
        title: const Text('校园服务中心'),
        actions: [
          IconButton(
            tooltip: '编辑首页快捷',
            icon: const Icon(TpIcons.sliders),
            onPressed: () => pushAdaptivePage<void>(
              context,
              builder: (_) => _ShortcutEditor(storage: widget.storage),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: TpPageBody(
          maxWidth: 1120,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final gutter = constraints.maxWidth < 600 ? TpTokens.space4 : TpTokens.space5;
              final columns = constraints.maxWidth < 600
                  ? 1
                  : constraints.maxWidth < 960
                      ? 2
                      : 3;
              final width =
                  (constraints.maxWidth - 2 * gutter - (columns - 1) * TpTokens.space3) / columns;
              return ListView(
                padding: EdgeInsets.fromLTRB(
                  gutter,
                  TpTokens.space4,
                  gutter,
                  AppShellMetrics.bottomContentPaddingOf(context),
                ),
                children: [
                  TextField(
                    controller: _search,
                    onChanged: (text) => setState(() => _query = text),
                    decoration: InputDecoration(
                      labelText: '搜索服务',
                      prefixIcon: const Icon(TpIcons.search),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: '清除搜索',
                              onPressed: _clear,
                              icon: const Icon(TpIcons.close),
                            ),
                    ),
                  ),
                  if (results.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(TpTokens.space5),
                      child: Column(
                        children: [
                          const Text('没有找到相关服务'),
                          TextButton(onPressed: _clear, child: const Text('清除搜索')),
                        ],
                      ),
                    ),
                  for (final category in CampusServiceCategory.values)
                    if (results.any((f) => f.category == category)) ...[
                      Padding(
                        padding:
                            const EdgeInsets.only(top: TpTokens.space5, bottom: TpTokens.space2),
                        child: Semantics(
                          header: true,
                          child: Text(category.label, style: TpTypography.cardTitle(colors)),
                        ),
                      ),
                      Wrap(
                        spacing: TpTokens.space3,
                        runSpacing: TpTokens.space3,
                        children: [
                          for (final f in results.where((f) => f.category == category))
                            SizedBox(
                              width: width,
                              child: TpCard(
                                onTap: () => openCampusFeature(context, f),
                                child: ListTile(
                                  leading: Icon(f.icon.icon, color: colors.brandInk),
                                  title: Text(f.description),
                                  subtitle: Text(f.subtitle),
                                  trailing: const Icon(TpIcons.chevronRight, size: TpTokens.iconS),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ShortcutEditor extends StatefulWidget {
  const _ShortcutEditor({required this.storage});
  final StorageService storage;

  @override
  State<_ShortcutEditor> createState() => _ShortcutEditorState();
}

class _ShortcutEditorState extends State<_ShortcutEditor> {
  late final _available = {
    for (final f in featureEntries)
      if (f.id != 'campus_card') f.id: f,
  };
  late final List<String> _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final saved = widget.storage.pinnedQuickFeatureIds;
    _selected = saved == null
        ? homeQuickFeatures(null).map((f) => f.id).toList()
        : pinnedShortcutIds(saved.where(_available.containsKey));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.storage.setPinnedQuickFeatureIds(_selected);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('快捷入口保存失败，请重试')));
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _move(int index, int by) => setState(() {
        final id = _selected.removeAt(index);
        _selected.insert(index + by, id);
      });

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(
        leading: IconButton(
          tooltip: '取消',
          icon: const Icon(TpIcons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('编辑首页快捷'),
        actions: [TextButton(onPressed: _saving ? null : _save, child: const Text('保存'))],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: TpPageBody(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              TpTokens.space4,
              TpTokens.space4,
              TpTokens.space4,
              AppShellMetrics.bottomContentPaddingOf(context),
            ),
            children: [
              TpCard(
                title: '已选 ${_selected.length}/$maxPinnedQuickFeatures',
                child: Column(
                  children: [
                    for (var i = 0; i < _selected.length; i++)
                      ListTile(
                        key: ValueKey('pin-${_selected[i]}'),
                        title: Text(_available[_selected[i]]!.description),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: '上移',
                              onPressed: i == 0 || _saving ? null : () => _move(i, -1),
                              icon: const Icon(Icons.arrow_upward),
                            ),
                            IconButton(
                              tooltip: '下移',
                              onPressed:
                                  i == _selected.length - 1 || _saving ? null : () => _move(i, 1),
                              icon: const Icon(Icons.arrow_downward),
                            ),
                          ],
                        ),
                      ),
                    if (_selected.length < maxPinnedQuickFeatures)
                      const Padding(
                        padding: EdgeInsets.all(TpTokens.space3),
                        child: Text('首页的空位会按默认顺序补齐。'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: TpTokens.space4),
              TpCard(
                title: '选择服务',
                child: Column(
                  children: [
                    for (final f in _available.values)
                      CheckboxListTile(
                        title: Text(f.description),
                        value: _selected.contains(f.id),
                        onChanged: _saving ||
                                (!_selected.contains(f.id) &&
                                    _selected.length == maxPinnedQuickFeatures)
                            ? null
                            : (checked) => setState(() {
                                  if (checked == true) {
                                    _selected.add(f.id);
                                  } else {
                                    _selected.remove(f.id);
                                  }
                                }),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
