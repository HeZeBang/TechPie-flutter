import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/course_table.dart';

/// Shared shell extracted from the timetable's semester picker.
/// Edits remain pending until the user confirms; dismissing returns null.
Future<T?> showSchedulePickerSheet<T>({
  required BuildContext context,
  required String title,
  required T Function() selection,
  required WidgetBuilder builder,
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
                  Expanded(
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, selection()),
                    child: const Text('确定'),
                  ),
                ],
              ),
            ),
            Flexible(child: builder(context)),
          ],
        ),
      ),
    ),
  );
}

Future<String?> showSemesterPickerSheet({
  required BuildContext context,
  required SemesterInfo info,
  required String? initialSemesterId,
}) {
  final years = info.semesters.keys.where((year) => info.semesters[year]!.isNotEmpty).toList()
    ..sort();
  if (years.isEmpty) return Future.value();
  final firstTerms = info.semesters[years.first]!.entries.toList()
    ..sort((a, b) => semesterTermRank(a.key).compareTo(semesterTermRank(b.key)));
  final validInitial = info.semesters.values.any((terms) => terms.containsValue(initialSemesterId));
  final initialSelection = validInitial ? initialSemesterId! : firstTerms.first.value;
  var pending = initialSelection;
  return showSchedulePickerSheet<String>(
    context: context,
    title: '选择学期',
    selection: () => pending,
    builder: (_) => SemesterWheelPicker(
      info: info,
      initialSemesterId: initialSelection,
      onSelectionChanged: (value) => pending = value,
    ),
  );
}

/// Two synced scroll wheels (academic year, then term) for picking a semester.
/// Reports the pending selection live via [onSelectionChanged]; the caller is
/// responsible for confirming (or discarding) it.
class SemesterWheelPicker extends StatefulWidget {
  final SemesterInfo info;
  final String? initialSemesterId;
  final ValueChanged<String> onSelectionChanged;

  const SemesterWheelPicker({
    super.key,
    required this.info,
    required this.initialSemesterId,
    required this.onSelectionChanged,
  });

  @override
  State<SemesterWheelPicker> createState() => _SemesterWheelPickerState();
}

class _SemesterWheelPickerState extends State<SemesterWheelPicker> {
  late final List<String> _years;
  late FixedExtentScrollController _yearController;
  late FixedExtentScrollController _termController;
  late List<MapEntry<String, String>> _termsForYear;
  late int _yearIndex;
  late int _termIndex;

  @override
  void initState() {
    super.initState();
    _years = widget.info.semesters.keys
        .where((year) => widget.info.semesters[year]!.isNotEmpty)
        .toList()
      ..sort();

    var yearIndex = 0;
    String? initialLabel;
    final initialId = widget.initialSemesterId;
    if (initialId != null) {
      for (var i = 0; i < _years.length; i++) {
        for (final entry in widget.info.semesters[_years[i]]!.entries) {
          if (entry.value == initialId) {
            yearIndex = i;
            initialLabel = entry.key;
          }
        }
      }
    }

    _yearIndex = yearIndex;
    _termsForYear = _orderedTerms(_years[_yearIndex]);
    final labelIndex =
        initialLabel == null ? -1 : _termsForYear.indexWhere((entry) => entry.key == initialLabel);
    _termIndex = labelIndex < 0 ? 0 : labelIndex;

    _yearController = FixedExtentScrollController(initialItem: _yearIndex);
    _termController = FixedExtentScrollController(initialItem: _termIndex);
  }

  @override
  void dispose() {
    _yearController.dispose();
    _termController.dispose();
    super.dispose();
  }

  List<MapEntry<String, String>> _orderedTerms(String year) {
    final terms = widget.info.semesters[year] ?? const <String, String>{};
    final entries = terms.entries.toList()
      ..sort(
        (a, b) => semesterTermRank(a.key).compareTo(semesterTermRank(b.key)),
      );
    return entries;
  }

  void _reportSelection() {
    if (_termIndex >= _termsForYear.length) return;
    widget.onSelectionChanged(_termsForYear[_termIndex].value);
  }

  void _onYearChanged(int index) {
    final previousLabel = _termIndex < _termsForYear.length ? _termsForYear[_termIndex].key : null;

    setState(() {
      _yearIndex = index;
      _termsForYear = _orderedTerms(_years[_yearIndex]);
      final labelIndex = previousLabel == null
          ? -1
          : _termsForYear.indexWhere((entry) => entry.key == previousLabel);
      _termIndex = labelIndex < 0 ? 0 : labelIndex.clamp(0, _termsForYear.length - 1);
    });
    _termController.jumpToItem(_termIndex);
    _reportSelection();
  }

  void _onTermChanged(int index) {
    setState(() => _termIndex = index);
    _reportSelection();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: SchedulePickerWheel(
              controller: _yearController,
              itemCount: _years.length,
              labelBuilder: (i) => _years[i],
              onChanged: _onYearChanged,
            ),
          ),
          Expanded(
            flex: 2,
            child: SchedulePickerWheel(
              controller: _termController,
              itemCount: _termsForYear.length,
              labelBuilder: (i) => '${semesterTermDisplayName(_termsForYear[i].key)}学期',
              onChanged: _onTermChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class SchedulePickerWheel extends StatelessWidget {
  const SchedulePickerWheel({
    super.key,
    required this.controller,
    required this.itemCount,
    required this.labelBuilder,
    required this.onChanged,
  });

  final FixedExtentScrollController controller;
  final int itemCount;
  final String Function(int) labelBuilder;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CupertinoPicker(
      scrollController: controller,
      itemExtent: 40,
      onSelectedItemChanged: onChanged,
      selectionOverlay: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      children: [
        for (var i = 0; i < itemCount; i++)
          Center(child: Text(labelBuilder(i), style: theme.textTheme.bodyLarge)),
      ],
    );
  }
}

/// Retains the field's appearance while giving every input method one action.
class SchedulePickerField extends StatelessWidget {
  const SchedulePickerField({super.key, required this.child, required this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => FocusableActionDetector(
        enabled: onTap != null,
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              onTap?.call();
              return null;
            },
          ),
        },
        child: Semantics(
          button: true,
          enabled: onTap != null,
          onTap: onTap,
          child: GestureDetector(
            excludeFromSemantics: true,
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: ExcludeFocus(child: AbsorbPointer(child: child)),
          ),
        ),
      );
}
