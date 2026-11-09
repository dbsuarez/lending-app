import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lending_manager/domain/models/models.dart';
import 'package:lending_manager/features/documents/loan_schedule_pdf.dart';
import 'package:lending_manager/features/settings/business_profile_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const business = BusinessProfile(
    name: 'Sample Lending',
    phone: '0917 000 0000',
    email: 'hello@example.test',
    address: 'Quezon City, Metro Manila',
  );
  const borrower = Borrower(
    id: 'b1',
    organizationId: 'o',
    firstName: 'Maria',
    lastName: 'Dela Cruz',
    phone: '0917 555 0101',
    address: 'Pasig City',
  );
  final loan = LoanDetail(
    summary: LoanSummary(
      id: 'abcdef12-0000-0000-0000-000000000000',
      organizationId: 'o',
      borrowerId: 'b1',
      borrowerName: 'Dela Cruz, Maria',
      principalCentavos: 1000000,
      totalCentavos: 1150000,
      monthlyRateBasisPoints: 500,
      termMonths: 3,
      status: 'active',
      createdAt: DateTime(2026, 9, 1),
      borrowedOn: DateTime(2026, 9, 1),
    ),
    installments: [
      for (var i = 0; i < 6; i++)
        Installment(
          sequence: i + 1,
          dueDate: DateTime(2026, 9 + i ~/ 2, i.isEven ? 15 : 30),
          amountCentavos: i == 5 ? 191670 : 191666,
          principalCentavos: 166666,
          interestCentavos: 25000,
          paidCentavos: i < 2 ? 191666 : 0,
          lastPaymentAt: i < 2 ? DateTime(2026, 9, 15 + i * 15) : null,
        ),
    ],
    payments: [
      ReceivedPayment(
        amountCentavos: 191666,
        receivedAt: DateTime(2026, 9, 15, 10),
        appliedSequence: 1,
        allocations: const [
          AllocationShare(
            sequence: 1,
            interestCentavos: 25000,
            principalCentavos: 166666,
          ),
        ],
      ),
      ReceivedPayment(
        amountCentavos: 191666,
        receivedAt: DateTime(2026, 10, 2, 10),
        appliedSequence: 2,
      ),
    ],
  );
  final payment = PaymentSummary(
    id: 'deadbeef-0000-0000-0000-000000000000',
    loanId: loan.summary.id,
    borrowerName: loan.summary.borrowerName,
    amountCentavos: 191666,
    receivedAt: DateTime(2026, 9, 15, 10),
    method: 'GCash',
    reference: '1234 5678 9012',
    status: 'verified',
  );

  test('amounts in words', () {
    expect(amountInWords(100), 'One peso only');
    expect(amountInWords(125050), 'One thousand two hundred fifty pesos and 50/100');
    expect(
      amountInWords(1000000),
      'Ten thousand pesos only',
    );
    expect(
      amountInWords(191666),
      'One thousand nine hundred sixteen pesos and 66/100',
    );
  });

  test('every document builds', () async {
    final out = Platform.environment['PDF_OUT'];
    final docs = {
      'receipt': await LoanDocumentsPdf.receipt(
        loan: loan,
        payment: payment,
        business: business,
        issuedOn: DateTime(2026, 11, 9),
      ),
      'statement': await LoanDocumentsPdf.statement(
        loan: loan,
        business: business,
        asOf: DateTime(2026, 11, 9),
      ),
      'agreement': await LoanDocumentsPdf.agreement(
        loan: loan,
        business: business,
        borrower: borrower,
        releasedOn: DateTime(2026, 9, 1),
      ),
      'acknowledgment': await LoanDocumentsPdf.acknowledgment(
        loan: loan,
        business: business,
        borrower: borrower,
        releasedOn: DateTime(2026, 9, 1),
        method: 'GCash',
        reference: 'REL-1',
      ),
      'schedule': await LoanSchedulePdf.build(loan, business: business),
    };
    for (final entry in docs.entries) {
      expect(entry.value.length, greaterThan(1000), reason: entry.key);
      if (out != null) File('$out/${entry.key}.pdf').writeAsBytesSync(entry.value);
    }
  });
}
