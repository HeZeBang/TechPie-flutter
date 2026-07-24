import 'dart:async';

import 'package:flutter/material.dart';

import '../models/oa_gym.dart';
import '../services/service_provider.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/ios_liquid/ios_glass_button.dart';
import '../widgets/ios_liquid/ios_native_navigation_bar.dart';
import '../widgets/ios_liquid/ios_platform_view_page_transitions.dart';
import 'login_page.dart';
import 'third_party_accounts_page.dart';

class OaGymPage extends StatefulWidget {
  const OaGymPage({super.key});

  @override
  State<OaGymPage> createState() => _OaGymPageState();
}

class _OaGymPageState extends State<OaGymPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _handlePrerequisite() async {
    final sp = ServiceProvider.of(context);
    if (sp.authService.isLoggedIn) {
      await _openThirdPartyAccounts();
      return;
    }
    await presentLoginPage(context);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openThirdPartyAccounts() async {
    await pushPlatformViewPage<void>(
      context,
      builder: (_) => const ThirdPartyAccountsPage(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sp = ServiceProvider.of(context);
    final auth = sp.authService;
    final tpAuth = sp.thirdPartyAuthService;
    final useIosChrome = isIos();
    final useLegacyIosChrome = usesLegacyIosChrome();
    final topInset = useIosChrome || useLegacyIosChrome
        ? 0.0
        : adaptiveTopBarHeight() + MediaQuery.viewPaddingOf(context).top;

    return Scaffold(
      extendBodyBehindAppBar: !useIosChrome && !useLegacyIosChrome,
      appBar: useIosChrome
          ? IosNativeNavigationBar(
              title: '场馆预约',
              leadingItems: const [
                IosNativeNavigationBarItem(
                  id: 'back',
                  title: 'Home',
                  sfSymbol: 'chevron.left',
                  accessibilityLabel: '返回 Home',
                  placementGroup: 'leading-main',
                ),
              ],
              onItemPressed: (id) {
                switch (id) {
                  case 'back':
                    unawaited(maybePopPlatformViewPage<void>(context));
                }
              },
            )
          : const BlurredAppBar(title: Text('场馆预约')),
      body: ListenableBuilder(
        listenable: Listenable.merge([auth, tpAuth]),
        builder: (context, _) {
          final ready = auth.isLoggedIn && tpAuth.hasEgateBinding;
          return ready
              ? Column(
                  children: [
                    SizedBox(height: topInset),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Card.outlined(
                        clipBehavior: Clip.antiAlias,
                        child: TabBar(
                          controller: _tabController,
                          tabs: const [
                            Tab(
                              text: '预约',
                              icon: Icon(Icons.event_available),
                            ),
                            Tab(text: '查询', icon: Icon(Icons.search)),
                            Tab(text: '个人', icon: Icon(Icons.person_outline)),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: const [
                          _BookingTab(),
                          _SearchTab(),
                          _ProfileTab(),
                        ],
                      ),
                    ),
                  ],
                )
              : ListView(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    topInset + 16,
                    16,
                    AppShellMetrics.bottomContentPaddingOf(context),
                  ),
                  children: [
                    Card.filled(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.login_rounded,
                              size: 40,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              auth.isLoggedIn
                                  ? '需要绑定 eGate 账号'
                                  : '需要先登录 TechPie',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              auth.isLoggedIn
                                  ? '场馆预约复用 eGate 绑定的校园网登录态，请在「第三方账号」中绑定 eGate 后再使用。'
                                  : '场馆预约复用 eGate 绑定的校园网登录态，不需要单独保存 OA 密码。',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 16),
                            IosGlassButton(
                              onPressed: _handlePrerequisite,
                              icon: auth.isLoggedIn
                                  ? Icons.vpn_key_outlined
                                  : Icons.login,
                              sfSymbol: auth.isLoggedIn
                                  ? 'key.horizontal'
                                  : 'person.crop.circle.badge.plus',
                              label: auth.isLoggedIn ? '去绑定 eGate' : '去登录',
                              role: IosNativeButtonRole.prominent,
                              accessibilityLabel:
                                  auth.isLoggedIn ? '前往绑定 eGate' : '登录 TechPie',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
        },
      ),
    );
  }
}

class _BookingTab extends StatefulWidget {
  const _BookingTab();

  @override
  State<_BookingTab> createState() => _BookingTabState();
}

class _BookingTabState extends State<_BookingTab> {
  final Set<OaSport> _sports = {OaSport.badminton};
  final Map<String, Set<int>> _selectedCourts = {};
  DateTime _date = DateTime.now();
  RangeValues _timeRange = const RangeValues(18, 20);
  List<OaAvailability> _availability = [];
  bool _checking = false;
  bool _submitting = false;
  String? _error;
  String? _result;

  String get _dateString => _formatDate(_date);
  int get _startHour => _timeRange.start.round();
  int get _endHour => _timeRange.end.round();
  List<int> get _selectedSlots =>
      oaSlotIdsForEndpointRange(_startHour, _endHour);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_availability.isEmpty && !_checking) {
      unawaited(_refreshAvailability());
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final maxDate = now.hour >= 12
        ? DateTime(now.year, now.month, now.day + 2)
        : DateTime(now.year, now.month, now.day + 1);
    final picked = await showDatePicker(
      context: context,
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

  Future<void> _refreshAvailability() async {
    if (_sports.isEmpty) return;
    if (_selectedSlots.isEmpty) {
      setState(() {
        _error = '请选择有效时间段，例如 18:00 到 19:00';
        _availability = [];
        _selectedCourts.clear();
      });
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
      _result = null;
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
      );
      if (!mounted) return;
      setState(() => _availability = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _checking = false);
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
    var allSuccess = true;
    try {
      for (final entry in _selectedCourts.entries) {
        final parts = entry.key.split('|');
        final sport = OaSport.values.firstWhere((item) => item.id == parts[0]);
        final slot = int.parse(parts[1]);
        for (final court in entry.value) {
          final result = await service.bookCourt(
            sport: sport,
            date: _dateString,
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
      await _refreshAvailability();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
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
        set.add(court);
      }
      if (set.isEmpty) _selectedCourts.remove(key);
      _result = null;
    });
  }

  int get _selectedCount =>
      _selectedCourts.values.fold(0, (sum, set) => sum + set.length);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final grouped = {
      for (final item in _availability) item.key: item,
    };

    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        AppShellMetrics.bottomContentPaddingOf(context),
      ),
      children: [
        Card.outlined(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('预约条件', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final sport in OaSport.values)
                      FilterChip(
                        selected: _sports.contains(sport),
                        label: Text(sport.label),
                        avatar: Icon(_sportIcon(sport), size: 18),
                        onSelected: (_) => _toggleSport(sport),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today_outlined),
                  title: const Text('预约日期'),
                  subtitle: Text(_dateString),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickDate,
                ),
                Text(
                  '时间段 ${oaEndpointRangeLabel(_startHour, _endHour)}',
                  style: theme.textTheme.bodyMedium,
                ),
                if (_selectedSlots.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '左右端点不能重合。请至少选择 1 小时时段。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                      ),
                    ),
                  ),
                RangeSlider(
                  values: _timeRange,
                  min: oaTimeEndpointStart.toDouble(),
                  max: oaTimeEndpointEnd.toDouble(),
                  divisions: oaTimeEndpointEnd - oaTimeEndpointStart,
                  labels: RangeLabels(
                    "${_startHour.toString().padLeft(2, "0")}:00",
                    "${_endHour.toString().padLeft(2, "0")}:00",
                  ),
                  onChanged: (value) {
                    setState(() {
                      _timeRange = value;
                      _selectedCourts.clear();
                    });
                  },
                  onChangeEnd: (_) => unawaited(_refreshAvailability()),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _checking ? null : _refreshAvailability,
                    icon: _checking
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: const Text('刷新可用场地'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_error != null) _MessageCard(message: _error!, isError: true),
        if (_result != null) _MessageCard(message: _result!, isError: false),
        if (_checking)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          for (final sport in _sports) ...[
            Card.outlined(
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(_sportIcon(sport), color: scheme.primary),
                        const SizedBox(width: 8),
                        Text(sport.label, style: theme.textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 12),
                    for (final slot in _selectedSlots)
                      _AvailabilitySlot(
                        sport: sport,
                        slot: slot,
                        availability: grouped['${sport.id}|$slot'],
                        selectedCourts:
                            _selectedCourts['${sport.id}|$slot'] ?? const {},
                        onToggleCourt: (court) =>
                            _toggleCourt('${sport.id}|$slot', court),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        FilledButton.icon(
          onPressed: _submitting || _selectedCount == 0 ? null : _submit,
          icon: _submitting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send),
          label: Text(_selectedCount == 0 ? '提交预约' : '提交预约 ($_selectedCount)'),
        ),
      ],
    );
  }
}

class _AvailabilitySlot extends StatelessWidget {
  final OaSport sport;
  final int slot;
  final OaAvailability? availability;
  final Set<int> selectedCourts;
  final ValueChanged<int> onToggleCourt;

  const _AvailabilitySlot({
    required this.sport,
    required this.slot,
    required this.availability,
    required this.selectedCourts,
    required this.onToggleCourt,
  });

  @override
  Widget build(BuildContext context) {
    final config = oaSportConfigs[sport]!;
    final time = oaTimeSlots[slot - 1];
    final available = availability?.availableCourts ?? const <int>[];
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(time.range, style: theme.textTheme.titleSmall),
              const SizedBox(width: 8),
              Chip(
                label: Text(
                  availability == null
                      ? '未加载'
                      : '${available.length}/${config.courtCount} 可用',
                ),
                visualDensity: VisualDensity.compact,
                color: WidgetStatePropertyAll(
                  availability == null
                      ? theme.colorScheme.surfaceContainerHighest
                      : available.isEmpty
                          ? theme.colorScheme.errorContainer
                          : theme.colorScheme.secondaryContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var court = 1; court <= config.courtCount; court++)
                ChoiceChip(
                  selected: selectedCourts.contains(court),
                  label: Text(_courtLabel(sport, court)),
                  onSelected: available.contains(court)
                      ? (_) => onToggleCourt(court)
                      : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SearchTab extends StatefulWidget {
  const _SearchTab();

  @override
  State<_SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<_SearchTab> {
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  RangeValues _timeRange = const RangeValues(18, 20);
  final Set<OaSport> _sports = {};
  final Set<String> _venues = {};
  List<OaCourtSearchResult> _results = [];
  bool _loading = false;
  String? _error;

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
    if (ServiceProvider.of(context).oaGymService.venues.isEmpty) {
      unawaited(_ensureMetadata());
    }
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: _startDate,
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  Future<void> _search() async {
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
      _error = null;
      _results = [];
    });
    try {
      final ranges = <String>[
        for (final slot in selectedSlots) oaTimeSlots[slot - 1].range,
      ];
      final data = await ServiceProvider.of(context).oaGymService.searchCourts(
            startDate: _formatDate(_startDate),
            endDate: _formatDate(_endDate),
            venueNames: _venues.isNotEmpty ? _venues : <String>{},
            timeRanges: ranges,
          );
      if (!mounted) return;
      setState(() => _results = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = ServiceProvider.of(context).oaGymService;
    final groupedVenues = _venuesBySport(service.venues.keys, _sports);
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
        16,
        12,
        16,
        AppShellMetrics.bottomContentPaddingOf(context),
      ),
      children: [
        Card.outlined(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('查询条件', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('开始'),
                        subtitle: Text(_formatDate(_startDate)),
                        onTap: _pickStartDate,
                      ),
                    ),
                    Expanded(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('结束'),
                        subtitle: Text(_formatDate(_endDate)),
                        onTap: _pickEndDate,
                      ),
                    ),
                  ],
                ),
                Text('项目分类', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilterChip(
                      selected: _sports.isEmpty && _venues.isEmpty,
                      label: const Text('所有场地'),
                      avatar: const Icon(Icons.apps_rounded, size: 18),
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onSelected: (_) {
                        setState(() {
                          _sports.clear();
                          _venues.clear();
                        });
                      },
                    ),
                    for (final sport in OaSport.values)
                      FilterChip(
                        selected: _sports.contains(sport),
                        label: Text(sport.label),
                        avatar: Icon(_sportIcon(sport), size: 18),
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onSelected: (_) {
                          setState(() {
                            if (_sports.contains(sport)) {
                              _sports.remove(sport);
                              _venues.removeAll(
                                _venuesForSports(service.venues.keys, {sport}),
                              );
                            } else {
                              _sports.add(sport);
                              _venues.addAll(
                                _venuesForSports(service.venues.keys, {sport}),
                              );
                            }
                          });
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_sports.isEmpty)
                  Text(
                    '未选择具体场地时默认查询全部场地',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                else
                  for (final sport
                      in OaSport.values.where(_sports.contains)) ...[
                    Text(
                      sport.label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
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
                    const SizedBox(height: 10),
                  ],
                Text(
                  '时间段 ${oaEndpointRangeLabel(_timeRange.start.round(), _timeRange.end.round())}',
                ),
                if (_timeRange.start.round() == _timeRange.end.round())
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '左右端点不能重合。请至少选择 1 小时时段。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                    ),
                  ),
                RangeSlider(
                  values: _timeRange,
                  min: oaTimeEndpointStart.toDouble(),
                  max: oaTimeEndpointEnd.toDouble(),
                  divisions: oaTimeEndpointEnd - oaTimeEndpointStart,
                  onChanged: (value) => setState(() => _timeRange = value),
                ),
                if (_sports.isNotEmpty && _venues.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '已选 ${_venues.length} 个场地',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _loading ? null : _search,
                  icon: _loading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                  label: Text(_loading ? '查询中...' : '查询预约记录'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_error != null) _MessageCard(message: _error!, isError: true),
        if (_loading)
          const Card.outlined(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),
          )
        else if (groupedResults.isNotEmpty)
          Card.outlined(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '查询结果 · $totalResults 条记录',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  for (final dateGroup in groupedResults) ...[
                    ExpansionTile(
                      title: Text(
                        '${dateGroup.date}（${dateGroup.timeSlots.length} 个时段）',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(bottom: 12),
                      children: [
                        for (final timeGroup in dateGroup.timeSlots) ...[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${timeGroup.timeRange}（${timeGroup.items.length} 条）',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 8),
                                for (var i = 0; i < timeGroup.items.length; i++)
                                  Padding(
                                    padding: EdgeInsets.only(
                                      bottom: i == timeGroup.items.length - 1
                                          ? 0
                                          : 8,
                                    ),
                                    child: ListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 4,
                                      ),
                                      tileColor: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest
                                          .withValues(alpha: 0.25),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      leading: const Icon(
                                        Icons.event_note_outlined,
                                      ),
                                      title: Text(timeGroup.items[i].venue),
                                      subtitle: Text(
                                        [
                                          if (timeGroup
                                              .items[i].user.isNotEmpty)
                                            timeGroup.items[i].user,
                                          if (timeGroup
                                              .items[i].bookingDate.isNotEmpty)
                                            timeGroup.items[i].bookingDate,
                                          if (timeGroup
                                              .items[i].useDate.isNotEmpty)
                                            timeGroup.items[i].useDate,
                                          if (timeGroup
                                              .items[i].status.isNotEmpty)
                                            timeGroup.items[i].status,
                                        ].join(' · '),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          )
        else if (!_loading && _error == null)
          const _MessageCard(message: '暂无查询结果', isError: false),
      ],
    );
  }
}

class _ProfileTab extends StatefulWidget {
  const _ProfileTab();

  @override
  State<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<_ProfileTab> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final profile = ServiceProvider.of(context).oaGymService.bookingProfile();
    _name.text = profile.name;
    _phone.text = profile.phone;
    _email.text = profile.email;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ServiceProvider.of(context).oaGymService.saveBookingProfile(
          OaBookingProfile(
            name: _name.text.trim(),
            phone: _phone.text.trim(),
            email: _email.text.trim(),
          ),
        );
    if (!mounted) return;
    showAdaptiveFeedback(
      context: context,
      message: '预约信息已保存',
      style: AdaptiveFeedbackStyle.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final sp = ServiceProvider.of(context);
    final tpAuth = sp.thirdPartyAuthService;
    final egate = tpAuth.egateBinding;

    // Identity card prefers eGate binding (real name + student id) over the
    // primary SSO account, whose userName/userId are Casdoor UUIDs with no
    // meaning in the OA booking context.
    final displayName = egate?.name?.isNotEmpty == true
        ? egate!.name!
        : (egate?.account.isNotEmpty == true ? egate!.account : 'TechPie 用户');
    final studentId = egate?.sid ?? '';
    final avatarText = displayName.characters.firstOrNull ?? 'U';

    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        AppShellMetrics.bottomContentPaddingOf(context),
      ),
      children: [
        Card.filled(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(child: Text(avatarText)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (studentId.isNotEmpty) Text(studentId),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card.outlined(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('预约提交信息', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  '提交 OA 场馆预约时会使用以下信息。姓名和手机号必填，邮箱可选。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: '姓名',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phone,
                  decoration: const InputDecoration(
                    labelText: '手机号',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _email,
                  decoration: const InputDecoration(
                    labelText: '邮箱',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('保存'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MessageCard extends StatelessWidget {
  final String message;
  final bool isError;

  const _MessageCard({
    required this.message,
    required this.isError,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card.filled(
      color: isError ? scheme.errorContainer : scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          message,
          style: TextStyle(
            color:
                isError ? scheme.onErrorContainer : scheme.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}

Map<OaSport, List<String>> _venuesBySport(
  Iterable<String> venues,
  Set<OaSport> sports,
) {
  final result = <OaSport, List<String>>{
    for (final sport in sports) sport: <String>[],
  };
  for (final item in venues) {
    if (const {
      '所有场地',
      '室内羽毛球场',
      '室内乒乓球场',
      '网球场',
      '匹克球场',
    }.contains(item)) {
      continue;
    }
    if (sports.contains(OaSport.badminton) && item.contains('羽毛球')) {
      result[OaSport.badminton]!.add(item);
      continue;
    }
    if (sports.contains(OaSport.pingpong) && item.contains('乒乓球')) {
      result[OaSport.pingpong]!.add(item);
      continue;
    }
    if (sports.contains(OaSport.tennis) && item.contains('网球')) {
      result[OaSport.tennis]!.add(item);
      continue;
    }
    if (sports.contains(OaSport.pickleball) && item.contains('匹克球')) {
      result[OaSport.pickleball]!.add(item);
    }
  }
  return result;
}

List<String> _venuesForSports(Iterable<String> venues, Set<OaSport> sports) =>
    venues.where((item) {
      if (const {
        '所有场地',
        '室内羽毛球场',
        '室内乒乓球场',
        '网球场',
        '匹克球场',
      }.contains(item)) {
        return false;
      }
      if (sports.contains(OaSport.badminton) && item.contains('羽毛球')) {
        return true;
      }
      if (sports.contains(OaSport.pingpong) && item.contains('乒乓球')) {
        return true;
      }
      if (sports.contains(OaSport.tennis) && item.contains('网球')) {
        return true;
      }
      if (sports.contains(OaSport.pickleball) && item.contains('匹克球')) {
        return true;
      }
      return false;
    }).toList();

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

String _formatDate(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String _courtLabel(OaSport sport, int court) {
  if (sport == OaSport.pickleball) return '匹克球1号场地';
  final config = oaSportConfigs[sport]!;
  return '${config.courtNamePrefix}$court${config.courtNameSuffix}';
}

IconData _sportIcon(OaSport sport) => switch (sport) {
      OaSport.badminton => Icons.sports_tennis,
      OaSport.pingpong => Icons.sports_handball,
      OaSport.tennis => Icons.sports_tennis,
      OaSport.pickleball => Icons.sports_baseball,
    };

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
