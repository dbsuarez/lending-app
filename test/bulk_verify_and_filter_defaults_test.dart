import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lending_manager/core/preferences/filter_defaults.dart';
import 'package:lending_manager/domain/models/models.dart';
import 'package:lending_manager/features/payments/payments_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

LoanSummary _loan() => LoanSummary(
  id: 'loan-1',
  organizationId: 'o',
  borrowerId: 'b',
  borrowerName: 'Florendo, Kristoper',
  principalCentavos: 3000000,
  totalCentavos: 3540000,
  monthlyRateBasisPoints: 300,
  termMonths: 6,
  status: 'active',
  createdAt: DateTime(2025, 7, 1),
);

void main() {
  test(
    'bulk verify confirms the chosen pending payments; undo restores all',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final payments = container.read(paymentsControllerProvider.notifier);
      for (final day in [5, 20, 21]) {
        await payments.recordPending(
          loan: _loan(),
          amountCentavos: 295000,
          receivedAt: DateTime(2025, 8, day),
          method: 'GCash',
          reference: 'REF-$day',
        );
      }
      final all = container.read(paymentsControllerProvider).value!;
      final chosen = all.where((p) => p.reference != 'REF-21').toList();

      final verified = await payments.verifyMany(chosen);
      expect(verified, hasLength(2));
      var now = container.read(paymentsControllerProvider).value!;
      expect(
        {for (final p in now) p.reference: p.status},
        {'REF-5': 'verified', 'REF-20': 'verified', 'REF-21': 'pending'},
      );
      // Oldest first, so money is applied in the order it arrived.
      expect(
        verified.map((id) => now.firstWhere((p) => p.id == id).reference),
        ['REF-5', 'REF-20'],
      );

      expect(await payments.undoVerifications(verified), isTrue);
      now = container.read(paymentsControllerProvider).value!;
      expect(now.every((p) => p.status == 'pending'), isTrue);
    },
  );

  test('filter defaults are remembered per list', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    final defaults = container.read(filterDefaultsProvider);
    expect(defaults.get('loans.status', 'active'), 'active');
    await defaults.set('loans.status', 'fully_paid');
    expect(defaults.get('loans.status', 'active'), 'fully_paid');
    expect(defaults.get('payments.status', 'all'), 'all');
    // Survives an app restart (new container, same device storage).
    final again = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(again.dispose);
    expect(
      again.read(filterDefaultsProvider).get('loans.status', 'active'),
      'fully_paid',
    );
  });
}
