import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/utils/platform.dart';
import 'package:techpie/widgets/adaptive_checkbox.dart';
import 'package:techpie/widgets/adaptive_context_menu.dart';
import 'package:techpie/widgets/adaptive_date_picker.dart';
import 'package:techpie/widgets/adaptive_option_sheet.dart';
import 'package:techpie/widgets/adaptive_popup_menu_button.dart';
import 'package:techpie/widgets/adaptive_progress_indicator.dart';
import 'package:techpie/widgets/adaptive_slider.dart';
import 'package:techpie/widgets/adaptive_switch.dart';
import 'package:techpie/widgets/design_system/design_system.dart';
import 'package:techpie/widgets/macos/macos_native_controls.dart';
import 'package:techpie/widgets/schedule_picker_sheet.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  Map<String, ({int id, List<MethodCall> calls})> installMacOsPlatformViewMocks(
    WidgetTester tester,
  ) {
    final messenger = tester.binding.defaultBinaryMessenger;
    final byType = <String, ({int id, List<MethodCall> calls})>{};
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (call) async {
      if (call.method == 'create') {
        final args = call.arguments as Map<Object?, Object?>;
        final id = args['id'] as int;
        final viewType = args['viewType'] as String;
        final calls = <MethodCall>[];
        byType[viewType] = (id: id, calls: calls);
        messenger.setMockMethodCallHandler(
          MethodChannel('${viewType}_$id'),
          (subCall) async {
            calls.add(subCall);
            if (subCall.method == 'getIntrinsicSize') {
              return <String, double>{'width': 140.0};
            }
            return null;
          },
        );
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform_views, null),
    );
    return byType;
  }

  Future<void> emitFromNative(
    WidgetTester tester,
    String viewType,
    int id,
    String method,
    Object? arguments,
  ) async {
    const codec = StandardMethodCodec();
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      '${viewType}_$id',
      codec.encodeMethodCall(MethodCall(method, arguments)),
      (_) {},
    );
  }

  testWidgets(
    'Mac AppKit Switch, SegmentedControl, Slider, Checkbox sync props and dark mode',
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    (tester) async {
      final mocks = installMacOsPlatformViewMocks(tester);
      var switched = false;
      var segment = 0;
      var slider = 12.0;
      var checked = false;
      var brightness = Brightness.light;
      var enabled = true;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              body: Column(
                children: [
                  AdaptiveSwitch(
                    value: switched,
                    enabled: enabled,
                    semanticLabel: '自动同步',
                    onChanged: (v) => setState(() => switched = v),
                  ),
                  MacosNativeSegmentedControl(
                    selectedIndex: segment,
                    labels: const ['完成进度', '完整方案'],
                    enabled: enabled,
                    onValueChanged: (v) => setState(() => segment = v),
                  ),
                  AdaptiveSlider(
                    value: slider,
                    min: 0,
                    max: 100,
                    divisions: 20,
                    enabled: enabled,
                    onChanged: (v) => setState(() => slider = v),
                  ),
                  AdaptiveCheckbox(
                    value: checked,
                    enabled: enabled,
                    semanticLabel: '发送用户名',
                    onChanged: (v) => setState(() => checked = v ?? false),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      brightness = Brightness.dark;
                      enabled = false;
                      switched = true;
                      segment = 1;
                      slider = 45.0;
                      checked = true;
                    }),
                    child: const Text('Mutate'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final views = tester.widgetList<AppKitView>(find.byType(AppKitView)).toList();
      expect(views, hasLength(4));
      expect(mocks.keys, hasLength(4));

      await emitFromNative(
        tester,
        'TechPieMacSwitch',
        mocks['TechPieMacSwitch']!.id,
        'valueChanged',
        {'value': true},
      );
      await emitFromNative(
        tester,
        'TechPieMacSegmentedControl',
        mocks['TechPieMacSegmentedControl']!.id,
        'valueChanged',
        {'index': 1},
      );
      await emitFromNative(
        tester,
        'TechPieMacSlider',
        mocks['TechPieMacSlider']!.id,
        'valueChanged',
        {'value': 30.0},
      );
      await emitFromNative(
        tester,
        'TechPieMacCheckbox',
        mocks['TechPieMacCheckbox']!.id,
        'valueChanged',
        {'value': true},
      );
      await tester.pumpAndSettle();

      expect(switched, isTrue);
      expect(segment, 1);
      expect(slider, 30.0);
      expect(checked, isTrue);

      await tester.tap(find.text('Mutate'));
      await tester.pumpAndSettle();

      for (final entry in mocks.values) {
        final methods = entry.calls.map((c) => c.method).toList();
        expect(methods, containsAll(['setBrightness', 'setEnabled']));
      }
      expect(
        mocks['TechPieMacSlider']!.calls.where((c) => c.method == 'setValue').last.arguments,
        {'value': 45.0},
      );
    },
  );

  testWidgets(
    'AdaptivePopupMenuButton renders pullsDown NSPopUpButton and dispatches selection',
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    (tester) async {
      final mocks = installMacOsPlatformViewMocks(tester);
      String? selected;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptivePopupMenuButton<String>(
              tooltip: '更多操作',
              onSelected: (value) => selected = value,
              items: const [
                AdaptivePopupMenuItem<String>(
                  value: 'toggle',
                  label: '显示作业',
                  checked: true,
                ),
                AdaptivePopupMenuItem<String>.divider(),
                AdaptivePopupMenuItem<String>(
                  value: 'clear',
                  label: '删除',
                  sfSymbol: 'trash',
                  destructive: true,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final view = tester.widget<AppKitView>(find.byType(AppKitView));
      expect(view.viewType, 'TechPieMacPopUpButton');
      final params = view.creationParams as Map<Object?, Object?>;
      expect(params['pullsDown'], isTrue);
      expect(params['borderless'], isTrue);

      final id = mocks['TechPieMacPopUpButton']!.id;
      await emitFromNative(tester, 'TechPieMacPopUpButton', id, 'itemSelected', {'index': 2});
      await tester.pumpAndSettle();
      expect(selected, 'clear');
    },
  );

  testWidgets(
    'showAdaptiveContextMenu uses NSMenu channel on macOS and falls back on MissingPluginException',
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    (tester) async {
      debugForceMacosNativeUiModals = true;
      try {
        const macChannel = MethodChannel('techpie/macos_native_ui');
        MethodCall? capturedCall;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          macChannel,
          (call) async {
            capturedCall = call;
            return 1;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            macChannel,
            null,
          ),
        );

        String? picked;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    picked = await showAdaptiveContextMenu<String>(
                      context: context,
                      globalPosition: const Offset(120, 80),
                      items: const [
                        AdaptiveContextMenuItem<String>(
                          value: 'edit',
                          label: '编辑主页布局',
                          sfSymbol: 'square.grid.2x2',
                        ),
                        AdaptiveContextMenuItem<String>(
                          value: 'remove',
                          label: '隐藏卡片',
                          sfSymbol: 'eye.slash',
                          destructive: true,
                        ),
                      ],
                    );
                  },
                  child: const Text('OpenMenu'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('OpenMenu'));
        await tester.pumpAndSettle();
        expect(capturedCall?.method, 'showContextMenu');
        expect(picked, 'remove');

        // Unregistered/missing plugin -> MissingPluginException triggers Flutter fallback menu.
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          macChannel,
          (_) async => throw MissingPluginException('missing'),
        );
        picked = null;
        await tester.tap(find.text('OpenMenu'));
        await tester.pumpAndSettle();
        expect(find.text('编辑主页布局'), findsOneWidget);
        await tester.tap(find.text('编辑主页布局'));
        await tester.pumpAndSettle();
        expect(picked, 'edit');
      } finally {
        debugForceMacosNativeUiModals = false;
      }
    },
  );

  testWidgets(
    'showAdaptiveDatePicker uses platform-appropriate dialog or sheet',
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
    (tester) async {
      DateTime? picked;
      final initial = DateTime(2026, 3, 10);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  picked = await showAdaptiveDatePicker(
                    context: context,
                    initialDate: initial,
                    firstDate: DateTime(2026, 1, 1),
                    lastDate: DateTime(2026, 12, 31),
                  );
                },
                child: const Text('PickDate'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('PickDate'));
      await tester.pumpAndSettle();

      if (defaultTargetPlatform == TargetPlatform.macOS) {
        expect(find.byType(Dialog), findsOneWidget);
        expect(find.byType(CalendarDatePicker), findsOneWidget);
        await tester.tap(find.text('确定'));
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        expect(find.byType(CupertinoDatePicker), findsOneWidget);
        expect(find.byType(IosSheetHeader), findsOneWidget);
        tester.widget<IosSheetHeader>(find.byType(IosSheetHeader)).onConfirm!();
      } else {
        expect(find.byType(DatePickerDialog), findsOneWidget);
        await tester.tap(find.text('OK'));
      }

      await tester.pumpAndSettle();
      expect(picked, initial);
    },
  );

  testWidgets(
    'showAdaptiveDateRangePicker uses macOS desktop CalendarDatePicker dialog',
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    (tester) async {
      installMacOsPlatformViewMocks(tester);
      DateTimeRange? picked;
      final initialRange = DateTimeRange(
        start: DateTime(2026, 3, 10),
        end: DateTime(2026, 3, 12),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  picked = await showAdaptiveDateRangePicker(
                    context: context,
                    initialDateRange: initialRange,
                    firstDate: DateTime(2026, 1, 1),
                    lastDate: DateTime(2026, 12, 31),
                  );
                },
                child: const Text('PickRange'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('PickRange'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(CalendarDatePicker), findsOneWidget);
      expect(find.byType(TpSegmentedControl), findsOneWidget);
      await tester.tap(find.text('结束日期'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(picked, initialRange);
    },
  );

  testWidgets(
    'showAdaptiveDateRangePicker uses Cupertino picker sheet on iOS',
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    (tester) async {
      DateTimeRange? picked;
      final initialRange = DateTimeRange(
        start: DateTime(2026, 3, 10),
        end: DateTime(2026, 3, 12),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  picked = await showAdaptiveDateRangePicker(
                    context: context,
                    initialDateRange: initialRange,
                    firstDate: DateTime(2026, 1, 1),
                    lastDate: DateTime(2026, 12, 31),
                  );
                },
                child: const Text('PickRange'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('PickRange'));
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoDatePicker), findsOneWidget);
      expect(find.text('开始日期'), findsOneWidget);
      await tester.tap(find.text('结束日期'));
      await tester.pumpAndSettle();

      expect(find.byType(IosSheetHeader), findsOneWidget);
      tester.widget<IosSheetHeader>(find.byType(IosSheetHeader)).onConfirm!();
      await tester.pumpAndSettle();
      expect(picked, initialRange);
    },
  );

  testWidgets(
    'AdaptiveActivityIndicator uses CupertinoActivityIndicator on Apple and CircularProgressIndicator elsewhere',
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveActivityIndicator(
              size: 18,
              semanticLabel: '加载中',
            ),
          ),
        ),
      );

      if (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.iOS) {
        expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      } else {
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.byType(CupertinoActivityIndicator), findsNothing);
      }
    },
  );

  testWidgets(
    'showAdaptiveOptionSheet adapts between iOS CupertinoActionSheet, macOS Dialog, and Material SimpleDialog',
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
    (tester) async {
      String? picked;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  picked = await showAdaptiveOptionSheet<String>(
                    context: context,
                    title: '选择操作',
                    message: '仅作用于当前列表',
                    selectedValue: 'b',
                    options: const [
                      AdaptiveOptionItem(value: 'a', label: '选项一'),
                      AdaptiveOptionItem(value: 'b', label: '选项二'),
                    ],
                  );
                },
                child: const Text('OpenOptions'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('OpenOptions'));
      await tester.pumpAndSettle();

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        expect(find.byType(CupertinoActionSheet), findsOneWidget);
        expect(find.text('选项二 ✓'), findsOneWidget);
        await tester.tap(find.text('选项一'));
      } else if (defaultTargetPlatform == TargetPlatform.macOS) {
        expect(find.byType(Dialog), findsOneWidget);
        await tester.tap(find.text('选项一'));
      } else {
        expect(find.byType(SimpleDialog), findsOneWidget);
        await tester.tap(find.text('选项一'));
      }

      await tester.pumpAndSettle();
      expect(picked, 'a');
    },
  );
}
