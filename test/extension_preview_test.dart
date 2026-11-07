import 'package:flutter_test/flutter_test.dart';
import 'package:lending_manager/domain/models/models.dart';
import 'package:lending_manager/domain/services/extension_preview.dart';
import 'package:lending_manager/domain/services/loan_calculator.dart';

/// ₱20,000 at 6%/month for 2 months on the 15th/30th: four ₱5,600
/// installments (₱5,000 principal + ₱600 interest), last due 2026-03-30.
LoanDetail _loan({List<int> paid = const [0, 0, 0, 0]}) {
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
    installments: [
      for (var i = 0; i < quote.installments.length; i++)
        Installment(
          sequence: quote.installments[i].sequence,
          dueDate: quote.installments[i].dueDate,
          amountCentavos: quote.installments[i].amountCentavos,
          principalCentavos: quote.installments[i].principalCentavos,
          interestCentavos: quote.installments[i].interestCentavos,
          paidCentavos: paid[i],
        ),
    ],
  );
}

void main() {
  const calc = ExtensionCalculator();

  test('reads the 15th/30th pattern even with a clamped Feb 28', () {
    final loan = _loan();
    expect(loan.installments.map((i) => i.dueDate.day), [15, 28, 15, 30]);
    expect(calc.paydayPattern(loan), [15, 30]);
  });

  test('cutoff on or after a date follows the payday pattern', () {
    expect(
      calc.cutoffOnOrAfter(DateTime(2026, 11, 7), [15, 30]),
      DateTime(2026, 11, 15),
    );
    expect(
      calc.cutoffOnOrAfter(DateTime(2026, 11, 16), [15, 30]),
      DateTime(2026, 11, 30),
    );
    expect(
      calc.cutoffOnOrAfter(DateTime(2027, 2, 16), [15, 30]),
      DateTime(2027, 2, 28),
    );
    expect(
      calc.cutoffOnOrAfter(DateTime(2026, 12, 31), [15, 30]),
      DateTime(2027, 1, 15),
    );
  });

  test('nothing paid: unpaid schedule plus extra interest to the cutoff', () {
    // From 2026-03-30 to the 2026-11-15 cutoff: 15 cutoffs = 7.5 months.
    final p = calc.asOfCutoff(_loan(), DateTime(2026, 11, 7));
    expect(p.asOf, DateTime(2026, 11, 15));
    expect(p.finalDueDate, DateTime(2026, 3, 30));
    expect(p.extensionMonths, 7.5);
    expect(p.unpaidPrincipalCentavos, 2000000);
    expect(p.unpaidInterestCentavos, 240000);
    // 6% x ₱20,000 x 7.5 = ₱9,000
    expect(p.extensionInterestCentavos, 900000);
    expect(p.totalCentavos, 2000000 + 240000 + 900000);
  });

  test(
    'partly paid: interest is applied first, extra interest on the rest',
    () {
      // First installment fully paid, second partly (₱1,000: interest ₱600,
      // principal ₱400).
      final loan = _loan(paid: [560000, 100000, 0, 0]);
      final p = calc.asOfCutoff(loan, DateTime(2026, 11, 7));
      expect(p.unpaidInterestCentavos, 120000);
      expect(p.unpaidPrincipalCentavos, 2000000 - 500000 - 40000);
      expect(p.interestBaseCentavos, 1460000);
      expect(p.extensionInterestCentavos, (1460000 * 0.06 * 7.5).round());

      final original = calc.asOfCutoff(
        loan,
        DateTime(2026, 11, 7),
        base: ExtensionInterestBase.originalPrincipal,
      );
      expect(original.interestBaseCentavos, 2000000);
      expect(original.extensionInterestCentavos, 900000);
    },
  );

  test('as of today pro-rates the part month by days', () {
    final p = calc.asOfDate(_loan(), DateTime(2026, 11, 7));
    final days = DateTime(2026, 11, 7).difference(DateTime(2026, 3, 30)).inDays;
    expect(
      p.extensionMonths,
      closeTo(days / ExtensionCalculator.daysPerMonth, 1e-9),
    );
    expect(p.asOf, DateTime(2026, 11, 7));
  });

  test('a date before the final due date adds no extra interest', () {
    final p = calc.asOfDate(_loan(), DateTime(2026, 3, 1));
    expect(p.extensionMonths, 0);
    expect(p.extensionInterestCentavos, 0);
    expect(p.totalCentavos, 2240000);
  });
}
