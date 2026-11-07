import 'package:flutter_test/flutter_test.dart';
import 'package:lending_manager/domain/models/models.dart';
import 'package:lending_manager/features/loans/loan_detail_screen.dart';

LoanDetail _loan(
  String status, {
  List<int> paid = const [0, 0],
  DateTime? borrowedOn,
  DateTime? paidOn,
}) => LoanDetail(
  summary: LoanSummary(
    id: '11111111-2222-3333-4444-555555555555',
    organizationId: 'o',
    borrowerId: 'b',
    borrowerName: 'Florendo, Kristoper',
    principalCentavos: 1000000,
    totalCentavos: 1120000,
    monthlyRateBasisPoints: 600,
    termMonths: 1,
    status: status,
    createdAt: DateTime(2026, 10, 1),
    borrowedOn: borrowedOn,
    paidOn: paidOn,
  ),
  installments: [
    Installment(
      sequence: 1,
      dueDate: DateTime(2026, 10, 15),
      amountCentavos: 560000,
      principalCentavos: 500000,
      interestCentavos: 60000,
      paidCentavos: paid[0],
    ),
    Installment(
      sequence: 2,
      dueDate: DateTime(2026, 11, 15),
      amountCentavos: 560000,
      principalCentavos: 500000,
      interestCentavos: 60000,
      paidCentavos: paid[1],
    ),
  ],
);

void main() {
  final today = DateTime(2026, 11, 7);

  test('active loan says money was released, not "draft"', () {
    final text = financialStateText(
      _loan('active', paid: [560000, 0], borrowedOn: DateTime(2026, 10, 1)),
      today: today,
    );
    expect(text, isNot(contains('draft')));
    expect(text, contains('Money released on 2026-10-01'));
    expect(text, contains('₱5,600.00 paid so far'));
    expect(text, contains('₱5,600.00 still owed'));
    expect(text, contains('Next due: ₱5,600.00 on 2026-11-15'));
    expect(text, isNot(contains('past due')));
  });

  test('active loan flags past-due installments', () {
    final text = financialStateText(
      _loan('active', borrowedOn: DateTime(2026, 10, 1)),
      today: today,
    );
    expect(text, contains('1 installment is past due'));
    expect(text, contains('Next due: ₱5,600.00 on 2026-10-15'));
  });

  test('each closed status has its own message', () {
    expect(
      financialStateText(
        _loan(
          'fully_paid',
          paid: [560000, 560000],
          paidOn: DateTime(2026, 11, 5),
        ),
      ),
      'Fully paid on 2026-11-05. Nothing is owed.',
    );
    expect(financialStateText(_loan('cancelled')), contains('cancelled'));
    expect(financialStateText(_loan('refinanced')), contains('refinanced'));
    expect(financialStateText(_loan('draft')), contains('No money has been'));
  });
}
