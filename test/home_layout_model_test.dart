import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/home_layout.dart';
import 'package:techpie/services/storage_service.dart';

void main() {
  group('HomeMobileLayout', () {
    test('defaults match original mobile order and compact campus card', () {
      final layout = HomeMobileLayout.defaults();
      expect(layout.order, [
        HomeWidgetId.campusCard,
        HomeWidgetId.todayCourses,
        HomeWidgetId.deadlines,
        HomeWidgetId.quickActions,
      ]);
      expect(layout.campusCardStyle, HomeCampusCardStyle.compact);
      expect(layout.availableToAdd, isEmpty);
      expect(layout.isEmpty, isFalse);
    });

    test('reorder supports down, end, and up moves with ReorderableList semantics',
        () {
      final initial = HomeMobileLayout.defaults();

      final down = initial.reorder(0, 2);
      expect(down.order, [
        HomeWidgetId.todayCourses,
        HomeWidgetId.campusCard,
        HomeWidgetId.deadlines,
        HomeWidgetId.quickActions,
      ]);

      final toEnd = initial.reorder(0, 4);
      expect(toEnd.order, [
        HomeWidgetId.todayCourses,
        HomeWidgetId.deadlines,
        HomeWidgetId.quickActions,
        HomeWidgetId.campusCard,
      ]);

      final up = toEnd.reorder(3, 0);
      expect(up.order, initial.order);

      // Invalid indices are safe no-ops.
      expect(initial.reorder(-1, 2), initial);
      expect(initial.reorder(9, 0), initial);
    });

    test('remove, add, and moveBy handle empty and duplicate guards', () {
      var layout = HomeMobileLayout.defaults();
      layout = layout.removeWidget(HomeWidgetId.deadlines);
      expect(layout.contains(HomeWidgetId.deadlines), isFalse);
      expect(layout.availableToAdd, [HomeWidgetId.deadlines]);

      // Adding again does not duplicate.
      final added = layout.addWidget(HomeWidgetId.deadlines, atIndex: 1);
      expect(added.order[1], HomeWidgetId.deadlines);
      expect(added.addWidget(HomeWidgetId.deadlines), added);

      // Move all out -> empty preserved through JSON roundtrip.
      for (final id in HomeWidgetId.values) {
        layout = layout.removeWidget(id);
      }
      expect(layout.isEmpty, isTrue);
      final roundtrip = HomeMobileLayout.decode(layout.encode());
      expect(roundtrip.isEmpty, isTrue);
      expect(roundtrip, layout);
    });

    test('decode handles malformed, unknown keys, and duplicates gracefully', () {
      expect(HomeMobileLayout.decode(null), HomeMobileLayout.defaults());
      expect(HomeMobileLayout.decode('not json'), HomeMobileLayout.defaults());
      expect(HomeMobileLayout.decode('{"v":1}'), HomeMobileLayout.defaults());

      final partial = HomeMobileLayout.decode(
        '{"v":1,"order":["deadlines","unknown_id","deadlines","campus_card"],"campusCardStyle":"full"}',
      );
      expect(partial.order, [HomeWidgetId.deadlines, HomeWidgetId.campusCard]);
      expect(partial.campusCardStyle, HomeCampusCardStyle.full);
    });
  });

  group('HomeDesktopLayout', () {
    test('defaults match Bento columns and full campus card style', () {
      final layout = HomeDesktopLayout.defaults();
      expect(layout.primary, [
        HomeWidgetId.todayCourses,
        HomeWidgetId.deadlines,
      ]);
      expect(layout.secondary, [
        HomeWidgetId.campusCard,
        HomeWidgetId.quickActions,
      ]);
      expect(layout.campusCardStyle, HomeCampusCardStyle.full);
    });

    test('moveToSlot handles intra-column and cross-column transfers cleanly', () {
      final initial = HomeDesktopLayout.defaults();

      // Move first primary item after second item (slot 2 -> final index 1).
      final swappedPrimary = initial.moveToSlot(
        HomeWidgetId.todayCourses,
        HomeBentoColumn.primary,
        2,
      );
      expect(swappedPrimary.primary, [
        HomeWidgetId.deadlines,
        HomeWidgetId.todayCourses,
      ]);

      // Move secondary item to top of primary column.
      final cross = swappedPrimary.moveToSlot(
        HomeWidgetId.campusCard,
        HomeBentoColumn.primary,
        0,
      );
      expect(cross.primary, [
        HomeWidgetId.campusCard,
        HomeWidgetId.deadlines,
        HomeWidgetId.todayCourses,
      ]);
      expect(cross.secondary, [HomeWidgetId.quickActions]);
      expect(cross.columnOf(HomeWidgetId.campusCard), HomeBentoColumn.primary);

      // Emptying secondary column works cleanly.
      final emptiedSecondary = cross.swapColumn(HomeWidgetId.quickActions);
      expect(emptiedSecondary.secondary, isEmpty);
      expect(emptiedSecondary.primary.length, 4);
    });

    test('moveBy, removeWidget, addWidget, and decode deduplicate across columns',
        () {
      final layout = HomeDesktopLayout(
        primary: const [HomeWidgetId.campusCard, HomeWidgetId.todayCourses],
        secondary: const [HomeWidgetId.campusCard, HomeWidgetId.deadlines],
      );
      // campusCard was deduplicated out of secondary, keeping primary priority.
      expect(layout.primary, [HomeWidgetId.campusCard, HomeWidgetId.todayCourses]);
      expect(layout.secondary, [HomeWidgetId.deadlines]);

      final shifted = layout.moveBy(HomeWidgetId.campusCard, 1);
      expect(shifted.primary, [HomeWidgetId.todayCourses, HomeWidgetId.campusCard]);

      final decoded = HomeDesktopLayout.decode(
        '{"v":1,"primary":["quick_actions","bogus"],"secondary":["quick_actions"],"campusCardStyle":"compact"}',
      );
      expect(decoded.primary, [HomeWidgetId.quickActions]);
      expect(decoded.secondary, isEmpty);
      expect(decoded.campusCardStyle, HomeCampusCardStyle.compact);
    });
  });

  group('StorageService Home layout persistence', () {
    test('persists mobile and desktop layouts independently', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService(await SharedPreferences.getInstance());

      expect(storage.homeMobileLayout, HomeMobileLayout.defaults());
      expect(storage.homeDesktopLayout, HomeDesktopLayout.defaults());

      final customMobile = HomeMobileLayout(
        order: const [HomeWidgetId.deadlines, HomeWidgetId.campusCard],
        campusCardStyle: HomeCampusCardStyle.full,
      );
      await storage.setHomeMobileLayout(customMobile);

      expect(storage.homeMobileLayout, customMobile);
      // Desktop remains untouched.
      expect(storage.homeDesktopLayout, HomeDesktopLayout.defaults());

      final customDesktop = HomeDesktopLayout(
        primary: const [HomeWidgetId.campusCard],
        secondary: const [HomeWidgetId.todayCourses, HomeWidgetId.deadlines],
        campusCardStyle: HomeCampusCardStyle.compact,
      );
      await storage.setHomeDesktopLayout(customDesktop);

      expect(storage.homeDesktopLayout, customDesktop);
      expect(storage.homeMobileLayout, customMobile);
    });
  });
}
