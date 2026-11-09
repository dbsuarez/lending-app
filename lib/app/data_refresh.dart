import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/dashboard/live_dashboard_screen.dart';
import '../features/loans/loans_controller.dart';
import '../features/payments/payments_controller.dart';
import '../features/reports/aging_report_provider.dart';
import 'top_bar_actions.dart';

/// After anything that moves money or changes a loan's status, every view
/// derived from loans and payments must reload: the Borrowers "Ongoing" tag,
/// Collections, Dashboard and the aging report all read these providers.
///
/// The caller already reloaded its own list, so it is skipped here.
/// Invalidated lists keep showing their previous data while reloading.
void refreshMoneyViews(Ref ref, {bool loans = true, bool payments = true}) {
  if (loans) ref.invalidate(loansControllerProvider);
  if (payments) ref.invalidate(paymentsControllerProvider);
  ref.invalidate(liveDashboardProvider);
  ref.invalidate(agingReportProvider);
  ref.invalidate(appNoticesProvider);
}

/// The same, from outside a provider (e.g. after a restore in Settings).
void refreshAllMoneyViews(ProviderContainer container) {
  container.invalidate(loansControllerProvider);
  container.invalidate(paymentsControllerProvider);
  container.invalidate(liveDashboardProvider);
  container.invalidate(agingReportProvider);
  container.invalidate(appNoticesProvider);
}
