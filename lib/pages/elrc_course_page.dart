import 'dart:async';

import 'package:flutter/material.dart';

import '../models/elrc_course.dart';
import '../models/elrc_recording.dart';
import '../services/elrc_client.dart';
import '../services/elrc_error.dart';
import '../widgets/adaptive_page_navigation.dart';
import 'elrc_player_page.dart';

class ElrcCoursePage extends StatefulWidget {
  const ElrcCoursePage({super.key, required this.course, required this.client});
  final ElrcCourse course;
  final ElrcClient client;

  @override
  State<ElrcCoursePage> createState() => _ElrcCoursePageState();
}

class _ElrcCoursePageState extends State<ElrcCoursePage> {
  ElrcRecordingOutline? _outline;
  ElrcException? _error;
  bool _loading = false;
  int _request = 0;
  late int _generation;

  @override
  void initState() {
    super.initState();
    _generation = widget.client.session.generation;
    widget.client.session.addListener(_sessionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  @override
  void didUpdateWidget(ElrcCoursePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final clientChanged = !identical(oldWidget.client, widget.client);
    if (clientChanged) {
      oldWidget.client.session.removeListener(_sessionChanged);
      _generation = widget.client.session.generation;
      widget.client.session.addListener(_sessionChanged);
    }
    if (clientChanged || oldWidget.course.key != widget.course.key) {
      _request++;
      _outline = null;
      _error = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_load());
      });
    }
  }

  void _sessionChanged() {
    if (_generation == widget.client.session.generation || !mounted) return;
    _generation = widget.client.session.generation;
    setState(() {
      _outline = null;
      _error = null;
    });
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      _outline = null;
    });
    try {
      await widget.client.session.connect();
      if (!mounted || request != _request) return;
      final outline = await widget.client.getOutline(widget.course);
      if (mounted && request == _request && widget.client.session.isConnected) {
        setState(() => _outline = outline);
      }
    } on ElrcException catch (error) {
      if (mounted && request == _request) setState(() => _error = error);
    } catch (_) {
      if (mounted && request == _request) {
        setState(() => _error = const ElrcException(ElrcErrorKind.network));
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _request++;
    widget.client.session.removeListener(_sessionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final outline = _outline;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.course.name),
        actions: [
          IconButton(
            tooltip: '刷新课次',
            onPressed: _loading ? null : () => unawaited(_load()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : outline == null
                ? ElrcStateMessage(
                    icon: _error == null ? Icons.school_outlined : Icons.info_outline,
                    title: _error?.message ?? '查看录播课次',
                    detail: _error == null ? '选择课程后，只请求这门课程的课次。' : null,
                    actionLabel: '重新加载',
                    onAction: () => unawaited(_load()),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (widget.course.description.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              widget.course.description,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        if (outline.incompleteLessonCount > 0)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              '${outline.incompleteLessonCount} 个课次的信息不完整，暂时无法打开。',
                            ),
                          ),
                        if (outline.lessons.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            child: Text(
                              outline.incompleteLessonCount == 0 ? '暂无课次' : '暂无信息完整的课次',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        for (var index = 0; index < outline.lessons.length; index++) ...[
                          if (index == 0 ||
                              outline.lessons[index - 1].week != outline.lessons[index].week)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                '第 ${outline.lessons[index].week} 周',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                          Card.outlined(
                            child: ListTile(
                              title: Text(
                                '${outline.lessons[index].weekDay} · ${outline.lessons[index].section} 节',
                              ),
                              subtitle: outline.lessons[index].weekDate.isEmpty
                                  ? null
                                  : Text(outline.lessons[index].weekDate),
                              trailing: const Icon(Icons.play_circle_outline),
                              onTap: () => unawaited(
                                pushAdaptivePage<void>(
                                  context,
                                  builder: (_) => ElrcPlayerPage(
                                    course: widget.course,
                                    lesson: outline.lessons[index],
                                    client: widget.client,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
      ),
    );
  }
}

class ElrcStateMessage extends StatelessWidget {
  const ElrcStateMessage({
    super.key,
    required this.icon,
    required this.title,
    this.detail,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final String title;
  final String? detail;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 44,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (detail != null) ...[
                const SizedBox(height: 12),
                Text(detail!, textAlign: TextAlign.center),
              ],
              if (onAction != null && actionLabel != null) ...[
                const SizedBox(height: 20),
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      );
}
