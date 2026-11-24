import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/library_reservation_service.dart';
import '../services/service_provider.dart';
import '../services/third_party_auth_service.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_alert_dialog.dart';
import '../widgets/adaptive_button.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/adaptive_segmented_control.dart';
import '../widgets/adaptive_select.dart';
import '../widgets/adaptive_switch.dart';
import '../widgets/adaptive_text_field_group.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';
import '../widgets/library_reservation_timeline.dart';
import 'library_reservation_records_page.dart';

class LibraryReservationPage extends StatefulWidget {
  const LibraryReservationPage({super.key});

  @override
  State<LibraryReservationPage> createState() => _LibraryReservationPageState();
}

class _LibraryReservationPageState extends State<LibraryReservationPage> {
  LibraryReservationService? _service;
  AuthService? _auth;
  ThirdPartyAuthService? _thirdPartyAuth;
  String? _primaryOwner;
  String? _campusOwner;
  LibrarySpaceType _type = LibrarySpaceType.discussion;
  late DateTime _date;
  DateTime? _endDate;
  LibraryAvailability? _availability;
  LibraryRoom? _room;
  int? _start;
  int? _end;
  bool _continuous = false;
  bool _choosingEnd = false;
  bool _loading = true;
  bool _submitting = false;
  bool _reopenRequired = false;
  String? _error;
  int _request = 0;
  Route<dynamic>? _bookingDialog;
  final _timelineOffset = ValueNotifier<double>(0);

  bool get _compactTimeline => MediaQuery.sizeOf(context).shortestSide < 600;

  @override
  void initState() {
    super.initState();
    _date = _day(LibraryReservationService.campusNow);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_service != null) return;
    final services = ServiceProvider.of(context);
    _auth = services.authService;
    _thirdPartyAuth = services.thirdPartyAuthService;
    _primaryOwner = _auth!.session?.userId;
    _campusOwner = _thirdPartyAuth!.campusWebSession.owner;
    _auth!.addListener(_identityChanged);
    _thirdPartyAuth!.addListener(_identityChanged);
    _service = LibraryReservationService(_thirdPartyAuth!);
    if (_auth!.isLoggedIn) {
      unawaited(_load());
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _auth?.removeListener(_identityChanged);
    _thirdPartyAuth?.removeListener(_identityChanged);
    _service?.close();
    _timelineOffset.dispose();
    super.dispose();
  }

  bool get _sameIdentity =>
      _auth!.isLoggedIn &&
      _auth!.session?.userId == _primaryOwner &&
      _thirdPartyAuth!.campusWebSession.owner == _campusOwner;

  void _identityChanged() {
    if (!mounted || _reopenRequired || _sameIdentity) return;
    final dialog = _bookingDialog;
    if (dialog != null && dialog.isActive) {
      dialog.navigator!.removeRoute(dialog);
    }
    _request++;
    setState(() {
      _reopenRequired = true;
      _loading = false;
      _submitting = false;
      _availability = null;
      _room = null;
      _start = null;
      _end = null;
      _error = null;
    });
  }

