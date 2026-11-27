import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Supported customizable widgets on the Home dashboard.
enum HomeWidgetId {
  campusCard('campus_card'),
  todayCourses('today_courses'),
  deadlines('deadlines'),
  quickActions('quick_actions');

  const HomeWidgetId(this.key);

  /// Stable serialized identifier stored in [SharedPreferences].
  final String key;

  static HomeWidgetId? fromKey(Object? raw) {
    if (raw is! String) return null;
    for (final value in values) {
      if (value.key == raw) return value;
    }
    return null;
  }
}

/// Visual density style for the Home campus card widget.
enum HomeCampusCardStyle {
  full('full'),
  compact('compact');

  const HomeCampusCardStyle(this.key);

  final String key;

  static HomeCampusCardStyle fromKey(
    Object? raw, {
    required HomeCampusCardStyle fallback,
  }) {
    if (raw is! String) return fallback;
    for (final value in values) {
      if (value.key == raw) return value;
    }
    return fallback;
  }
}

/// Column buckets used by the desktop 2-column Bento layout.
enum HomeBentoColumn { primary, secondary }

/// Static display metadata for a customizable Home widget.
@immutable
class HomeWidgetMeta {
  const HomeWidgetMeta({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.defaultDesktopColumn,
  });

  final HomeWidgetId id;
  final String title;
  final String subtitle;
  final HomeBentoColumn defaultDesktopColumn;
}

const Map<HomeWidgetId, HomeWidgetMeta> homeWidgetCatalog = {
  HomeWidgetId.campusCard: HomeWidgetMeta(
    id: HomeWidgetId.campusCard,
    title: '校园卡',
    subtitle: '余额展示与付款码快捷入口',
    defaultDesktopColumn: HomeBentoColumn.secondary,
  ),
  HomeWidgetId.todayCourses: HomeWidgetMeta(
    id: HomeWidgetId.todayCourses,
    title: '今日课程',
    subtitle: '当天课表进度、教室与教师信息',
    defaultDesktopColumn: HomeBentoColumn.primary,
  ),
  HomeWidgetId.deadlines: HomeWidgetMeta(
    id: HomeWidgetId.deadlines,
    title: '待办截止',
    subtitle: '近期作业、自定义事项与考试倒计时',
    defaultDesktopColumn: HomeBentoColumn.primary,
  ),
  HomeWidgetId.quickActions: HomeWidgetMeta(
    id: HomeWidgetId.quickActions,
    title: '快捷入口',
    subtitle: '常用校园服务与工具固定入口',
    defaultDesktopColumn: HomeBentoColumn.secondary,
  ),
};

HomeWidgetMeta homeWidgetMetaFor(HomeWidgetId id) => homeWidgetCatalog[id]!;

List<HomeWidgetId> _parseUniqueWidgetList(
  Object? raw, {
  Set<HomeWidgetId>? seen,
}) {
  if (raw is! List) return const [];
  final tracker = seen ?? <HomeWidgetId>{};
  final result = <HomeWidgetId>[];
  for (final item in raw) {
    final parsed = HomeWidgetId.fromKey(item);
    if (parsed != null && tracker.add(parsed)) {
      result.add(parsed);
    }
  }
  return result;
}

/// Single-column widget arrangement and preferences for narrow/mobile viewports.
@immutable
class HomeMobileLayout {
  HomeMobileLayout({
    required List<HomeWidgetId> order,
    this.campusCardStyle = defaultCampusCardStyle,
  }) : order = List<HomeWidgetId>.unmodifiable(_dedupe(order));

  factory HomeMobileLayout.defaults() => HomeMobileLayout(
        order: defaultOrder,
        campusCardStyle: defaultCampusCardStyle,
      );

  static const List<HomeWidgetId> defaultOrder = [
    HomeWidgetId.campusCard,
    HomeWidgetId.todayCourses,
    HomeWidgetId.deadlines,
    HomeWidgetId.quickActions,
  ];

