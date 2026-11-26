import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/screen_form_factor.dart';
import '../../../services/glance_settings_service.dart';
import '../domain/glance_snapshot.dart';
import 'cover_glance_layout.dart';
import 'glance_formatters.dart';
import 'glance_widgets.dart';
import 'rear_glance_layout.dart';

/// The compact surface shown on the rear screen or the MIX Flip cover.
///
/// This widget is presentation-only: the live wrapper feeds it a snapshot and
/// the host supplies the payment page, so the same layout can be rendered in
/// tests and in the settings preview without touching services.
class GlanceShell extends StatefulWidget {
  const GlanceShell({
    super.key,
    required this.surface,
    required this.snapshot,
    required this.sections,
    this.paymentBuilder,
    this.initialSection,
    this.requestedSection,
    this.requestRevision = 0,
    this.onPageChanged,
    this.onRefresh,
  });

  final GlanceSurface surface;
  final GlanceSnapshot snapshot;
  final List<GlanceSection> sections;
  final WidgetBuilder? paymentBuilder;
  final GlanceSection? initialSection;
  final GlanceSection? requestedSection;
  final int requestRevision;
  final ValueChanged<GlanceSection>? onPageChanged;
  final VoidCallback? onRefresh;

  @override
  State<GlanceShell> createState() => _GlanceShellState();
}

class _GlanceShellState extends State<GlanceShell> {
  late PageController _controller;
  late int _index;

  List<GlanceSection> get _sections => [
        for (final section in widget.sections)
          if (section != GlanceSection.payment || widget.paymentBuilder != null)
            section,
      ];

  @override
  void initState() {
    super.initState();
    final sections = _sections;
    _index = _indexOf(sections, widget.initialSection ?? widget.requestedSection);
    _controller = PageController(initialPage: _index);
  }

