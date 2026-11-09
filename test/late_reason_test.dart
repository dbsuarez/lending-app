import 'package:flutter_test/flutter_test.dart';
import 'package:lending_manager/domain/models/models.dart';
import 'package:lending_manager/features/payments/payment_edit_dialog.dart';

LoanDetail loan(List<Installment> installments) => LoanDetail(
  summary: LoanSummary(
    id: 'l1',
    organizationId: 'o',
    borrowerId: 'b',
    borrowerName: 'Test',
    principalCentavos: 1000000,
    totalCentavos: 1050000,
    monthlyRateBasisPoints: 500,
    termMonths: 1,
    status: 'active',
    createdAt: DateTime(2026, 10, 1),
  ),
  installments: installments,
);

Installment due(int seq, DateTime date, {int paid = 0}) => Installment(
  sequence: seq,
  dueDate: date,
  amountCentavos: 525000,
  principalCentavos: 500000,
  interestCentavos: 25000,
  paidCentavos: paid,
);

void main() {
  final schedule = [
    due(1, DateTime(2026, 10, 15)),
    due(2, DateTime(2026, 10, 30)),
  ];

  test('on or before the due date is not late', () {
    expect(lateness(loan(schedule), DateTime(2026, 10, 15, 23, 59)), isNull);
    expect(lateness(loan(schedule), DateTime(2026, 10, 1)), isNull);
  });

  test('days late are counted from the oldest unpaid installment', () {
    final late = lateness(loan(schedule), DateTime(2026, 10, 20, 9));
    expect(late?.days, 5);
    expect(late?.due, DateTime(2026, 10, 15));
  });

  test('a paid installment no longer counts', () {
    final partlyPaid = [
      due(1, DateTime(2026, 10, 15), paid: 525000),
      due(2, DateTime(2026, 10, 30)),
    ];
    expect(lateness(loan(partlyPaid), DateTime(2026, 10, 20)), isNull);
    expect(lateness(loan(partlyPaid), DateTime(2026, 11, 2))?.days, 3);
  });

  test('a fully paid loan is never late', () {
    final paid = [
      due(1, DateTime(2026, 10, 15), paid: 525000),
      due(2, DateTime(2026, 10, 30), paid: 525000),
    ];
    expect(lateness(loan(paid), DateTime(2027, 1, 1)), isNull);
  });
}