  static const HomeCampusCardStyle defaultCampusCardStyle =
      HomeCampusCardStyle.compact;

  final List<HomeWidgetId> order;
  final HomeCampusCardStyle campusCardStyle;

  bool get isEmpty => order.isEmpty;

  bool contains(HomeWidgetId id) => order.contains(id);

  List<HomeWidgetId> get availableToAdd => [
        for (final id in HomeWidgetId.values)
          if (!order.contains(id)) id,
      ];

  HomeMobileLayout copyWith({
    List<HomeWidgetId>? order,
    HomeCampusCardStyle? campusCardStyle,
  }) =>
      HomeMobileLayout(
        order: order ?? this.order,
        campusCardStyle: campusCardStyle ?? this.campusCardStyle,
      );

  /// Reorders using Flutter's [ReorderableListView] index convention
  /// (`oldIndex < newIndex` adjusts `newIndex` down by 1).
  HomeMobileLayout reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= order.length) return this;
    var target = newIndex.clamp(0, order.length);
    if (oldIndex < target) {
      target -= 1;
    }
    if (target == oldIndex) return this;
    final next = order.toList();
    final item = next.removeAt(oldIndex);
    next.insert(target, item);
    return copyWith(order: next);
  }

  /// Shifts [id] up (`delta < 0`) or down (`delta > 0`) within [order].
  HomeMobileLayout moveBy(HomeWidgetId id, int delta) {
    final oldIndex = order.indexOf(id);
    if (oldIndex < 0 || delta == 0) return this;
    final target = (oldIndex + delta).clamp(0, order.length - 1);
    if (target == oldIndex) return this;
    final next = order.toList();
    final item = next.removeAt(oldIndex);
    next.insert(target, item);
    return copyWith(order: next);
  }

  HomeMobileLayout removeWidget(HomeWidgetId id) {
    if (!order.contains(id)) return this;
    return copyWith(
      order: [
        for (final item in order)
          if (item != id) item,
      ],
    );
  }

  HomeMobileLayout addWidget(HomeWidgetId id, {int? atIndex}) {
    if (order.contains(id)) return this;
    final next = order.toList();
    final insertAt = (atIndex ?? next.length).clamp(0, next.length);
    next.insert(insertAt, id);
    return copyWith(order: next);
  }

  Map<String, dynamic> toJson() => {
        'v': 1,
        'order': [for (final id in order) id.key],
        'campusCardStyle': campusCardStyle.key,
      };

  String encode() => jsonEncode(toJson());

  static HomeMobileLayout decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return HomeMobileLayout.defaults();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return HomeMobileLayout.defaults();
      }
      if (!decoded.containsKey('order') || decoded['order'] is! List) {
        return HomeMobileLayout.defaults();
      }
      final order = _parseUniqueWidgetList(decoded['order']);
      final style = HomeCampusCardStyle.fromKey(
        decoded['campusCardStyle'],
        fallback: defaultCampusCardStyle,
      );
      return HomeMobileLayout(order: order, campusCardStyle: style);
    } catch (_) {
      return HomeMobileLayout.defaults();
    }
  }

  static List<HomeWidgetId> _dedupe(List<HomeWidgetId> items) {
    final seen = <HomeWidgetId>{};
    return [
      for (final item in items)
        if (seen.add(item)) item,
    ];
  }

  @override
  bool operator ==(Object other) =>
      other is HomeMobileLayout &&
      other.campusCardStyle == campusCardStyle &&
      listEquals(other.order, order);

  @override
  int get hashCode => Object.hash(campusCardStyle, Object.hashAll(order));
}

/// Dual-column Bento widget arrangement and preferences for wide/desktop views.
@immutable
class HomeDesktopLayout {
  const HomeDesktopLayout._({
    required this.primary,
    required this.secondary,
    required this.campusCardStyle,
  });

