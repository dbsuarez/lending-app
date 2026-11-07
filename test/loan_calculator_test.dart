import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lending_manager/core/formatting.dart';
import 'package:lending_manager/data/repositories/demo_repository.dart';
import 'package:lending_manager/domain/services/loan_calculator.dart';
import 'package:lending_manager/features/documents/loan_schedule_pdf.dart';
import 'package:lending_manager/features/loans/loans_controller.dart';
import 'package:lending_manager/features/payments/payments_controller.dart';

void main() {
  test('shared date formatting follows UI standards', () {
    expect(formatPhilippineDate(DateTime(2026, 11, 6)), '2026-11-06');
    expect(
      formatPhilippineDateTime(DateTime(2026, 11, 6, 9, 5)),
      '2026-11-06 09:05',
    );
  });

  const c = LoanCalculator();
  test('local loan draft is retained by the loans controller', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(loansControllerProvider.future);
    final quote = c.calculate(
      principalCentavos: 2000000,
      monthlyRateBasisPoints: 600,
      termMonths: 5,
      firstDueDate: DateTime(2027, 1, 15),
      paydayPattern: [15, 30],
    );

    final saved = await container
        .read(loansControllerProvider.notifier)
        .createDraft(
          borrower: container.read(borrowersProvider).first,
          quote: quote,
          firstDueDate: DateTime(2027, 1, 15),
          paydayPattern: const [15, 30],
        );

    expect(saved, isTrue);
    final loans = container.read(loansControllerProvider).value;
    expect(loans, hasLength(1));
    expect(loans!.single.totalCentavos, 2600000);
    expect(loans.single.status, 'draft');

    final detail = await container
        .read(loansControllerProvider.notifier)
        .fetchDetail(loans.single.id);
    expect(detail.installments, hasLength(10));
    final pdf = await LoanSchedulePdf.build(
      detail,
      generatedOn: DateTime(2026, 11, 7),
    );
    expect(pdf.length, greaterThan(5000));
    expect(String.fromCharCodes(pdf.take(4)), '%PDF');

    final activated = await container
        .read(loansControllerProvider.notifier)
        .activate(
          loanId: loans.single.id,
          disbursedOn: DateTime(2026, 11, 7),
          method: 'GCash',
          reference: '',
        );
    expect(activated, isTrue);
    expect(
      container.read(loansControllerProvider).value!.single.status,
      'active',
    );

    await container.read(paymentsControllerProvider.future);
    final paymentSaved = await container
        .read(paymentsControllerProvider.notifier)
        .recordPending(
          loan: container.read(loansControllerProvider).value!.single,
          amountCentavos: 260000,
          receivedAt: DateTime(2026, 11, 7, 10, 30),
          method: 'GCash',
          reference: 'TEST-001',
        );
    expect(paymentSaved, isTrue);
    final payments = container.read(paymentsControllerProvider).value!;
    expect(payments, hasLength(1));
    expect(payments.single.status, 'pending');
    final rejected = await container
        .read(paymentsControllerProvider.notifier)
        .reject(payments.single, 'Reference could not be verified');
    expect(rejected, isTrue);
    expect(
      container.read(paymentsControllerProvider).value!.single.status,
      'rejected',
    );
    final cashSaved = await container
        .read(paymentsControllerProvider.notifier)
        .recordPending(
          loan: container.read(loansControllerProvider).value!.single,
          amountCentavos: 260000,
          receivedAt: DateTime(2026, 11, 7, 11),
          method: 'Cash',
          reference: 'CASH-001',
        );
    expect(cashSaved, isTrue);
    expect(
      container.read(paymentsControllerProvider).value!.first.status,
      'verified',
    );
  });

  test('reference loan is exact', () {
    final q = c.calculate(
      principalCentavos: 2000000,
      monthlyRateBasisPoints: 600,
      termMonths: 5,
      firstDueDate: DateTime(2027, 1, 15),
      paydayPattern: [15, 30],
    );
    expect(q.interestCentavos, 600000);
    expect(q.totalCentavos, 2600000);
    expect(q.installments.length, 10);
    expect(q.installments.every((x) => x.amountCentavos == 260000), isTrue);
  });
  test('February clamps in common and leap years', () {
    final common = c.calculate(
      principalCentavos: 100000,
      monthlyRateBasisPoints: 0,
      termMonths: 1,
      firstDueDate: DateTime(2027, 2, 15),
      paydayPattern: [15, 30],
    );
    final leap = c.calculate(
      principalCentavos: 100000,
      monthlyRateBasisPoints: 0,
      termMonths: 1,
      firstDueDate: DateTime(2028, 2, 15),
      paydayPattern: [15, 30],
    );
    expect(common.installments.last.dueDate, DateTime(2027, 2, 28));
    expect(leap.installments.last.dueDate, DateTime(2028, 2, 29));
  });
  test('Maricar schedule fixture uses 15th and month end', () {
    final quote = c.calculate(
      principalCentavos: 2000000,
      monthlyRateBasisPoints: 600,
      termMonths: 5,
      firstDueDate: DateTime(2026, 11, 15),
      paydayPattern: [15, 31],
    );
    expect(quote.interestCentavos, 600000);
    expect(quote.totalCentavos, 2600000);
    expect(
      quote.installments.map((item) => item.amountCentavos),
      everyElement(260000),
    );
    expect(quote.installments.map((item) => item.dueDate), [
      DateTime(2026, 11, 15),
      DateTime(2026, 11, 30),
      DateTime(2026, 12, 15),
      DateTime(2026, 12, 31),
      DateTime(2027, 1, 15),
      DateTime(2027, 1, 31),
      DateTime(2027, 2, 15),
      DateTime(2027, 2, 28),
      DateTime(2027, 3, 15),
      DateTime(2027, 3, 31),
    ]);
  });
  test('invalid amounts are rejected', () {
    expect(
      () => c.calculate(
        principalCentavos: 0,
        monthlyRateBasisPoints: 600,
        termMonths: 5,
        firstDueDate: DateTime(2027),
        paydayPattern: [15, 30],
      ),
      throwsArgumentError,
    );
  });
}
