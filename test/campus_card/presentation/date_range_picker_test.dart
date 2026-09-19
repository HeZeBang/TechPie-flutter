import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/app/app_providers.dart';
import 'package:techpie/features/campus_card/app/demo_runtime_factory.dart';
import 'package:techpie/features/campus_card/presentation/screens/card_manage_screen.dart';
import 'package:techpie/features/campus_card/presentation/theme/theme.dart';

void main() {
  testWidgets(
    'Android date range picker inherits the host theme and can clear a range',
    (tester) async {
      const hostPrimary = Color(0xFF6750A4);
      await tester.binding.setSurfaceSize(const Size(430, 932));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final runtime = await buildDemoRuntime();
      addTearDown(runtime.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appRuntimeProvider.overrideWithValue(runtime)],
          child: MaterialApp(
            theme: GeekPayTheme.inherit(
              ThemeData(
                useMaterial3: true,
                colorScheme: const ColorScheme.light(primary: hostPrimary),
              ),
            ).copyWith(
              platform: TargetPlatform.android,
            ),
            home: const CardManageScreen(),
          ),
        ),
      );
      for (var index = 0; index < 24; index++) {
        await tester.pump(const Duration(milliseconds: 30));
      }

      await tester.tap(find.text('使用明细'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('日期范围'));
      await tester.pumpAndSettle();

      final pickerContext = tester.element(
        find.byType(DateRangePickerDialog),
      );
      expect(Theme.of(pickerContext).colorScheme.primary, hostPrimary);
      expect(
        Theme.of(pickerContext)
            .appBarTheme
            .systemOverlayStyle
            ?.statusBarIconBrightness,
        Brightness.dark,
      );
      expect(find.byKey(const Key('android-date-range-clear')), findsOneWidget);
      expect(find.text('不指定日期'), findsNWidgets(2));

      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(find.text('不指定日期'), findsNothing);

      await tester.tap(find.text('日期范围'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('android-date-range-clear')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('android-date-range-clear')), findsNothing);
      expect(find.text('不指定日期'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