  factory HomeDesktopLayout({
    required List<HomeWidgetId> primary,
    required List<HomeWidgetId> secondary,
    HomeCampusCardStyle campusCardStyle = defaultCampusCardStyle,
  }) {
    final seen = <HomeWidgetId>{};
    final cleanPrimary = <HomeWidgetId>[
      for (final id in primary)
        if (seen.add(id)) id,
    ];
    final cleanSecondary = <HomeWidgetId>[
      for (final id in secondary)
        if (seen.add(id)) id,
    ];
    return HomeDesktopLayout._(
      primary: List<HomeWidgetId>.unmodifiable(cleanPrimary),
      secondary: List<HomeWidgetId>.unmodifiable(cleanSecondary),
      campusCardStyle: campusCardStyle,
    );
  }

  factory HomeDesktopLayout.defaults() => HomeDesktopLayout(
        primary: defaultPrimary,
        secondary: defaultSecondary,
        campusCardStyle: defaultCampusCardStyle,
      );

  static const List<HomeWidgetId> defaultPrimary = [
    HomeWidgetId.todayCourses,
    HomeWidgetId.deadlines,
  ];

  static const List<HomeWidgetId> defaultSecondary = [
    HomeWidgetId.campusCard,
    HomeWidgetId.quickActions,
  ];

  static const HomeCampusCardStyle defaultCampusCardStyle =
      HomeCampusCardStyle.full;

  final List<HomeWidgetId> primary;
  final List<HomeWidgetId> secondary;
  final HomeCampusCardStyle campusCardStyle;

  bool get isEmpty => primary.isEmpty && secondary.isEmpty;

  bool contains(HomeWidgetId id) =>
      primary.contains(id) || secondary.contains(id);

  List<HomeWidgetId> get availableToAdd => [
        for (final id in HomeWidgetId.values)
          if (!contains(id)) id,
      ];

  List<HomeWidgetId> columnItems(HomeBentoColumn column) => switch (column) {
        HomeBentoColumn.primary => primary,
        HomeBentoColumn.secondary => secondary,
      };

  HomeBentoColumn? columnOf(HomeWidgetId id) {
    if (primary.contains(id)) return HomeBentoColumn.primary;
    if (secondary.contains(id)) return HomeBentoColumn.secondary;
    return null;
  }

  int indexOf(HomeWidgetId id) {
    final pIdx = primary.indexOf(id);
    if (pIdx >= 0) return pIdx;
    return secondary.indexOf(id);
  }

  HomeDesktopLayout copyWith({
    List<HomeWidgetId>? primary,
    List<HomeWidgetId>? secondary,
    HomeCampusCardStyle? campusCardStyle,
  }) =>
      HomeDesktopLayout(
        primary: primary ?? this.primary,
        secondary: secondary ?? this.secondary,
        campusCardStyle: campusCardStyle ?? this.campusCardStyle,
      );

  /// Moves [id] to drop slot [slotIndex] in [targetColumn].
  ///
  /// [slotIndex] follows pre-removal insertion slot semantics (`0..len`):
  /// dropping below an item's own slot in the same column adjusts by `-1`.
  HomeDesktopLayout moveToSlot(
    HomeWidgetId id,
    HomeBentoColumn targetColumn,
    int slotIndex,
  ) {
    final sourceColumn = columnOf(id);
    if (sourceColumn == null) {
      return addWidget(id, column: targetColumn, atIndex: slotIndex);
    }

    final nextPrimary = primary.toList();
    final nextSecondary = secondary.toList();
    final sourceList =
        sourceColumn == HomeBentoColumn.primary ? nextPrimary : nextSecondary;
    final targetList =
        targetColumn == HomeBentoColumn.primary ? nextPrimary : nextSecondary;

    final oldIndex = sourceList.indexOf(id);
    var insertAt = slotIndex.clamp(0, targetList.length);
    if (sourceColumn == targetColumn && oldIndex < insertAt) {
      insertAt -= 1;
    }
    if (sourceColumn == targetColumn && oldIndex == insertAt) {
      return this;
    }
    sourceList.removeAt(oldIndex);
    targetList.insert(insertAt.clamp(0, targetList.length), id);
    return copyWith(primary: nextPrimary, secondary: nextSecondary);
  }