  @override
  void didUpdateWidget(GlanceShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sections = _sections;
    if (sections.isEmpty) return;
    if (_index >= sections.length) {
      _index = sections.length - 1;
      _jumpTo(_index);
    }
    if (widget.requestRevision != oldWidget.requestRevision &&
        widget.requestedSection != null) {
      final index = sections.indexOf(widget.requestedSection!);
      if (index >= 0) {
        _index = index;
        _jumpTo(index);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static int _indexOf(List<GlanceSection> sections, GlanceSection? section) {
    if (sections.isEmpty) return 0;
    final index = section == null ? -1 : sections.indexOf(section);
    return index < 0 ? 0 : index;
  }

  void _jumpTo(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      if (_controller.page?.round() == index) return;
      _controller.jumpToPage(index);
    });
  }

  void _select(int index) {
    if (index == _index) return;
    if (_controller.hasClients) {
      unawaited(
        _controller.animateToPage(
          index,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        ),
      );
    } else {
      setState(() => _index = index);
    }
  }

  String _sectionLabel(GlanceSection section) => switch (section) {
        GlanceSection.courses => '课程',
        GlanceSection.assignments => '作业',
        GlanceSection.payment => '消费码',
      };

  Widget _page(BuildContext context, GlanceSection section, bool compact) {
    final onRetry = widget.onRefresh;
    return switch (section) {
      GlanceSection.courses => compact
          ? RearCoursesPage(snapshot: widget.snapshot, onRetry: onRetry)
          : CoverCoursesPage(snapshot: widget.snapshot, onRetry: onRetry),
      GlanceSection.assignments => compact
          ? RearAssignmentsPage(snapshot: widget.snapshot, onRetry: onRetry)
          : CoverAssignmentsPage(snapshot: widget.snapshot, onRetry: onRetry),
      GlanceSection.payment => Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 10 : 14,
            compact ? 2 : 4,
            compact ? 10 : 14,
            compact ? 2 : 6,
          ),
          child: widget.paymentBuilder!(context),
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = theme.scaffoldBackgroundColor;
    final dark = theme.brightness == Brightness.dark;
    final overlay = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: background,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness:
          dark ? Brightness.light : Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        backgroundColor: background,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final sections = _sections;
              if (sections.isEmpty) {
                return const GlanceMessage(
                  icon: Icons.dashboard_customize_outlined,
                  title: '未选择显示内容',
                  subtitle: '请在完整 App 的“背屏与小屏”中开启至少一项',
                );
              }
              final compact = widget.surface == GlanceSurface.rear &&
                  constraints.maxWidth > constraints.maxHeight;
              final wide = widget.surface == GlanceSurface.cover;
              final selectedIndex = _index.clamp(0, sections.length - 1);
              final section = sections[selectedIndex];
              return Column(
                children: [
                  _GlanceHeader(
                    now: widget.snapshot.now,
                    week: widget.snapshot.week,
                    inTerm: widget.snapshot.inTerm,
                    sectionLabel: _sectionLabel(section),
                    compact: compact,
                    wide: wide,
                    onRefresh: widget.onRefresh,
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _controller,
                      itemCount: sections.length,
                      onPageChanged: (index) {
                        setState(() => _index = index);
                        widget.onPageChanged?.call(sections[index]);
                      },
                      itemBuilder: (context, index) => TickerMode(
                        enabled: index == selectedIndex,
                        child: _page(context, sections[index], compact),
                      ),
                    ),
                  ),
                  _GlanceTabs(
                    sections: sections,
                    selectedIndex: selectedIndex,
                    compact: compact,
                    labelOf: _sectionLabel,
                    onSelected: _select,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _GlanceHeader extends StatelessWidget {
  const _GlanceHeader({
    required this.now,
    required this.week,
    required this.inTerm,
    required this.sectionLabel,
    required this.compact,
    required this.wide,
    this.onRefresh,
  });

  final DateTime now;
  final int? week;
  final bool inTerm;
  final String sectionLabel;
  final bool compact;
  final bool wide;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final date = formatGlanceDateLine(
      now: now,
      week: week,
      inTerm: inTerm,
    );
    if (compact) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(10, 1, 10, 1),
        child: Row(
          children: [
            Text(
              formatGlanceClock(now),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                date,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              sectionLabel,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    if (wide) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 2),
        child: Row(
          children: [
            Text(
              formatGlanceClock(now),
              style: TextStyle(
                fontSize: 24,
                height: 1,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                date,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              sectionLabel,
              maxLines: 1,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: colors.onSurface,
              ),
            ),
            if (onRefresh != null)
              _GlanceRefreshButton(onRefresh: onRefresh!),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 3),
      child: Row(
        children: [
          Text(
            formatGlanceClock(now),
            style: TextStyle(
              fontSize: 22,
              height: 1,
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  date,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                Text(
                  sectionLabel,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
                  ),
                ),
              ],
            ),
          ),
          if (onRefresh != null)
            _GlanceRefreshButton(onRefresh: onRefresh!),
        ],
      ),
    );
  }
}

class _GlanceRefreshButton extends StatelessWidget {
  const _GlanceRefreshButton({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '刷新',
      button: true,
      child: IconButton(
        onPressed: onRefresh,
        icon: const Icon(Icons.refresh, size: 18),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(
          width: 32,
          height: 32,
        ),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _GlanceTabs extends StatelessWidget {
  const _GlanceTabs({
    required this.sections,
    required this.selectedIndex,
    required this.compact,
    required this.labelOf,
    required this.onSelected,
  });

  final List<GlanceSection> sections;
  final int selectedIndex;
  final bool compact;
  final String Function(GlanceSection section) labelOf;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(8, compact ? 1 : 3, 8, compact ? 2 : 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var index = 0; index < sections.length; index++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Semantics(
                selected: index == selectedIndex,
                button: true,
                child: Material(
                  color: index == selectedIndex
                      ? colors.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    onTap: () => onSelected(index),
                    borderRadius: BorderRadius.circular(999),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 8 : 11,
                        vertical: compact ? 3 : 5,
                      ),
                      child: Text(
                        labelOf(sections[index]),
                        style: TextStyle(
                          fontSize: compact ? 9 : 11,
                          fontWeight: index == selectedIndex
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: index == selectedIndex
                              ? colors.onPrimary
                              : colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
