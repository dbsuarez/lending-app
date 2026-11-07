import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lending_manager/features/dashboard/refined_dashboard_screen.dart';

void main() {
  for (final scenario in <({String name, Size size})>[
    (name: 'phone_390x844', size: const Size(390, 844)),
    (name: 'tablet_1024x768', size: const Size(1024, 768)),
    (name: 'desktop_1440x900', size: const Size(1440, 900)),
  ]) {
    testWidgets('dashboard responsive golden ${scenario.name}', (tester) async {
      tester.view.physicalSize = scenario.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(body: RefinedDashboardScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/dashboard_${scenario.name}.png'),
      );
    });
  }
}
