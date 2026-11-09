import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lending_manager/core/undo/undo_controller.dart';
import 'package:lending_manager/app/app.dart';
import 'package:lending_manager/features/borrowers/borrowers_screen.dart';
import 'package:lending_manager/features/loans/loan_form_screen.dart';

void main() {
  testWidgets('loan form opens with a stable payday selection', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          home: Scaffold(body: LoanFormScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('15th and 30th'), findsOneWidget);
    expect(find.text('Principal (PHP)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('local borrower workflow creates a record', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          home: Scaffold(body: BorrowersScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'initial borrowers screen');

    await tester.tap(find.text('Add borrower…'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'borrower dialog');
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Test');
    await tester.enterText(fields.at(1), 'Borrower');
    await tester.tap(find.text('Borrower consent confirmed'));
    await tester.tap(find.text('Create Borrower'));
    await tester.pumpAndSettle();

    expect(find.text('Borrower, Test'), findsOneWidget);
    expect(find.text('Borrower created.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow dashboard cards have bounded height', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: LendingManagerApp()));
    await tester.pumpAndSettle();
    if (find.text('Enter local demo').evaluate().isNotEmpty) {
      await tester.tap(find.text('Enter local demo'));
      await tester.pumpAndSettle();
    }

    expect(find.text("Today's Collections"), findsOneWidget);
    expect(find.text('Recent Payments'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('local demo reaches dashboard', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: LendingManagerApp()));
    await tester.pumpAndSettle();
    if (find.text('Enter local demo').evaluate().isNotEmpty) {
      await tester.tap(find.text('Enter local demo'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Outstanding Loans'), findsOneWidget);
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.text('Reports'), findsWidgets);
    expect(find.text('Documents'), findsWidgets);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('desktop shell follows palette and dark mode without errors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ProviderScope(child: LendingManagerApp()));
    await tester.pumpAndSettle();
    if (find.text('Enter local demo').evaluate().isNotEmpty) {
      await tester.tap(find.text('Enter local demo'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byTooltip('Collapse navigation'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Expand navigation'), findsOneWidget);
    await tester.tap(find.byTooltip('Expand navigation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Emerald'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
