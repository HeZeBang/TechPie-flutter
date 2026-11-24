import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/oa_gym.dart';
import '../../services/service_provider.dart';
import '../../theme/theme.dart';
import '../adaptive_button.dart';
import '../adaptive_date_picker.dart';
import '../app_shell/app_shell_metrics.dart';
import '../design_system/design_system.dart';
import 'gym_shared.dart';

class GymBookingTab extends StatefulWidget {
  const GymBookingTab({super.key});

  @override
  State<GymBookingTab> createState() => _GymBookingTabState();
}

class _GymBookingTabState extends State<GymBookingTab> {
  final Set<OaSport> _sports = {OaSport.badminton};
  final Map<String, Set<int>> _selectedCourts = {};
  DateTime _date = DateTime.now();
  RangeValues _timeRange = const RangeValues(18, 20);
  List<OaAvailability> _availability = [];
  bool _checking = false;
  bool _submitting = false;
  String? _error;
  String? _result;
  int _availabilityRequest = 0;
  bool _initialized = false;

  String get _dateString => gymFormatDate(_date);
  int get _startHour => _timeRange.start.round();
  int get _endHour => _timeRange.end.round();
  List<int> get _selectedSlots =>
      oaSlotIdsForEndpointRange(_startHour, _endHour);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      unawaited(_refreshAvailability());
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final maxDate = now.hour >= 12
        ? DateTime(now.year, now.month, now.day + 2)
        : DateTime(now.year, now.month, now.day + 1);
    final picked = await showAdaptiveDatePicker(
      context: context,
      title: '预约日期',
      initialDate: _date,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: maxDate,
    );
    if (picked == null) return;
    setState(() {
      _date = picked;
      _selectedCourts.clear();
      _result = null;
    });
    await _refreshAvailability();
  }

  Future<void> _refreshAvailability({bool preserveResult = false}) async {
    final request = ++_availabilityRequest;
    if (_sports.isEmpty) return;
    if (_selectedSlots.isEmpty) {
      setState(() {
        _checking = false;
        _error = '请选择有效时间段，例如 18:00 到 19:00';
        _availability = [];
        _selectedCourts.clear();
      });
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
      if (!preserveResult) _result = null;
      _availability = [];
      _selectedCourts.clear();
    });
    try {
      final service = ServiceProvider.of(context).oaGymService;
      final data = await service.checkAvailability(
        sports: _sports,
        date: _dateString,
        startSlot: _selectedSlots.first,
        endSlot: _selectedSlots.last,
        shouldContinue: () => mounted && request == _availabilityRequest,
        onProgress: (data) {
          if (mounted && request == _availabilityRequest) {
            setState(() => _availability = data);
          }
        },
      );
      if (!mounted || request != _availabilityRequest) return;
      setState(() => _availability = data);
    } catch (e) {
      if (!mounted || request != _availabilityRequest) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted && request == _availabilityRequest) {
        setState(() => _checking = false);
      }
    }
  }

  Future<void> _submit() async {
    if (_selectedCourts.isEmpty) {
      setState(
        () => _error = _selectedSlots.isEmpty ? '请选择有效时间段' : '请先选择可预约场地',
      );
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
      _result = null;
    });

    final service = ServiceProvider.of(context).oaGymService;
    final messages = <String>[];
    final date = _dateString;
    final selections = {
      for (final entry in _selectedCourts.entries)
        entry.key: Set<int>.of(entry.value),
    };
    final submitted = <String>{};
    var allSuccess = true;
    try {
      for (final entry in selections.entries) {
        final parts = entry.key.split('|');
        final sport = OaSport.values.firstWhere((item) => item.id == parts[0]);
        final slot = int.parse(parts[1]);
        for (final court in entry.value) {
          if (!submitted.add(
            '$slot|${oaCourtForSport(sport, court).physicalKey}',
          )) {
            continue;
          }
          final result = await service.bookCourt(
            sport: sport,
            date: date,
            timeSlot: slot,
            courtNumber: court,
            playersCount: 2,
          );
          messages.add(result.message);
          allSuccess = allSuccess && result.success;
        }
      }
      if (!mounted) return;
      setState(() {
        _result = messages.join('\n');
        if (allSuccess) _selectedCourts.clear();
      });
      await _refreshAvailability(preserveResult: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
      if (messages.isNotEmpty) {
        setState(() {
          _result = messages.join('\n');
          _selectedCourts.clear();
        });
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _toggleSport(OaSport sport) {
    setState(() {
      if (_sports.contains(sport)) {
        if (_sports.length > 1) _sports.remove(sport);
      } else {
        _sports.add(sport);
      }
      _selectedCourts.clear();
      _result = null;
    });
    unawaited(_refreshAvailability());
  }

  void _toggleCourt(String key, int court) {
    setState(() {
      final set = _selectedCourts.putIfAbsent(key, () => <int>{});
      if (set.contains(court)) {
        set.remove(court);
      } else {
        final parts = key.split('|');
        final sport =
            OaSport.values.firstWhere((sport) => sport.id == parts[0]);
        final physical = oaCourtForSport(sport, court).physicalKey;
        for (final entry in _selectedCourts.entries) {
          final other = entry.key.split('|');
          if (entry.key == key || other[1] != parts[1]) continue;
          final otherSport =
              OaSport.values.firstWhere((sport) => sport.id == other[0]);
          entry.value.removeWhere(
            (number) =>
                oaCourtForSport(otherSport, number).physicalKey == physical,
          );
        }
        set.add(court);
      }
      _selectedCourts.removeWhere((_, courts) => courts.isEmpty);
      _result = null;
    });
  }

  int get _selectedCount =>
      _selectedCourts.values.fold(0, (sum, set) => sum + set.length);

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final grouped = {
      for (final item in _availability) item.key: item,
    };

    return ListView(
      padding: EdgeInsets.fromLTRB(
        TpTokens.pageHorizontalPadding,
        TpTokens.space3,
        TpTokens.pageHorizontalPadding,
        AppShellMetrics.bottomContentPaddingOf(context),
      ),
      children: [
        TpPageBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TpCard(
                leadingIcon: TpIcons.gym,
                title: '预约条件',
                trailing: TpBadge(
                  label: oaEndpointRangeLabel(_startHour, _endHour),
                  tone: _selectedSlots.isEmpty
                      ? TpBadgeTone.danger
                      : TpBadgeTone.brand,
                ),
                padding: const EdgeInsets.fromLTRB(
                  TpTokens.cardPaddingHorizontal,
                  TpTokens.space1,
                  TpTokens.cardPaddingHorizontal,
                  TpTokens.space4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: TpTokens.space2,
                      runSpacing: TpTokens.space2,
                      children: [
                        for (final sport in OaSport.values)
                          FilterChip(
                            selected: _sports.contains(sport),
                            label: Text(sport.label),
                            avatar: Icon(gymSportIcon(sport), size: 18),
                            onSelected:
                                _submitting ? null : (_) => _toggleSport(sport),
                          ),
                      ],
                    ),
                    const SizedBox(height: TpTokens.space2),
                    Divider(height: 1, thickness: 0.5, color: colors.divider),
                    InkWell(
                      onTap: _submitting ? null : _pickDate,
                      borderRadius: BorderRadius.circular(TpTokens.radiusS),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            Icon(
                              TpIcons.calendar,
                              size: TpTokens.iconM,
                              color: colors.brandInk,
                            ),
                            const SizedBox(width: TpTokens.space3),
                            Expanded(
                              child: Text(
                                '预约日期',
                                style: TpTypography.itemTitle(colors)
                                    .copyWith(fontWeight: FontWeight.w500),
                              ),
                            ),
                            Text(
                              _dateString,
                              style: TpTypography.itemMeta(colors),
                            ),
                            const SizedBox(width: TpTokens.space1),
                            Icon(
                              TpIcons.chevronRight,
                              size: TpTokens.iconS,
                              color: colors.textMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Divider(height: 1, thickness: 0.5, color: colors.divider),
                    const SizedBox(height: TpTokens.space3),
                    Row(
                      children: [
                        Text(
                          '时间段',
                          style: TpTypography.itemTitle(colors)
                              .copyWith(fontSize: 14),
                        ),
                        const SizedBox(width: TpTokens.space2),
                        Text(
                          oaEndpointRangeLabel(_startHour, _endHour),
                          style: TpTypography.itemMeta(colors),
                        ),
                      ],
                    ),
                    if (_selectedSlots.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: TpTokens.space1),
                        child: Text(
                          '左右端点不能重合。请至少选择 1 小时时段。',
                          style: TpTypography.itemMeta(colors).copyWith(
                            color: colors.dangerRed,
                          ),
                        ),
                      ),
                    RangeSlider(
                      values: _timeRange,
                      min: oaTimeEndpointStart.toDouble(),
                      max: oaTimeEndpointEnd.toDouble(),
                      divisions: oaTimeEndpointEnd - oaTimeEndpointStart,
                      labels: RangeLabels(
                        '${_startHour.toString().padLeft(2, '0')}:00',
                        '${_endHour.toString().padLeft(2, '0')}:00',
                      ),
                      onChanged: _submitting
                          ? null
                          : (value) {
                              setState(() {
                                _availabilityRequest++;
                                _checking = false;
                                _timeRange = value;
                                _availability = [];
                                _selectedCourts.clear();
                              });
                            },
                      onChangeEnd: (_) => unawaited(_refreshAvailability()),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: AdaptiveButton(
                        onPressed: _checking || _submitting
                            ? null
                            : _refreshAvailability,
                        icon: TpIcons.refresh,
                        sfSymbol: 'arrow.clockwise',
                        label: '刷新可用场地',
                        role: AdaptiveButtonRole.plain,
                        loading: _checking,
                        width: 170,
                        height: 44,
                        accessibilityLabel: '刷新可用场地',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: TpTokens.sectionGap),
              if (_error != null) ...[
                GymMessageCard(message: _error!, isError: true),
                const SizedBox(height: TpTokens.sectionGap),
              ],
              if (_result != null) ...[
                GymMessageCard(message: _result!, isError: false),
                const SizedBox(height: TpTokens.sectionGap),
              ],
              if (_checking)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: TpTokens.space3),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: TpTokens.space3),
                      Text(
                        '正在查询 ${_availability.length}/${_sports.length * _selectedSlots.length} 个时段',
                        style: TpTypography.itemMeta(colors),
                      ),
                    ],
                  ),
                ),
              for (final sport in _sports) ...[
                TpCard(
                  leadingIcon: gymSportIcon(sport),
                  title: sport.label,
                  padding: const EdgeInsets.fromLTRB(
                    TpTokens.cardPaddingHorizontal,
                    TpTokens.space1,
                    TpTokens.cardPaddingHorizontal,
                    TpTokens.space2,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < _selectedSlots.length; i++)
                        _AvailabilitySlot(
                          sport: sport,
                          slot: _selectedSlots[i],
                          availability:
                              grouped['${sport.id}|${_selectedSlots[i]}'],
                          selectedCourts:
                              _selectedCourts['${sport.id}|${_selectedSlots[i]}'] ??
                                  const {},
                          enabled: !_submitting && !_checking,
                          showDivider: i < _selectedSlots.length - 1,
                          onToggleCourt: (court) => _toggleCourt(
                            '${sport.id}|${_selectedSlots[i]}',
                            court,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: TpTokens.sectionGap),
              ],
              AdaptiveButton(
                onPressed: _submitting || _checking || _selectedCount == 0
                    ? null
                    : _submit,
                icon: Icons.send,
                sfSymbol: 'paperplane.fill',
                label:
                    _selectedCount == 0 ? '提交预约' : '提交预约 ($_selectedCount)',
                role: AdaptiveButtonRole.prominent,
                loading: _submitting,
                height: 46,
                accessibilityLabel: '提交场馆预约',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AvailabilitySlot extends StatelessWidget {
  const _AvailabilitySlot({
    required this.sport,
    required this.slot,
    required this.availability,
    required this.selectedCourts,
    required this.onToggleCourt,
    this.enabled = true,
    this.showDivider = false,
  });

  final OaSport sport;
  final int slot;
  final OaAvailability? availability;
  final Set<int> selectedCourts;
  final ValueChanged<int> onToggleCourt;
  final bool enabled;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final courts = oaCourtsForSport(sport);
    final time = oaTimeSlots[slot - 1];
    final available = availability?.availableCourts ?? const <int>[];
    final badgeLabel = availability == null
        ? '未加载'
        : '${available.length}/${courts.length} 可用';
    final badgeTone = availability == null
        ? TpBadgeTone.muted
        : available.isEmpty
            ? TpBadgeTone.danger
            : TpBadgeTone.success;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: TpTokens.space2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    time.range,
                    style: TpTypography.itemTitle(colors).copyWith(
                      fontSize: 14,
                      fontFeatures: TpTypography.tabularFigures,
                    ),
                  ),
                  const SizedBox(width: TpTokens.space2),
                  TpBadge(label: badgeLabel, tone: badgeTone),
                ],
              ),
              const SizedBox(height: TpTokens.space2),
              Wrap(
                spacing: TpTokens.space2,
                runSpacing: TpTokens.space2,
                children: [
                  for (final court in courts)
                    ChoiceChip(
                      selected: selectedCourts.contains(court.number),
                      label: Text(court.label),
                      onSelected: enabled && available.contains(court.number)
                          ? (_) => onToggleCourt(court.number)
                          : null,
                    ),
                ],
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(height: 1, thickness: 0.5, color: colors.divider),
      ],
    );
  }
}
