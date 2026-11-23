import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/widgets/startup_page.dart';

void main() {
  testWidgets('startup page shows branding then reveals its child', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: StartupPage(
          minimumDuration: Duration(milliseconds: 100),
          child: Scaffold(body: Text('App')),
        ),
      ),
    );

    expect(find.text('TechPie'), findsOneWidget);
    expect(find.text('App'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 101));

    expect(find.text('TechPie'), findsNothing);
    expect(find.text('App'), findsOneWidget);
  });
}
