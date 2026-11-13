import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/utils/platform.dart';
import 'package:techpie/widgets/ios/ios_native_tab_bar.dart';

class _FirstFrameBinding extends AutomatedTestWidgetsFlutterBinding {
  final warmUpPhases = <SchedulerPhase>[];
  int idleWarmUps = 0;

  @override
  void allowFirstFrame() {
    final needsFrame = !sendFramesToEngine;
    super.allowFirstFrame();
    // The test binding suppresses this automatic scheduling. Restore the
    // production renderer contract so a manual pump cannot hide the bug.
    if (needsFrame) scheduleWarmUpFrame();
  }

  @override
  void scheduleWarmUpFrame() {
    warmUpPhases.add(schedulerPhase);
    // Production SchedulerBinding rejects warm-up requests within a frame;
    // the standard widget-test binding otherwise bypasses that restriction.
    if (schedulerPhase != SchedulerPhase.idle) return;
    idleWarmUps++;
    super.scheduleWarmUpFrame();
  }
}

void main() {
  final binding = _FirstFrameBinding();
  testWidgets(
    'releasing the native tab bar first-frame hold schedules a frame while idle',
    (tester) async {
      debugUsesIosLiquidGlass = true;
      addTearDown(() => debugUsesIosLiquidGlass = false);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: IosNativeTabBar(
              selectedIndex: 0,
              items: const [
                IosNativeTabBarItem(
                  label: 'Home',
                  icon: Icons.home,
                  selectedIcon: Icons.home,
                  sfSymbol: 'house',
                  selectedSfSymbol: 'house.fill',
                ),
              ],
              onSelected: (_) {},
            ),
          ),
        ),
      );
      final before = binding.idleWarmUps;
      // Dispose occurs inside the frame. No pump/gesture follows to rescue a
      // missing frame: allowFirstFrame must schedule the warm-up on its own.
      await tester.pumpWidget(const SizedBox());
      expect(binding.warmUpPhases, everyElement(SchedulerPhase.idle));
      expect(binding.idleWarmUps - before, 1);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
