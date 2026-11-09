import 'package:flutter_test/flutter_test.dart';
import 'package:lending_manager/app/global_search.dart';
import 'package:lending_manager/domain/models/models.dart';

void main() {
  const borrowers = [
    Borrower(
      id: 'b1',
      organizationId: 'o',
      firstName: 'Maria',
      lastName: 'Dela Cruz',
      phone: '0917 555 0101',
    ),
    Borrower(
      id: 'b2',
      organizationId: 'o',
      firstName: 'Ramon',
      lastName: 'Santos',
    ),
  ];
  final loans = [
    LoanSummary(
      id: '6b98df02-0000-0000-0000-000000000000',
      organizationId: 'o',
      borrowerId: 'b1',
      borrowerName: 'Dela Cruz, Maria',
      principalCentavos: 1000000,
      totalCentavos: 1150000,
      monthlyRateBasisPoints: 500,
      termMonths: 3,
      status: 'active',
      createdAt: DateTime(2026, 9, 1),
    ),
  ];
  final payments = [
    PaymentSummary(
      id: '4dd3e52a-0000-0000-0000-000000000000',
      loanId: loans.first.id,
      borrowerName: 'Dela Cruz, Maria',
      amountCentavos: 287500,
      receivedAt: DateTime(2026, 10, 2),
      method: 'GCash',
      reference: '1234 5678 9012',
      status: 'verified',
    ),
  ];
  List<String> find(String q) => [
    for (final h in searchEverything(
      query: q,
      borrowers: borrowers,
      loans: loans,
      payments: payments,
    ))
      '${h.group}:${h.route}',
  ];

  test('too short finds nothing', () => expect(find('m'), isEmpty));

  test('name finds the borrower and their loan', () {
    expect(
      find('maria'),
      containsAll([
        'Borrowers:/borrowers/b1',
        'Loans:/loans/${loans.first.id}?from=loans',
      ]),
    );
    expect(find('cruz maria'), contains('Borrowers:/borrowers/b1'));
  });

  test('phone digits find the borrower', () {
    expect(find('5550101'), contains('Borrowers:/borrowers/b1'));
  });

  test('loan number with or without LN-', () {
    expect(
      find('LN-6B98'),
      contains('Loans:/loans/${loans.first.id}?from=loans'),
    );
    expect(
      find('6b98df'),
      contains('Loans:/loans/${loans.first.id}?from=loans'),
    );
  });

  test('payment by amount, reference or receipt number', () {
    final route = 'Payments:/loans/${loans.first.id}?from=loans';
    expect(find('2875'), contains(route));
    expect(find('2,875.00'), contains(route));
    expect(find('5678 9012'), contains(route));
    expect(find('PR-4DD3'), contains(route));
  });

  test('no match', () => expect(find('zzzz'), isEmpty));
}
