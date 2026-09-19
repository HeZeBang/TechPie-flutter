import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/app/app_providers.dart';
import 'package:techpie/features/campus_card/domain/ports/platform_ports.dart';
import 'package:techpie/features/campus_card/presentation/screens/widget_setup_screen.dart';

void main() {
  testWidgets('Android pinning waits for an explicit user tap', (tester) async {
    final port = _WidgetPort(HomeWidgetAvailability.nativePin);
    await tester.pumpWidget(_app(port, TargetPlatform.android));
    await tester.pumpAndSettle();
    expect(port.requests, 0);
    expect(find.byType(PayWidgetPreview), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('request-pin-widget')));
    await tester.tap(find.byKey(const Key('request-pin-widget')));
    await tester.pumpAndSettle();
    expect(port.requests, 1);
    expect(find.text('请在系统弹窗中确认添加。'), findsOneWidget);
  });

  testWidgets('iOS shows a complete manual guide without a pin button',
      (tester) async {
    final port = _WidgetPort(HomeWidgetAvailability.manual);
    await tester.pumpWidget(_app(port, TargetPlatform.iOS));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('request-pin-widget')), findsNothing);
    expect(find.textContaining('搜索 TechPie'), findsOneWidget);
    expect(find.textContaining('点“完成”'), findsOneWidget);
    expect(port.requests, 0);
  });

  testWidgets('a rejected launcher request falls back to manual instructions',
      (tester) async {
    final port = _WidgetPort(HomeWidgetAvailability.nativePin, accept: false);
    await tester.pumpWidget(_app(port, TargetPlatform.android));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('request-pin-widget')));
    await tester.tap(find.byKey(const Key('request-pin-widget')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('request-pin-widget')), findsNothing);
    expect(find.textContaining('未接受添加请求'), findsOneWidget);
    expect(find.textContaining('找到 TechPie'), findsOneWidget);
  });
}

Widget _app(HomeWidgetPort port, TargetPlatform platform) => ProviderScope(
      overrides: [homeWidgetPortProvider.overrideWithValue(port)],
      child: MaterialApp(
        theme: ThemeData(platform: platform),
        home: const WidgetSetupScreen(),
      ),
    );

class _WidgetPort implements HomeWidgetPort {
  _WidgetPort(this.value, {this.accept = true});
  final HomeWidgetAvailability value;
  final bool accept;
  int requests = 0;

  @override
  Future<HomeWidgetAvailability> availability() async => value;
  @override
  Future<bool> requestPin() async {
    requests++;
    return accept;
  }
}
