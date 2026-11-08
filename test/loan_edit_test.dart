import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lending_manager/core/undo/undo_controller.dart';
import 'package:lending_manager/domain/models/models.dart';
import 'package:lending_manager/domain/services/loan_calculator.dart';
import 'package:lending_manager/features/loans/loan_form_screen.dart';
import 'package:lending_manager/features/loans/loans_controller.dart';

void main() {
  testWidgets('Edit Draft: prefilled, saves new terms, undo restores', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final loans = container.read(loansControllerProvider.notifier);
    final quote = const LoanCalculator().calculate(
      principalCentavos: 2000000,
      monthlyRateBasisPoints: 600,
      termMonths: 5,
      firstDueDate: DateTime(2026, 11, 15),
      paydayPattern: const [15, 30],
    );
    final id = (await loans.createDraft(
      borrower: const Borrower(
        id: 'b1',
        organizationId: 'demo',
        firstName: 'Daniel',
        lastName: 'Test',
      ),
      quote: quote,
      firstDueDate: DateTime(2026, 11, 15),
      paydayPattern: const [15, 30],
    ))!;

    final router = GoRouter(
      initialLocation: '/loans/$id/edit',
      routes: [
        GoRoute(
          path: '/loans/:loanId/edit',
          builder: (c, s) => Scaffold(
            body: LoanFormScreen(loanId: s.pathParameters['loanId']),
          ),
        ),
        GoRoute(
          path: '/loans/:loanId',
          builder: (c, s) => const Scaffold(body: Text('LOAN PAGE')),
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Edit draft'), findsOneWidget);
    // Prefilled from the draft.
    expect(find.widgetWithText(TextFormField, '20000'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '5'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, '20000'),
      '15000',
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // Review shows before/after.
    expect(find.text('Before'), findsOneWidget);
    expect(find.text('₱20,000.00'), findsWidgets);
    expect(find.text('₱15,000.00'), findsWidgets);

    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(find.text('LOAN PAGE'), findsOneWidget);

    final saved = (await loans.fetchDetail(id)).summary;
    expect(saved.principalCentavos, 1500000);
    expect(saved.status, 'draft');

    // Undo restores the original terms.
    expect(await loans.undoLoanCorrection('local-$id'), isTrue);
    expect((await loans.fetchDetail(id)).summary.principalCentavos, 2000000);
  });
}
