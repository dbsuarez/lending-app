import 'package:flutter_test/flutter_test.dart';
import 'package:lending_manager/domain/models/models.dart';

Installment _inst(int seq, DateTime due, {int paid = 0}) => Installment(
  sequence: seq,
  dueDate: due,
  amountCentavos: 260000,
  principalCentavos: 200000,
  interestCentavos: 60000,
  paidCentavos: paid,
);

ReceivedPayment _pay(int pesos, DateTime at) =>
    ReceivedPayment(amountCentavos: pesos * 100, receivedAt: at);

LoanDetail _loan(List<ReceivedPayment> payments) => LoanDetail(
  summary: LoanSummary(
    id: '11111111-2222-3333-4444-555555555555',
    organizationId: 'o',
    borrowerId: 'b',
    borrowerName: 'Florendo, Kristoper',
    principalCentavos: 600000,
    totalCentavos: 780000,
    monthlyRateBasisPoints: 1000,
    termMonths: 1,
    status: 'active',
    createdAt: DateTime(2026, 11, 1),
  ),
  installments: [
    _inst(1, DateTime(2026, 11, 15), paid: 260000),
    _inst(2, DateTime(2026, 11, 30), paid: 260000),
    _inst(3, DateTime(2026, 12, 15), paid: 40000),
  ],
  payments: payments,
);

void main() {
  test('each cutoff shows what was actually received in it', () {
    final loan = _loan([
      _pay(3000, DateTime(2026, 11, 14, 10)), // early in cutoff 1 (overpaid)
      _pay(2200, DateTime(2026, 11, 30, 18)), // on cutoff 2's due date
      _pay(500, DateTime(2026, 12, 20, 9)), // after the final due date
    ]);
    final rows = loan.ledgerRows(asOf: DateTime(2026, 12, 31));
    expect(rows.map((r) => r.receivedCentavos), [300000, 220000, 0]);
    // Applied amounts still come from allocations (3,000 split 2,600 + 400).
    expect(rows.map((r) => r.installment.paidCentavos), [
      260000,
      260000,
      40000,
    ]);
    expect(rows[0].received.single.receivedOn, DateTime(2026, 11, 14));
    expect(loan.paymentsAfterFinalDue.single.amountCentavos, 50000);
  });

  test('a payment on the day after a due date belongs to the next cutoff', () {
    final rows = _loan([
      _pay(2600, DateTime(2026, 11, 16, 8)),
    ]).ledgerRows(asOf: DateTime(2026, 12, 1));
    expect(rows.map((r) => r.receivedCentavos), [0, 260000, 0]);
  });

  test('uses the local calendar day of the payment', () {
    // 2026-11-15 20:00 UTC is already 2026-11-16 04:00 in Manila (UTC+8);
    // the ledger uses the device's local day.
    final payment = _pay(100, DateTime.utc(2026, 11, 15, 20));
    final local = payment.receivedAt.toLocal();
    expect(payment.receivedOn, DateTime(local.year, local.month, local.day));
  });

  test('several payments in one cutoff are added up', () {
    final rows = _loan([
      _pay(1000, DateTime(2026, 11, 20)),
      _pay(1600, DateTime(2026, 11, 29)),
    ]).ledgerRows(asOf: DateTime(2026, 12, 1));
    expect(rows[1].receivedCentavos, 260000);
    expect(rows[1].received, hasLength(2));
  });
}
