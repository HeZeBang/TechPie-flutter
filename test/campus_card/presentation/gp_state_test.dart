import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/core/errors/app_failure.dart';
import 'package:techpie/features/campus_card/presentation/icons/geekpay_icons.dart';
import 'package:techpie/features/campus_card/presentation/theme/theme.dart';
import 'package:techpie/features/campus_card/presentation/widgets/gp_state.dart';

void main() {
  testWidgets('shows only AppFailure safeMessage and never its cause', (
    tester,
  ) async {
    const causeMarker = 'SYNTHETIC_RAW_CAUSE_MUST_NOT_RENDER';
    const failure = AppFailure(
      FailureKind.server,
      '操作失败，请稍后重试',
      cause: causeMarker,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: GeekPayTheme.inherit(ThemeData.light()),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: GpStateView.error(failure, onRetry: () {}),
          ),
        ),
      ),
    );

    expect(GpStateView.safeUiError(failure), '操作失败，请稍后重试');
    expect(find.text('操作失败，请稍后重试'), findsOneWidget);
    expect(find.textContaining(causeMarker), findsNothing);
    expect(find.byType(GpIcon), findsNothing);
  });

  test('classifies AppFailure network kinds without reading raw text', () {
    expect(
      GpStateView.errorIsNetwork(
        const AppFailure(FailureKind.network, '网络不可用'),
      ),
      isTrue,
    );
    expect(
      GpStateView.errorIsNetwork(const AppFailure(FailureKind.timeout, '连接超时')),
      isTrue,
    );
    expect(
      GpStateView.errorIsNetwork(const AppFailure(FailureKind.server, '服务失败')),
      isFalse,
    );
    expect(GpStateView.safeUiError(StateError('synthetic raw')), '发生未知错误');
  });
}
