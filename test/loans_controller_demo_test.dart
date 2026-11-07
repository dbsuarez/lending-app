import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lending_manager/domain/models/models.dart';
import 'package:lending_manager/domain/services/loan_calculator.dart';
import 'package:lending_manager/features/loans/loans_controller.dart';

void main() {
  test('demo loan drafts survive until the loans list is watched', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // The create form only reads the notifier, so the provider is created
    // (and its async build starts) in the same call as createDraft.
    final quote = const LoanCalculator().calculate(
      principalCentavos: 2000000,
      monthlyRateBasisPoints: 600,
      termMonths: 5,
      firstDueDate: DateTime(2026, 11, 15),
      paydayPattern: const [15, 30],
    );
    final saved = await container
        .read(loansControllerProvider.notifier)
        .createDraft(
          borrower: const Borrower(
            id: 'b1',
            organizationId: 'demo',
            firstName: 'Maricar',
            lastName: 'Origino',
          ),
          quote: quote,
          firstDueDate: DateTime(2026, 11, 15),
          paydayPattern: const [15, 30],
        );
    expect(saved, isNotNull);

    // Then the Loans screen starts watching the list.
    final sub = container.listen(loansControllerProvider, (_, _) {});
    addTearDown(sub.close);
    final loans = await container.read(loansControllerProvider.future);
    expect(loans, hasLength(1));
    expect(loans.single.status, 'draft');
  });
}
