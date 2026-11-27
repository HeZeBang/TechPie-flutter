import 'dart:async';

import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html;

import '../models/feature.dart';
import '../services/egate_app_service.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/design_system/tp_card.dart';
import 'emap_action_dialog.dart';
import 'generic_webview_page.dart';

class EgateDiscovery extends StatefulWidget {
  const EgateDiscovery({super.key, required this.service, required this.onChanged});
  final EgateAppService service;
  final Future<void> Function() onChanged;
  @override
  State<EgateDiscovery> createState() => _DiscoveryState();
}

class _DiscoveryState extends State<EgateDiscovery> {
  static const int _maxSearchPages = 10;

  bool recent = true, busy = false, hasNext = false, registering = false, searchCapped = false;
  int page = 0, request = 0;
  String search = '';
  final query = TextEditingController();
  Timer? _searchDebounce;
  late List<EgateActivity> rows = widget.service.recent;
  String? error;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    query.dispose();
    super.dispose();
  }

  Future<void> _load({bool next = false}) async {
    final serial = ++request;
    setState(() {
      busy = true;
      error = null;
      searchCapped = false;
    });
    var target = next ? page + 1 : 1;
    try {
      late List<EgateActivity> matches;
      var more = false;
      var capped = false;
      if (recent) {
        matches = await widget.service.fetchRecentActivities();
      } else {
        // The activity model supports pagination. Search those pages without
        // assuming a server-side query operator for the activity name.
        final needle = search.toLowerCase();
        var scanned = 0;
        while (true) {
          final batch = await widget.service.fetchAllActivities(target);
          if (!mounted || request != serial) return;
          scanned++;
          matches = needle.isEmpty
              ? batch.rows
              : batch.rows
                  .where((row) => row.name.toLowerCase().contains(needle))
                  .toList();
          more = batch.hasNext && batch.rows.isNotEmpty;
          if (matches.isNotEmpty || !more || needle.isEmpty) break;
          if (scanned >= _maxSearchPages) {
            capped = true;
            break;
          }
          target++;
        }
      }
      if (!mounted || request != serial) return;
      setState(() {
        rows = next ? [...rows, ...matches] : matches;
        page = target;
        hasNext = more;
        searchCapped = capped;
      });
    } catch (e) {
      if (mounted && request == serial) setState(() => error = '$e');
    } finally {
      if (mounted && request == serial) setState(() => busy = false);
    }
  }

  String actionLabel(EgateActivity activity) => activity.registered
      ? '已报名'
      : activity.canRegister
          ? '报名'
          : '前往网页版';

  Future<void> register(EgateActivity activity) async {
    if (!activity.canRegister) {
      await pushAdaptivePage<void>(
        context,
        builder: (_) => const GenericWebViewPage(
          title: '学生活动',
          url: 'https://egate.shanghaitech.edu.cn/xsfw/sys/xshdapp/*default/index.do',
          cookieType: CookieType.egateApp,
        ),
      );
      return;
    }
    final rev = widget.service.revision;
    if (registering ||
        !await confirmEmapAction(
          context,
          '报名',
          [
            activity.name,
            activity['HDSJ'],
            activity['HDDD'],
          ].where((v) => v.isNotEmpty).join('\n'),
        ) ||
        !mounted) {
      return;
    }
    setState(() => registering = true);
    try {
      widget.service.check(rev);
      final reply = await widget.service.registerActivity(activity);
      if (!mounted) return;
      showAdaptiveFeedback(context: context, message: reply);
      await Future.wait([_load(), widget.onChanged()]);
    } catch (e) {
      if (mounted) {
        showAdaptiveFeedback(context: context, message: '$e', style: AdaptiveFeedbackStyle.error);
      }
    } finally {
      if (mounted) setState(() => registering = false);
    }
  }

  Future<void> detail(EgateActivity activity) async {
    final service = widget.service;
    final rev = service.revision;
    final apply = await showDialog<bool>(
      context: context,
      builder: (dialog) => ListenableBuilder(
        listenable: service,
        builder: (_, __) {
          if (service.revision != rev) return const AlertDialog(content: Text('账号已变更'));
          final description = html.parseFragment(activity['HDJS']).text ?? '';
          return AlertDialog(
            title: Text(activity.name),
            scrollable: true,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final v in [
                  activity['HDSJ'],
                  activity['HDDD'],
                  activity['HDLX_DISPLAY'],
                  activity['HDJB_DISPLAY'],
                  activity.status,
                ])
                  if (v.isNotEmpty) Text(v),
                if (activity['HDRS'].isNotEmpty)
                  Text('报名人数 ${activity["CJRS"]} / ${activity["HDRS"]}'),
                if (description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(description),
                  ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('关闭')),
              FilledButton(
                onPressed: activity.registered ? null : () => Navigator.pop(dialog, true),
                child: Text(actionLabel(activity)),
              ),
            ],
          );
        },
      ),
    );
    if (mounted && apply == true && service.revision == rev) await register(activity);
  }

  @override
  Widget build(BuildContext context) {
    final needle = search.toLowerCase();
    final visible = recent ? rows.where((r) => r.name.toLowerCase().contains(needle)) : rows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('近期活动')),
            ButtonSegment(value: false, label: Text('全部活动')),
          ],
          selected: {
            recent,
          },
          onSelectionChanged: (set) {
            _searchDebounce?.cancel();
            setState(() {
              recent = set.single;
              rows = recent ? widget.service.recent : widget.service.all;
              search = '';
              query.clear();
              hasNext = false;
              searchCapped = false;
            });
            unawaited(_load());
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: TextField(
            controller: query,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: '搜索活动名称',
              suffixIcon: IconButton(
                tooltip: '搜索',
                icon: const Icon(Icons.search),
                onPressed: () => _search(query.text),
              ),
            ),
            onChanged: (v) {
              if (recent) {
                setState(() => search = v.trim());
                return;
              }
              _searchDebounce?.cancel();
              _searchDebounce = Timer(const Duration(milliseconds: 350), () {
                if (mounted && !recent) _search(v);
              });
            },
            onSubmitted: _search,
          ),
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          ListTile(
            title: Text(error!),
            trailing: TextButton(onPressed: _load, child: const Text('重试')),
          ),
        if (!busy && error == null && visible.isEmpty)
          ListTile(
            title: Text(searchCapped ? '已连续翻页搜索，暂未找到匹配活动' : '暂无活动'),
          ),
        for (final activity in visible)
          TpCard(
            child: ListTile(
              onTap: () => detail(activity),
              title: Text(activity.name),
              subtitle: Text(
                [activity['HDSJ'], activity['HDDD'], activity.status]
                    .where((s) => s.isNotEmpty)
                    .join(' · '),
              ),
              trailing: TextButton(
                onPressed: registering || activity.registered ? null : () => register(activity),
                child: Text(actionLabel(activity)),
              ),
            ),
          ),
        if (!recent && hasNext)
          TextButton(onPressed: busy ? null : () => _load(next: true), child: const Text('加载更多')),
      ],
    );
  }

  void _search(String value) {
    _searchDebounce?.cancel();
    setState(() => search = value.trim());
    if (!recent) unawaited(_load());
  }
}