  /// Shifts [id] up (`delta < 0`) or down (`delta > 0`) within its column.
  HomeDesktopLayout moveBy(HomeWidgetId id, int delta) {
    final column = columnOf(id);
    if (column == null || delta == 0) return this;
    final list = columnItems(column).toList();
    final oldIndex = list.indexOf(id);
    final target = (oldIndex + delta).clamp(0, list.length - 1);
    if (target == oldIndex) return this;
    list.removeAt(oldIndex);
    list.insert(target, id);
    return column == HomeBentoColumn.primary
        ? copyWith(primary: list)
        : copyWith(secondary: list);
  }

  /// Moves [id] to the opposite Bento column, clamped to a matching index.
  HomeDesktopLayout swapColumn(HomeWidgetId id) {
    final sourceColumn = columnOf(id);
    if (sourceColumn == null) return this;
    final targetColumn = sourceColumn == HomeBentoColumn.primary
        ? HomeBentoColumn.secondary
        : HomeBentoColumn.primary;
    final currentIndex = indexOf(id);
    final targetLen = columnItems(targetColumn).length;
    return moveToSlot(id, targetColumn, currentIndex.clamp(0, targetLen));
  }

  HomeDesktopLayout removeWidget(HomeWidgetId id) {
    if (!contains(id)) return this;
    return copyWith(
      primary: [
        for (final item in primary)
          if (item != id) item,
      ],
      secondary: [
        for (final item in secondary)
          if (item != id) item,
      ],
    );
  }

  HomeDesktopLayout addWidget(
    HomeWidgetId id, {
    HomeBentoColumn? column,
    int? atIndex,
  }) {
    if (contains(id)) return this;
    final targetCol = column ?? homeWidgetMetaFor(id).defaultDesktopColumn;
    final nextPrimary = primary.toList();
    final nextSecondary = secondary.toList();
    final targetList =
        targetCol == HomeBentoColumn.primary ? nextPrimary : nextSecondary;
    final insertAt = (atIndex ?? targetList.length).clamp(0, targetList.length);
    targetList.insert(insertAt, id);
    return copyWith(primary: nextPrimary, secondary: nextSecondary);
  }

  Map<String, dynamic> toJson() => {
        'v': 1,
        'primary': [for (final id in primary) id.key],
        'secondary': [for (final id in secondary) id.key],
        'campusCardStyle': campusCardStyle.key,
      };

  String encode() => jsonEncode(toJson());

  static HomeDesktopLayout decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return HomeDesktopLayout.defaults();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return HomeDesktopLayout.defaults();
      }
      if (!decoded.containsKey('primary') ||
          !decoded.containsKey('secondary') ||
          decoded['primary'] is! List ||
          decoded['secondary'] is! List) {
        return HomeDesktopLayout.defaults();
      }
      final seen = <HomeWidgetId>{};
      final primary = _parseUniqueWidgetList(decoded['primary'], seen: seen);
      final secondary = _parseUniqueWidgetList(decoded['secondary'], seen: seen);
      final style = HomeCampusCardStyle.fromKey(
        decoded['campusCardStyle'],
        fallback: defaultCampusCardStyle,
      );
      return HomeDesktopLayout(
        primary: primary,
        secondary: secondary,
        campusCardStyle: style,
      );
    } catch (_) {
      return HomeDesktopLayout.defaults();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is HomeDesktopLayout &&
      other.campusCardStyle == campusCardStyle &&
      listEquals(other.primary, primary) &&
      listEquals(other.secondary, secondary);

  @override
  int get hashCode => Object.hash(
        campusCardStyle,
        Object.hashAll(primary),
        Object.hashAll(secondary),
      );
}
