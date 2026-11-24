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

class GymSearchTab extends StatefulWidget {
  const GymSearchTab({super.key});

  @override
  State<GymSearchTab> createState() => _GymSearchTabState();
}

class _GymSearchTabState extends State<GymSearchTab>
    with AutomaticKeepAliveClientMixin {
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  RangeValues _timeRange = const RangeValues(18, 20);
  final Set<OaSport> _sports = {};
  final Set<String> _venues = {};
  List<OaCourtSearchResult> _results = [];
  bool _loading = false;
  bool _hasSearched = false;
  String? _error;
  int _searchRequest = 0;
  bool _metadataStarted = false;

  @override
  bool get wantKeepAlive => true;

  void _invalidateSearch() {
    _searchRequest++;
    _loading = false;
    _hasSearched = false;
    _results = [];
    _error = null;
  }

  Future<void> _ensureMetadata() async {
    try {
      await ServiceProvider.of(context).oaGymService.ensureReady();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_metadataStarted &&
        ServiceProvider.of(context).oaGymService.venues.isEmpty) {
      _metadataStarted = true;
      unawaited(_ensureMetadata());
    }
  }

  Future<void> _pickStartDate() async {
    final picked = await showAdaptiveDatePicker(
      context: context,
      title: '开始日期',
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null) {
      setState(() {
        _invalidateSearch();
        _startDate = picked;
        if (_endDate.isBefore(picked)) _endDate = picked;
      });
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await showAdaptiveDatePicker(
      context: context,
      title: '结束日期',
      initialDate: _endDate,
      firstDate: _startDate,
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null) {
      setState(() {
        _invalidateSearch();
        _endDate = picked;
      });
    }
  }

  Future<void> _search() async {
    final request = ++_searchRequest;
    final selectedSlots = oaSlotIdsForEndpointRange(
      _timeRange.start.round(),
      _timeRange.end.round(),
    );
    if (selectedSlots.isEmpty) {
      setState(() => _error = '请选择有效时间段，例如 18:00 到 19:00');
      return;
    }

    setState(() {
      _loading = true;
      _hasSearched = true;
      _error = null;
      _results = [];
    });
    try {
      final ranges = <String>[
        for (final slot in selectedSlots) oaTimeSlots[slot - 1].range,
      ];
      final service = ServiceProvider.of(context).oaGymService;
      final data = await service.searchCourts(
        startDate: gymFormatDate(_startDate),
        endDate: gymFormatDate(_endDate),
        venueNames: _venues.isNotEmpty
            ? Set.of(_venues)
            : _sports.map((sport) => oaSportConfigs[sport]!.parentName).toSet(),
        timeRanges: ranges,
        shouldContinue: () => mounted && request == _searchRequest,
        onProgress: (data) {
          if (mounted && request == _searchRequest) {
            setState(() => _results = data);
          }
        },
      );
      if (!mounted || request != _searchRequest) return;
      setState(() => _results = data);
    } catch (e) {
      if (!mounted || request != _searchRequest) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted && request == _searchRequest) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = context.tpColors;
    final service = ServiceProvider.of(context).oaGymService;
    final groupedVenues = gymVenuesBySport(service.venues.keys, _sports);
    final groupedResults = _groupSearchResults(_results);
    final totalResults = groupedResults.fold<int>(
      0,
      (sum, group) =>
          sum +
          group.timeSlots
              .fold<int>(0, (count, slot) => count + slot.items.length),
    );

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
                leadingIcon: TpIcons.search,
                title: '查询条件',
                padding: const EdgeInsets.fromLTRB(
                  TpTokens.cardPaddingHorizontal,
                  TpTokens.space1,
                  TpTokens.cardPaddingHorizontal,
                  TpTokens.space4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _DatePickChip(
                            label: '开始',
                            value: gymFormatDate(_startDate),
                            onTap: _pickStartDate,
                          ),
                        ),
                        const SizedBox(width: TpTokens.space2),
                        Expanded(
                          child: _DatePickChip(
                            label: '结束',
                            value: gymFormatDate(_endDate),
                            onTap: _pickEndDate,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: TpTokens.space3),
                    Text(
                      '项目分类',
                      style: TpTypography.itemTitle(colors)
                          .copyWith(fontSize: 14),
                    ),
                    const SizedBox(height: TpTokens.space2),
                    Wrap(
                      spacing: TpTokens.space2,
                      runSpacing: TpTokens.space2,
                      children: [
                        FilterChip(
                          selected: _sports.isEmpty && _venues.isEmpty,
                          label: const Text('所有场地'),
                          avatar: const Icon(TpIcons.activities, size: 16),
                          showCheckmark: false,
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          onSelected: (_) {
                            setState(() {
                              _invalidateSearch();
                              _sports.clear();
                              _venues.clear();
                            });
                          },
                        ),
                        for (final sport in OaSport.values)
                          FilterChip(
                            selected: _sports.contains(sport),
                            label: Text(sport.label),
                            avatar: Icon(gymSportIcon(sport), size: 16),
                            showCheckmark: false,
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            onSelected: (_) {
                              setState(() {
                                _invalidateSearch();
                                if (_sports.contains(sport)) {
                                  _sports.remove(sport);
                                  _venues.removeWhere(
                                    (venue) => !_sports.any(
                                      (selected) =>
                                          oaVenueMatchesSport(venue, selected),
                                    ),
                                  );
                                } else {
                                  _sports.add(sport);
                                  _venues.addAll(
                                    gymVenuesForSports(
                                      service.venues.keys,
                                      {sport},
                                    ),
                                  );
                                }
                              });
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: TpTokens.space2),
                    if (_sports.isEmpty)
                      Text(
                        '未选择具体场地时默认查询全部场地',
                        style: TpTypography.itemMeta(colors),
                      )
                    else
                      for (final sport
                          in OaSport.values.where(_sports.contains)) ...[
                        const SizedBox(height: TpTokens.space1),
                        Text(
                          sport.label,
                          style: TpTypography.itemTitle(colors)
                              .copyWith(fontSize: 13.5),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final venue
                                in groupedVenues[sport] ?? const <String>[])
                              FilterChip(
                                selected: _venues.contains(venue),
                                label: Text(venue),
                                showCheckmark: false,
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                onSelected: (_) {
                                  setState(() {
                                    _invalidateSearch();
                                    if (_venues.contains(venue)) {
                                      _venues.remove(venue);
                                    } else {
                                      _venues.add(venue);
                                    }
                                  });
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: TpTokens.space2),
                      ],
                    const SizedBox(height: TpTokens.space2),
                    Text(
                      '时间段 ${oaEndpointRangeLabel(_timeRange.start.round(), _timeRange.end.round())}',
                      style: TpTypography.itemTitle(colors)
                          .copyWith(fontSize: 14),
                    ),
                    if (_timeRange.start.round() == _timeRange.end.round())
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
                      onChanged: (value) => setState(() {
                        _invalidateSearch();
                        _timeRange = value;
                      }),
                    ),
                    if (_sports.isNotEmpty && _venues.isNotEmpty) ...[
                      Text(
                        '已选 ${_venues.length} 个场地',
                        style: TpTypography.itemMeta(colors),
                      ),
                      const SizedBox(height: TpTokens.space2),
                    ],
                    const SizedBox(height: TpTokens.space2),
                    AdaptiveButton(
                      onPressed: _loading ? null : _search,
                      icon: TpIcons.search,
                      sfSymbol: 'magnifyingglass',
                      label: _loading ? '查询中...' : '查询预约记录',
                      role: AdaptiveButtonRole.prominent,
                      loading: _loading,
                      height: 46,
                      accessibilityLabel: '查询预约记录',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: TpTokens.sectionGap),
              if (_error != null) ...[
                GymMessageCard(message: _error!, isError: true),
                const SizedBox(height: TpTokens.sectionGap),
              ],
              if (_loading)
                const TpCard(
                  padding: EdgeInsets.all(TpTokens.space5),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (groupedResults.isNotEmpty)
                TpCard(
                  leadingIcon: TpIcons.calendarCheck,
                  title: '查询结果',
                  trailing: TpBadge(
                    label: '$totalResults 条记录',
                    tone: TpBadgeTone.brand,
                  ),
                  child: Theme(
                    data: Theme.of(context)
                        .copyWith(dividerColor: Colors.transparent),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final dateGroup in groupedResults)
                          ExpansionTile(
                            title: Text(
                              '${dateGroup.date}（${dateGroup.timeSlots.length} 个时段）',
                              style: TpTypography.itemTitle(colors)
                                  .copyWith(fontSize: 14.5),
                            ),
                            tilePadding: const EdgeInsets.symmetric(
                              horizontal: TpTokens.cardPaddingHorizontal,
                            ),
                            childrenPadding: const EdgeInsets.only(
                              bottom: TpTokens.space3,
                            ),
                            children: [
                              for (final timeGroup in dateGroup.timeSlots) ...[
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    TpTokens.cardPaddingHorizontal,
                                    TpTokens.space2,
                                    TpTokens.cardPaddingHorizontal,
                                    TpTokens.space1,
                                  ),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      '${timeGroup.timeRange}（${timeGroup.items.length} 条）',
                                      style: TpTypography.cardMeta(colors)
                                          .copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                for (var i = 0; i < timeGroup.items.length; i++)
                                  TpAccentRow(
                                    accentColor: colors.brand,
                                    title: timeGroup.items[i].venue,
                                    subtitle: [
                                      if (timeGroup.items[i].user.isNotEmpty)
                                        timeGroup.items[i].user,
                                      if (timeGroup
                                          .items[i].bookingDate.isNotEmpty)
                                        timeGroup.items[i].bookingDate,
                                      if (timeGroup.items[i].useDate.isNotEmpty)
                                        timeGroup.items[i].useDate,
                                    ].join(' · '),
                                    trailing:
                                        timeGroup.items[i].status.isNotEmpty
                                            ? TpBadge(
                                                label:
                                                    timeGroup.items[i].status,
                                                tone: TpBadgeTone.muted,
                                              )
                                            : null,
                                    showDivider: i < timeGroup.items.length - 1,
                                  ),
                              ],
                            ],
                          ),
                      ],
                    ),
                  ),
                )
              else if (!_loading && _error == null)
                GymMessageCard(
                  message: _hasSearched ? '暂无查询结果' : '选择条件后点击「查询预约记录」',
                  isError: false,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DatePickChip extends StatelessWidget {
  const _DatePickChip({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    return Material(
      color: colors.surfaceSubtle,
      borderRadius: BorderRadius.circular(TpTokens.radiusS),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: colors.textPrimary.withValues(
          alpha: colors.isDark ? 0.06 : 0.04,
        ),
        splashColor: colors.brandSoft,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: TpTokens.space3,
            vertical: TpTokens.space2 + 2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TpTypography.cardMeta(colors)),
              const SizedBox(height: 2),
              Text(
                value,
                style: TpTypography.itemTitle(colors).copyWith(
                  fontSize: 14,
                  fontFeatures: TpTypography.tabularFigures,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

List<_SearchDateGroup> _groupSearchResults(List<OaCourtSearchResult> results) {
  final dateMap = <String, Map<String, List<_SearchResultItem>>>{};
  final seen = <String>{};

  for (final result in results) {
    for (final row in result.rows) {
      final key = '${result.venue}|${result.timeRange}|${row.join('\u001f')}';
      if (!seen.add(key)) continue;
      final useDate = row.length > 9 ? row[9].trim() : '';
      if (useDate.isEmpty) continue;
      final timeRange = result.timeRange.isEmpty ? '全部时间' : result.timeRange;
      final itemsByTime = dateMap.putIfAbsent(
        useDate,
        () => <String, List<_SearchResultItem>>{},
      );
      final items =
          itemsByTime.putIfAbsent(timeRange, () => <_SearchResultItem>[]);
      items.add(
        _SearchResultItem(
          venue: result.venue,
          user: row.length > 7 ? row[7].trim() : '',
          bookingDate: row.length > 2 ? row[2].trim() : '',
          useDate: useDate,
          status: row.length > 6 ? row[6].trim() : '',
        ),
      );
    }
  }

  final groups = <_SearchDateGroup>[];
  final dates = dateMap.keys.toList()..sort();
  for (final date in dates) {
    final timeMap = dateMap[date]!;
    final timeSlots = timeMap.keys.toList()
      ..sort((a, b) {
        if (a == b) return 0;
        if (a == '全部时间') return -1;
        if (b == '全部时间') return 1;
        return a.compareTo(b);
      });
    groups.add(
      _SearchDateGroup(
        date: date,
        timeSlots: [
          for (final timeRange in timeSlots)
            _SearchTimeGroup(
              timeRange: timeRange,
              items: timeMap[timeRange] ?? const [],
            ),
        ],
      ),
    );
  }
  return groups;
}

class _SearchDateGroup {
  final String date;
  final List<_SearchTimeGroup> timeSlots;

  const _SearchDateGroup({
    required this.date,
    required this.timeSlots,
  });
}

class _SearchTimeGroup {
  final String timeRange;
  final List<_SearchResultItem> items;

  const _SearchTimeGroup({
    required this.timeRange,
    required this.items,
  });
}

class _SearchResultItem {
  final String venue;
  final String user;
  final String bookingDate;
  final String useDate;
  final String status;

  const _SearchResultItem({
    required this.venue,
    required this.user,
    required this.bookingDate,
    required this.useDate,
    required this.status,
  });
}
