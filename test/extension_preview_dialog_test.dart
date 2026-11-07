import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lending_manager/domain/models/models.dart';
import 'package:lending_manager/domain/services/loan_calculator.dart';
import 'package:lending_manager/features/loans/extension_preview_dialog.dart';

LoanDetail _overdueLoan() {
  final quote = const LoanCalculator().calculate(
    principalCentavos: 2000000,
    monthlyRateBasisPoints: 600,
    termMonths: 2,
    firstDueDate: DateTime(2026, 2, 15),
    paydayPattern: const [15, 30],
  );
  return LoanDetail(
    summary: LoanSummary(
      id: '11111111-2222-3333-4444-555555555555',
      organizationId: 'org',
      borrowerId: 'b',
      borrowerName: 'Florendo, Kristoper',
      principalCentavos: quote.principalCentavos,
      totalCentavos: quote.totalCentavos,
      monthlyRateBasisPoints: 600,
      termMonths: 2,
      status: 'active',
      createdAt: DateTime(2026, 2, 1),
    ),
    installments: quote.installments,
  );
}

void main() {
  testWidgets('shows today and cutoff totals on a phone without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ExtensionPreviewDialog(
              _overdueLoan(),
              today: DateTime(2026, 11, 7),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Preview only'), findsOneWidget);
    expect(find.text('As of 2026-11-07'), findsOneWidget);
    expect(find.text('At payday cutoff 2026-11-15'), findsOneWidget);
    // Cutoff: ₱22,400 unpaid + 6% x ₱20,000 x 7.5 months (₱9,000).
    await tester.scrollUntilVisible(find.text('₱31,400.00'), 200);
    expect(find.text('₱31,400.00'), findsOneWidget);

    // Switching the interest base keeps the same result here (nothing paid).
    await tester.tap(find.text('Original'));
    await tester.pumpAndSettle();
    expect(find.text('₱31,400.00'), findsOneWidget);
  });
}
