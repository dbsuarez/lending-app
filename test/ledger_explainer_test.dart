import 'package:flutter_test/flutter_test.dart';
import 'package:lending_manager/domain/models/models.dart';
import 'package:lending_manager/domain/services/ledger_explainer.dart';

/// LN-2DA66048 as recorded: ₱30,000 at 3% for 6 months, 12 × ₱2,950
/// (₱450 interest + ₱2,500 principal), five GCash payments.
LoanDetail _kristoper() {
  final dues = [
    DateTime(2025, 8, 5),
    DateTime(2025, 8, 20),
    DateTime(2025, 9, 5),
    DateTime(2025, 9, 20),
    DateTime(2025, 10, 5),
    DateTime(2025, 10, 20),
    DateTime(2025, 11, 5),
    DateTime(2025, 11, 20),
    DateTime(2025, 12, 5),
    DateTime(2025, 12, 20),
    DateTime(2026, 1, 5),
    DateTime(2026, 1, 20),
  ];
  const paid = [295000, 295000, 295000, 295000, 140000, 0, 0, 0, 0, 0, 0, 0];
  AllocationShare a(int seq, int interest, int principal) => AllocationShare(
    sequence: seq,
    interestCentavos: interest * 100,
    principalCentavos: principal * 100,
  );
  ReceivedPayment p(int pesos, DateTime at, List<AllocationShare> shares) =>
      ReceivedPayment(
        amountCentavos: pesos * 100,
        receivedAt: at,
        allocations: shares,
      );
  return LoanDetail(
    summary: LoanSummary(
      id: '2da66048-0000-0000-0000-000000000000',
      organizationId: 'o',
      borrowerId: 'b',
      borrowerName: 'Florendo, Kristoper',
      principalCentavos: 3000000,
      totalCentavos: 3540000,
      monthlyRateBasisPoints: 300,
      termMonths: 6,
      status: 'active',
      createdAt: DateTime(2025, 7, 20),
    ),
    installments: [
      for (var i = 0; i < 12; i++)
        Installment(
          sequence: i + 1,
          dueDate: dues[i],
          amountCentavos: 295000,
          principalCentavos: 250000,
          interestCentavos: 45000,
          paidCentavos: paid[i],
        ),
    ],
    payments: [
      p(2600, DateTime(2025, 8, 5), [a(1, 450, 2150)]),
      p(3370, DateTime(2025, 8, 21), [
        a(1, 0, 350),
        a(2, 450, 2500),
        a(3, 70, 0),
      ]),
      p(2780, DateTime(2025, 9, 22), [a(3, 380, 2400)]),
      p(2000, DateTime(2025, 10, 15), [a(3, 0, 100), a(4, 450, 1450)]),
      p(2450, DateTime(2025, 10, 22), [a(4, 0, 1050), a(5, 450, 950)]),
    ],
  );
}

void main() {
  final e = explainLedger(_kristoper(), today: DateTime(2026, 11, 8));

  test('each payment is described by where its money went', () {
    expect(e.payments.map(e.describe).toList(), [
      '₱2,600 to #1 (₱350 still due on #1)',
      'finished #1 (₱350), paid #2 in full (₱2,950), ₱70 to #3 (₱2,880 still due on #3)',
      '₱2,780 to #3 (₱100 still due on #3)',
      'finished #3 (₱100), ₱1,900 to #4 (₱1,050 still due on #4)',
      'finished #4 (₱1,050), ₱1,400 to #5 (₱1,550 still due on #5)',
    ]);
  });

  test('status lines summarise where the loan stands', () {
    expect(e.statusLines(today: DateTime(2026, 11, 8)), [
      '#1–#4 are fully paid.',
      '#5 is partly paid: ₱1,400 of ₱2,950 (₱1,550 left).',
      '#6–#12 are not paid yet and past due (since Oct 20, 2025).',
      'Total paid: ₱13,200. Remaining balance: ₱22,200.',
      'Next to pay: ₱1,550 for #5 (due Oct 5, 2025, past due).',
    ]);
  });

  test('customer text is chat-friendly', () {
    final text = e.customerText(today: DateTime(2026, 11, 8));
    expect(text.split('\n').first, 'Loan LN-2DA66048 – Florendo, Kristoper');
    expect(
      text,
      contains(
        '₱30,000 at 3% a month for 6 months = ₱35,400 total, in 12 installments of ₱2,950.',
      ),
    );
    expect(
      text,
      contains(
        '• Aug 21, 2025 – ₱3,370: finished #1 (₱350), paid #2 in full (₱2,950), ₱70 to #3',
      ),
    );
  });
}