  Future<void> _load() async {
    if (_reopenRequired || !_sameIdentity) {
      _identityChanged();
      return;
    }
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      _room = null;
      _start = null;
      _end = null;
    });
    try {
      final availability = await _service!.load(
        _type,
        _date,
        through: _continuous ? _endDate : null,
      );
      if (!mounted || request != _request || !_sameIdentity) return;
      setState(() {
        _availability = availability;
        _loading = false;
        if (_type == LibrarySpaceType.study && _continuous) {
          _endDate ??= _date;
        }
      });
    } catch (error) {
      if (!mounted || request != _request || !_sameIdentity) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _openRecords() {
    unawaited(
      pushAdaptivePage<void>(
        context,
        builder: (_) => LibraryReservationRecordsPage(
          service: _service!,
          onCancelled: () {
            if (mounted && _sameIdentity) unawaited(_load());
          },
        ),
      ),
    );
  }

  void _selectDate(DateTime day) {
    if (_continuous && _choosingEnd) {
      if (day.isBefore(_date) || day == _endDate) return;
      setState(() => _endDate = day);
    } else {
      if (day == _date) return;
      setState(() {
        _date = day;
        if (_endDate?.isBefore(day) ?? false) _endDate = day;
      });
    }
    unawaited(_load());
  }

  List<int> _endsFor(LibraryAvailability availability, LibraryRoom room, int start) {
    final latest = availability.latestEnd(room, start);
    return [
      for (var end = start + availability.stepMinutes;
          end <= latest;
          end += availability.stepMinutes)
        if (end - start >= availability.minMinutes) end,
    ];
  }

  bool _roomSelectable(LibraryRoom room) {
    if (room.disabled) return false;
    final availability = _availability!;
    if (!_continuous) return availability.startTimes(room).isNotEmpty;
    for (var slot = availability.openStart;
        slot < availability.openEnd;
        slot += availability.stepMinutes) {
      if (availability.statusAt(room, slot) != LibrarySlotStatus.available) return false;
    }
    return true;
  }

  Future<void> _confirm() async {
    final availability = _availability;
    final room = _room;
    final start = _start;
    final end = _end;
    if (availability == null ||
        room == null ||
        start == null ||
        end == null ||
        _submitting) {
      return;
    }
    final today = _day(LibraryReservationService.campusNow);
    final last = today.add(Duration(days: availability.cycleDays - 1));
    final finalDate = _continuous ? (_endDate ?? _date) : _date;
    final validSelection = _continuous
        ? _roomSelectable(room) &&
            start == availability.openStart &&
            end == availability.openEnd
        : availability.startTimes(room).contains(start) &&
            end >= start + availability.minMinutes &&
            end <= availability.latestEnd(room, start) &&
            (end - start) % availability.stepMinutes == 0;
    if (_date.isBefore(today) ||
        _date.isAfter(last) ||
        finalDate.isBefore(_date) ||
        finalDate.isAfter(last) ||
        !validSelection) {
      showAdaptiveFeedback(
        context: context,
        message: '预约日期或时段已失效，请重新选择',
        style: AdaptiveFeedbackStyle.error,
      );
      return;
    }
    final type = _type;
    final continuous = _continuous;
    final dates = continuous ? _days(_date, _endDate ?? _date) : [_date];
    setState(() => _submitting = true);
    try {
      final details = type == LibrarySpaceType.discussion
          ? await _discussionDetails()
          : const _DiscussionDetails();
      if (details == null || !mounted || !_sameIdentity) return;
      final confirmed = await showAdaptiveAlertDialog<bool>(
        context: context,
        title: '确认预约',
        message: '${type.label} · ${room.name}\n'
            '${_dateLabel(dates.first)}${dates.length > 1 ? ' 至 ${_dateLabel(dates.last)}' : ''}\n'
            '${_time(start)}–${_time(end)}',
        actions: const [
          AdaptiveAlertAction(label: '取消', value: false),
          AdaptiveAlertAction(label: '提交预约', value: true, isDefault: true),
        ],
      );
      if (confirmed != true || !mounted || !_sameIdentity) return;
      await _service!.book(
        type: type,
        room: room,
        dates: dates,
        start: start,
        end: end,
        continuous: continuous,
        meetingType: details.meetingType,
        topic: details.topic,
        participants: details.participants,
      );
      if (!mounted || !_sameIdentity) return;
      showAdaptiveFeedback(
        context: context,
        message: '预约成功',
        style: AdaptiveFeedbackStyle.success,
      );
      await _load();
    } catch (error) {
      if (!mounted || !_sameIdentity) return;
      showAdaptiveFeedback(
        context: context,
        message: error.toString(),
        style: AdaptiveFeedbackStyle.error,
      );
    } finally {
      if (mounted && _sameIdentity) setState(() => _submitting = false);
    }
  }

  Future<_DiscussionDetails?> _discussionDetails() async {
    final options = await _service!.discussionOptions();
    if (!mounted || !_sameIdentity) return null;
    return _showBookingDialog<_DiscussionDetails>(
      (_) => _DiscussionDialog(
        service: _service!,
        types: options.types,
        topics: options.topics,
      ),
    );
  }

  Future<T?> _showBookingDialog<T>(WidgetBuilder builder) async {
    final route = DialogRoute<T>(context: context, builder: builder);
    _bookingDialog = route;
    try {
      return await Navigator.of(context).push(route);
    } finally {
      _bookingDialog = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final canBook = !_reopenRequired &&
        (_auth?.isLoggedIn ?? false) &&
        _room != null &&
        _start != null &&
        _end != null;
    final canOpenRecords = !_submitting && !_reopenRequired && _sameIdentity;
    return Scaffold(
      appBar: isIos()
          ? IosNativeNavigationBar(
              title: '图书馆预约',
              leadingItems: const [
                IosNativeNavigationBarItem(
                  id: 'back',
                  sfSymbol: 'chevron.left',
                  accessibilityLabel: '返回',
                ),
              ],
              trailingItems: [
                IosNativeNavigationBarItem(
                  id: 'records',
                  title: '我的预约',
                  enabled: canOpenRecords,
                ),
              ],
              onItemPressed: (id) {
                if (id == 'back') unawaited(maybePopAdaptivePage<void>(context));
                if (id == 'records' && canOpenRecords) _openRecords();
              },
            )
          : BlurredAppBar(
              leading: const BackButton(),
              title: const Text('图书馆预约'),
              actions: [
                OutlinedButton(
                  onPressed: canOpenRecords ? _openRecords : null,
                  child: const Text('我的预约'),
                ),
                const SizedBox(width: 8),
              ],
            ),
      body: _reopenRequired
          ? const _Message(
              icon: Icons.manage_accounts_outlined,
              text: '账号已切换，请关闭并重新打开此页面',
            )
          : !_auth!.isLoggedIn
              ? const _Message(icon: Icons.login, text: '请先登录 TechPie')
              : ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                  child: _body(),
                ),
      bottomNavigationBar: canBook ? _bookingFooter() : null,
    );
  }

  Widget _body() {
    final availability = _availability;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AdaptiveSegmentedControl(
                    value: _type.index,
                    segments: [for (final type in LibrarySpaceType.values) type.label],
                    onChanged: _submitting
                        ? null
                        : (index) {
                            final type = LibrarySpaceType.values[index];
                            if (_type == type) return;
                            setState(() {
                              _type = type;
                              _availability = null;
                              _continuous = false;
                              _choosingEnd = false;
                              _endDate = null;
                            });
                            unawaited(_load());
                          },
                  ),
                  const SizedBox(height: 14),
                  if (_type == LibrarySpaceType.study) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('连续整天预约'),
                      subtitle: const Text('只显示所选日期共同可用的时段'),
                      trailing: Semantics(
                        label: '连续整天预约',
                        child: AdaptiveSwitch(
                          value: _continuous,
                          enabled: availability != null && !_submitting,
                          onChanged: (value) {
                            setState(() {
                              _continuous = value;
                              _choosingEnd = false;
                              _endDate = value ? _date : null;
                            });
                            unawaited(_load());
                          },
                        ),
                      ),
                    ),
                  ],
                  if (availability != null) ...[
                    if (_continuous) ...[
                      AdaptiveSegmentedControl(
                        value: _choosingEnd ? 1 : 0,
                        segments: [
                          '开始 ${_date.month}/${_date.day}',
                          '结束 ${(_endDate ?? _date).month}/${(_endDate ?? _date).day}',
                        ],
                        onChanged: _submitting
                            ? null
                            : (index) => setState(() => _choosingEnd = index == 1),
                      ),
                      const SizedBox(height: 4),
                    ],
                    _dateStrip(availability),
                  ],
                  if (availability != null) ...[
                    const SizedBox(height: 10),
                    const LibraryReservationLegend(),
                    if (_compactTimeline) ...[
                      const SizedBox(height: 6),
                      Text(
                        '左右滑动查看，每屏最多 8 小时',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ],
              ),
            ),
            Expanded(child: _roomList()),
          ],
        ),
      ),
    );
  }

  Widget _dateStrip(LibraryAvailability availability) {
    final today = _day(LibraryReservationService.campusNow);
    final count = availability.cycleDays;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final native = isIos();
    final end = _continuous ? (_endDate ?? _date) : _date;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final gap = width >= count * 56 ? 8.0 : 4.0;
        final dayWidth = ((width - gap * (count - 1)) / count)
            .clamp(native ? 76.0 : 44.0, double.infinity);
        return SizedBox(
          height: 60,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: count,
            separatorBuilder: (_, __) => SizedBox(width: gap),
            itemBuilder: (context, index) {
              final day = today.add(Duration(days: index));
              final selected = day == _date || day == end;
              final inRange = day.isAfter(_date) && day.isBefore(end);
              final enabled = !_submitting &&
                  !(_continuous && _choosingEnd && day.isBefore(_date));
              final label = '${_dateLabel(day)}，${_weekday(day)}'
                  '${inRange ? '，已选范围内' : ''}';
              if (native) {
                return Semantics(
                  selected: selected || inRange,
                  child: AdaptiveButton(
                    width: dayWidth,
                    height: 54,
                    label: '${day.month}/${day.day}',
                    subtitle: _weekday(day),
                    accessibilityLabel: label,
                    icon: Icons.calendar_today,
                    sfSymbol: 'calendar',
                    role: selected
                        ? AdaptiveButtonRole.prominent
                        : inRange
                            ? AdaptiveButtonRole.standard
                            : AdaptiveButtonRole.plain,
                    onPressed: enabled ? () => _selectDate(day) : null,
                  ),
                );
              }
              return SizedBox(
                width: dayWidth,
                child: Semantics(
                  label: label,
                  child: ChoiceChip(
                    selected: selected,
                    showCheckmark: false,
                    selectedColor: colors.primaryContainer,
                    backgroundColor: inRange ? colors.secondaryContainer : null,
                    side: BorderSide(
                      color: selected ? colors.primary : colors.outlineVariant,
                      width: selected ? 1.5 : 1,
                    ),
                    labelPadding: EdgeInsets.zero,
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    label: SizedBox(
                      width: dayWidth,
                      child: ExcludeSemantics(
                        child: DefaultTextStyle(
                          style: (theme.textTheme.labelMedium ?? const TextStyle()).copyWith(
                            color: selected
                                ? colors.onPrimaryContainer
                                : inRange
                                    ? colors.onSecondaryContainer
                                    : colors.onSurfaceVariant,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              FittedBox(child: Text(_weekday(day))),
                              const SizedBox(height: 2),
                              FittedBox(child: Text('${day.month}/${day.day}')),
                            ],
                          ),
                        ),
                      ),
                    ),
                    onSelected: enabled ? (_) => _selectDate(day) : null,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _roomList() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(semanticsLabel: '正在查询所选日期的可用时段'),
      );
    }
    if (_error != null) {
      return _Message(
        icon: Icons.error_outline,
        text: _error!,
        action: TextButton(onPressed: _load, child: const Text('重试')),
      );
    }
    final availability = _availability!;
    if (availability.rooms.isEmpty) {
      return const _Message(icon: Icons.event_busy, text: '当天没有房间信息');
    }
    final anySelectable = availability.rooms.any(_roomSelectable);
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        16,
        4,
        16,
        _end == null ? MediaQuery.paddingOf(context).bottom + 16 : 16,
      ),
      itemCount: availability.rooms.length + (anySelectable ? 0 : 1),
      itemBuilder: (context, index) {
        if (!anySelectable && index == 0) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: _Message(icon: Icons.event_busy, text: '当天没有可预约房间'),
          );
        }
        final room = availability.rooms[index - (anySelectable ? 0 : 1)];
        return _roomCard(availability, room);
      },
    );
  }

  Widget _roomCard(LibraryAvailability availability, LibraryRoom room) {
    final selected = identical(room, _room);
    final selectable = _roomSelectable(room);
    final selection = selected && _start != null && _end != null
        ? (start: _start!, end: _end!)
        : null;
    final capacity = room.capacity == null ? null : '${room.capacity} 人';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: selected
            ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(room.name, style: Theme.of(context).textTheme.titleMedium),
                      if (capacity != null)
                        Text(capacity, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                SizedBox(
                  width: 122,
                  child: AdaptiveButton(
                    onPressed: !selectable || _submitting
                        ? null
                        : () => setState(() {
                              _room = selected && !_continuous ? null : room;
                              _start = _continuous ? availability.openStart : null;
                              _end = _continuous ? availability.openEnd : null;
                            }),
                    icon: selected
                        ? (_continuous ? Icons.check : Icons.close)
                        : Icons.schedule,
                    sfSymbol: selected
                        ? (_continuous ? 'checkmark' : 'xmark')
                        : 'clock',
                    label: _continuous
                        ? (selected ? '已选择' : '选择房间')
                        : (selected ? '取消选择' : '选择时段'),
                    role: AdaptiveButtonRole.plain,
                    height: 44,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LibraryReservationTimeline(
              availability: availability,
              room: room,
              selection: selection,
              scrollOffset: _compactTimeline ? _timelineOffset : null,
            ),
            if (selected && !_continuous) ...[
              const SizedBox(height: 8),
              _roomTimeFields(availability, room),
            ],
          ],
        ),
      ),
    );
  }

  Widget _roomTimeFields(LibraryAvailability availability, LibraryRoom room) {
    final start = _start;
    final starts = _submitting ? const <int>[] : availability.startTimes(room).toList();
    final ends = _submitting || start == null
        ? const <int>[]
        : _endsFor(availability, room, start);
    return Column(
      children: [
        _TimeField(
          label: '开始',
          value: start,
          options: starts,
          onChanged: (value) {
            if (!mounted ||
                _submitting ||
                !identical(_room, room) ||
                !starts.contains(value)) {
              return;
            }
            setState(() {
              _start = value;
              if (!_endsFor(availability, room, value).contains(_end)) _end = null;
            });
          },
        ),
        const Divider(height: 1),
        _TimeField(
          label: '结束',
          value: _end,
          placeholder: start == null ? '先选开始' : '请选择',
          options: ends,
          onChanged: (value) {
            if (!mounted ||
                _submitting ||
                !identical(_room, room) ||
                _start != start ||
                !ends.contains(value)) {
              return;
            }
            setState(() => _end = value);
          },
        ),
      ],
    );
  }

  Widget _bookingFooter() {
    final room = _room!;
    final theme = Theme.of(context);
    final date = '${_date.month}/${_date.day}';
    final endDate = _endDate;
    final dates = _continuous && endDate != null && endDate != _date
        ? '$date–${endDate.month}/${endDate.day}'
        : date;
    final duration = _continuous ? '' : ' · ${_end! - _start!} 分钟';
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      shape: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1008),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        room.name,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '$dates · ${_time(_start!)}–${_time(_end!)}$duration',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Tooltip(
                  message: '清除已选时段',
                  excludeFromSemantics: isIos(),
                  child: AdaptiveButton(
                    accessibilityLabel: '清除已选时段',
                    role: AdaptiveButtonRole.plain,
                    height: 44,
                    onPressed: _submitting
                        ? null
                        : () => setState(() {
                              _room = null;
                              _start = null;
                              _end = null;
                            }),
                    icon: Icons.close,
                    sfSymbol: 'xmark',
                  ),
                ),
                SizedBox(
                  width: 122,
                  child: AdaptiveButton(
                    onPressed: _submitting ? null : _confirm,
                    icon: Icons.check_circle_outline,
                    sfSymbol: 'checkmark',
                    label: '确认预约',
                    role: AdaptiveButtonRole.prominent,
                    loading: _submitting,
                    height: 44,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DiscussionDialog extends StatefulWidget {
  const _DiscussionDialog({
    required this.service,
    required this.types,
    required this.topics,
  });

  final LibraryReservationService service;
  final Map<String, String> types;
  final Map<String, String> topics;

  @override
  State<_DiscussionDialog> createState() => _DiscussionDialogState();
}

class _DiscussionDialogState extends State<_DiscussionDialog> {
  final _search = TextEditingController();
  String? _type;
  String? _topic;
  bool _searching = false;
  String? _error;
  List<LibraryParticipant> _results = const [];
  final List<LibraryParticipant> _selected = [];

  @override
  void initState() {
    super.initState();
    _type = widget.types.keys.firstOrNull;
    _topic = widget.topics.keys.firstOrNull;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    final query = _search.text.trim();
    if (query.isEmpty || _searching) return;
    setState(() {
      _searching = true;
      _error = null;
      _results = const [];
    });
    try {
      final results = await widget.service.findParticipants(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('讨论室信息'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('会议类型'),
                  trailing: SizedBox(
                    width: 132,
                    child: AdaptiveSelect(
                      accessibilityLabel: '会议类型',
                      value: _type,
                      options: [
                        for (final entry in widget.types.entries)
                          AdaptiveSelectOption(value: entry.key, label: entry.value),
                      ],
                      onChanged: (value) => setState(() => _type = value),
                    ),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('主题'),
                  trailing: SizedBox(
                    width: 132,
                    child: AdaptiveSelect(
                      accessibilityLabel: '主题',
                      value: _topic,
                      options: [
                        for (final entry in widget.topics.entries)
                          AdaptiveSelectOption(value: entry.key, label: entry.value),
                      ],
                      onChanged: (value) => setState(() => _topic = value),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                AdaptiveTextFieldGroup(
                  items: [
                    AdaptiveTextFieldGroupItem(
                      controller: _search,
                      placeholder: '同行人姓名或学号（可选）',
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _find(),
                    ),
                  ],
                ),
                AdaptiveButton(
                  onPressed: _searching ? null : _find,
                  icon: Icons.search,
                  sfSymbol: 'magnifyingglass',
                  label: '搜索同行人',
                  role: AdaptiveButtonRole.plain,
                  loading: _searching,
                  height: 44,
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child:
                        Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                ..._results.map(
                  (person) => CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(person.name),
                    subtitle: Text(person.number),
                    value: _selected.any((item) => item.number == person.number),
                    onChanged: (selected) => setState(() {
                      if (selected == true) {
                        if (!_selected.any((item) => item.number == person.number)) {
                          _selected.add(person);
                        }
                      } else {
                        _selected.removeWhere((item) => item.number == person.number);
                      }
                    }),
                  ),
                ),
                if (_selected.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    children: _selected
                        .map(
                          (person) => InputChip(
                            label: Text(person.name),
                            onDeleted: () => setState(() => _selected.remove(person)),
                          ),
                        )
                        .toList(),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          SizedBox(
            width: 96,
            child: AdaptiveButton(
              onPressed: () => Navigator.pop(context),
              label: '取消',
              icon: Icons.close,
              sfSymbol: 'xmark',
              role: AdaptiveButtonRole.plain,
              height: 44,
            ),
          ),
          SizedBox(
            width: 96,
            child: AdaptiveButton(
              onPressed: _type == null || _topic == null
                  ? null
                  : () => Navigator.pop(
                        context,
                        _DiscussionDetails(
                          meetingType: _type!,
                          topic: _topic!,
                          participants: List.unmodifiable(_selected),
                        ),
                      ),
              label: '继续',
              icon: Icons.chevron_right,
              sfSymbol: 'chevron.right',
              role: AdaptiveButtonRole.prominent,
              height: 44,
            ),
          ),
        ],
      );
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.placeholder = '请选择',
  });

  final String label;
  final int? value;
  final String placeholder;
  final List<int> options;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        trailing: SizedBox(
          width: 126,
          child: AdaptiveSelect(
            accessibilityLabel: label,
            value: value?.toString(),
            placeholder: options.isEmpty && value != null ? _time(value!) : placeholder,
            useIosNativeMenu: true,
            width: 126,
            options: [
              for (final time in options)
                AdaptiveSelectOption(value: '$time', label: _time(time)),
            ],
            onChanged: (value) => onChanged(int.parse(value)),
          ),
        ),
      );
}

class _DiscussionDetails {
  const _DiscussionDetails({
    this.meetingType = '',
    this.topic = '',
    this.participants = const [],
  });

  final String meetingType;
  final String topic;
  final List<LibraryParticipant> participants;
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 42, color: Theme.of(context).colorScheme.secondary),
              const SizedBox(height: 12),
              Text(text, textAlign: TextAlign.center),
              if (action != null) action!,
            ],
          ),
        ),
      );
}

DateTime _day(DateTime value) => DateTime.utc(value.year, value.month, value.day);

List<DateTime> _days(DateTime first, DateTime last) => [
      for (var day = first; !day.isAfter(last); day = day.add(const Duration(days: 1))) day,
    ];

String _dateLabel(DateTime date) =>
    '${date.year}年${date.month.toString().padLeft(2, '0')}月${date.day.toString().padLeft(2, '0')}日';

String _time(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

String _weekday(DateTime date) =>
    const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][date.weekday - 1];
