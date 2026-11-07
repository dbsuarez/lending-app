import 'package:flutter_test/flutter_test.dart';
import 'package:lending_manager/domain/models/models.dart';
import 'package:lending_manager/features/documents/loan_schedule_pdf.dart';

LoanDetail _loan() => LoanDetail(
  summary: LoanSummary(
    id: '7187dd79-0596-429f-a120-c5e7138ade9d',
    organizationId: 'org',
    borrowerId: 'b1',
    borrowerName: 'Peña, Niño',
    principalCentavos: 2000000,
    totalCentavos: 780000,
    monthlyRateBasisPoints: 600,
    termMonths: 1,
    status: 'active',
    createdAt: DateTime(2026, 11, 1),
    borrowedOn: DateTime(2026, 11, 1),
  ),
  installments: [
    // Deliberately out of order: ledger must sort by sequence.
    Installment(
      sequence: 3,
      dueDate: DateTime(2026, 12, 15),
      amountCentavos: 260000,
      principalCentavos: 200000,
      interestCentavos: 60000,
    ),
    Installment(
      sequence: 1,
      dueDate: DateTime(2026, 11, 15),
      amountCentavos: 260000,
      principalCentavos: 200000,
      interestCentavos: 60000,
      paidCentavos: 260000,
      lastPaymentAt: DateTime.utc(2026, 11, 14, 3),
    ),
    Installment(
      sequence: 2,
      dueDate: DateTime(2026, 11, 30),
      amountCentavos: 260000,
      principalCentavos: 200000,
      interestCentavos: 60000,
      paidCentavos: 100000,
      lastPaymentAt: DateTime.utc(2026, 11, 29, 3),
    ),
  ],
);

void main() {
  // PDFs load the embedded Roboto font from the asset bundle.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ledger rows run the balance down in installment order', () {
    final rows = _loan().ledgerRows(asOf: DateTime(2026, 12, 1));
    expect(rows.map((r) => r.installment.sequence), [1, 2, 3]);
    expect(rows.map((r) => r.endingBalanceCentavos), [520000, 420000, 420000]);
    // #2 is partly paid; #3 is not yet due on Dec 1.
    expect(rows.map((r) => r.status), ['paid', 'partial', 'upcoming']);
  });

  test('unpaid past-due installment is overdue', () {
    final rows = _loan().ledgerRows(asOf: DateTime(2026, 12, 20));
    expect(rows.last.status, 'overdue');
  });

  test('ledger and schedule PDFs render', () async {
    final generated = DateTime(2026, 12, 1);
    final ledger = await LoanSchedulePdf.buildLedger(
      _loan(),
      generatedOn: generated,
    );
    final schedule = await LoanSchedulePdf.build(
      _loan(),
      generatedOn: generated,
    );
    for (final bytes in [ledger, schedule]) {
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(1000));
    }
  });
}
