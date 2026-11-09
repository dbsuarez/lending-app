import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_saver/file_saver.dart';
import 'dart:convert';
import 'dart:typed_data';
import '../../core/export_file.dart';
import '../../core/widgets/info_tip.dart';
import '../../core/undo/undo_controller.dart';
import '../../core/formatting.dart';
import '../../core/widgets/metric_grid.dart';
import '../../core/widgets/window_title.dart';
import 'package:go_router/go_router.dart';
import '../../domain/models/models.dart';
import '../loans/loans_controller.dart';
import '../payments/payments_controller.dart';
import 'aging_report_provider.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loans = ref.watch(loansControllerProvider);
    final payments = ref.watch(paymentsControllerProvider);
    final aging = ref.watch(agingReportProvider);
    if (loans.isLoading || payments.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (loans.hasError || payments.hasError) {
      return const Center(child: Text('Reports could not be loaded.'));
    }
    final loanItems = loans.value ?? const [];
    final businessLoans = loanItems.where((loan) => !loan.isPersonal).toList();
    final businessLoanIds = businessLoans.map((loan) => loan.id).toSet();
    final paymentItems = (payments.value ?? const [])
        .where((payment) => businessLoanIds.contains(payment.loanId))
        .toList();
    final active = businessLoans
        .where((loan) => loan.status == 'active')
        .toList();
    final principal = active.fold<int>(
      0,
      (sum, loan) => sum + loan.principalCentavos,
    );
    final contractual = active.fold<int>(
      0,
      (sum, loan) => sum + loan.totalCentavos,
    );
    final pending = paymentItems
        .where((p) => p.status == 'pending')
        .fold<int>(0, (sum, p) => sum + p.amountCentavos);
    final verified = paymentItems
        .where((p) => p.status == 'verified')
        .fold<int>(0, (sum, p) => sum + p.amountCentavos);
    final unapplied = paymentItems
        .where((p) => p.status == 'verified' && p.unappliedCentavos > 0)
        .toList();
    final byMethod = <String, ({int count, int amount})>{};
    for (final payment in paymentItems) {
      final old = byMethod[payment.method] ?? (count: 0, amount: 0);
      byMethod[payment.method] = (
        count: old.count + 1,
        amount: old.amount + payment.amountCentavos,
      );
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Reports',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _exportCsv(
                context,
                loanItems.cast<LoanSummary>(),
                paymentItems.cast<PaymentSummary>(),
              ),
              icon: const Icon(Icons.download_outlined),
              label: const Text('Export CSV'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        MetricGrid(
          children: [
            MetricCard('Active loans', '${active.length}'),
            MetricCard(
              'Money lent out',
              formatPeso(principal),
              info: 'disburse',
            ),
            MetricCard(
              'Contractual total',
              formatPeso(contractual),
              info: 'contractual_total',
            ),
            MetricCard('Verified collections', formatPeso(verified)),
            MetricCard(
              'Pending verification',
              formatPeso(pending),
              info: 'pending_verification',
            ),
          ],
        ),
        const SizedBox(height: 20),
        TitleWithInfo(
          'Outstanding balance aging',
          'aging',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        aging.when(
          data: (report) => report == null
              ? const Card(
                  child: ListTile(
                    title: Text(
                      'Aging is available when connected to Supabase.',
                    ),
                  ),
                )
              : MetricGrid(
                  children: [
                    MetricCard('Not yet due', formatPeso(report.current)),
                    MetricCard('1-30 days', formatPeso(report.days1to30)),
                    MetricCard('31-60 days', formatPeso(report.days31to60)),
                    MetricCard('61-90 days', formatPeso(report.days61to90)),
                    MetricCard('Over 90 days', formatPeso(report.days90Plus)),
                    MetricCard(
                      'Total outstanding',
                      formatPeso(report.total),
                      info: 'still_owed',
                    ),
                  ],
                ),
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => const Card(
            child: ListTile(title: Text('Aging report could not be loaded.')),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Payments by method',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Card(
          child: byMethod.isEmpty
              ? const ListTile(title: Text('No payments recorded.'))
              : Column(
                  children: [
                    for (final entry in byMethod.entries)
                      ListTile(
                        title: Text(entry.key),
                        subtitle: Text(
                          '${entry.value.count} payment${entry.value.count == 1 ? '' : 's'}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              formatPeso(entry.value.amount),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: () => _showMethod(
                          context,
                          entry.key,
                          paymentItems
                              .cast<PaymentSummary>()
                              .where((p) => p.method == entry.key)
                              .toList(),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 20),
        Text('Payment checks', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Card(
          child: unapplied.isEmpty
              ? const ListTile(
                  leading: Icon(Icons.check_circle_outline),
                  title: Text('No unapplied payment credits'),
                  subtitle: Text(
                    'All confirmed payments are fully applied to installments.',
                  ),
                )
              : Column(
                  children: [
                    for (final payment in unapplied)
                      ListTile(
                        leading: const Icon(Icons.warning_amber_outlined),
                        title: Text(payment.borrowerName),
                        subtitle: Text(
                          '${payment.reference.isEmpty ? 'No reference' : payment.reference} · Reverse with a required reason if this credit was entered incorrectly.',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              formatPeso(payment.unappliedCentavos),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: () =>
                            context.go('/loans/${payment.loanId}?from=loans'),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  /// Details of one payment method: totals by status and its payments.
  void _showMethod(
    BuildContext context,
    String method,
    List<PaymentSummary> payments,
  ) {
    final sorted = [...payments]
      ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    int sum(Iterable<PaymentSummary> list) =>
        list.fold(0, (s, p) => s + p.amountCentavos);
    Iterable<PaymentSummary> withStatus(String s) =>
        sorted.where((p) => p.status == s);
    final now = DateTime.now();
    final thisMonth = withStatus('verified').where(
      (p) =>
          p.receivedAt.toLocal().year == now.year &&
          p.receivedAt.toLocal().month == now.month,
    );
    final rows = <(String, Iterable<PaymentSummary>)>[
      ('Verified', withStatus('verified')),
      ('Pending verification', withStatus('pending')),
      ('Reversed', withStatus('reversed')),
      ('Rejected', withStatus('rejected')),
    ].where((r) => r.$2.isNotEmpty);
    String status(String s) =>
        s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          scrollable: true,
          title: WindowTitle(Text(method)),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (label, list) in rows)
                  _detailLine('$label (${list.length})', formatPeso(sum(list))),
                _detailLine(
                  'Verified this month (${thisMonth.length})',
                  formatPeso(sum(thisMonth)),
                ),
                const Divider(height: 24),
                Text('Payments', style: theme.textTheme.labelLarge),
                for (final p in sorted.take(30))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${formatPeso(p.amountCentavos)} · ${p.borrowerName}',
                    ),
                    subtitle: Text(
                      '${formatPhilippineDateTime(p.receivedAt)} · ${status(p.status)}'
                      '${p.reference.isEmpty ? '' : ' · ${p.reference}'}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.pop(dialogContext);
                      context.go('/loans/${p.loanId}?from=loans');
                    },
                  ),
                if (sorted.length > 30)
                  Text(
                    'Showing the latest 30 of ${sorted.length}. The Payments '
                    'page lists them all.',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  static Widget _detailLine(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );

  Future<void> _exportCsv(
    BuildContext context,
    List<LoanSummary> loans,
    List<PaymentSummary> payments,
  ) async {
    final rows = <List<Object?>>[
      [
        'record_type',
        'reference',
        'borrower',
        'date',
        'status',
        'method',
        'amount_php',
      ],
      for (final loan in loans)
        [
          'loan',
          'LN-${loan.id.substring(0, 8).toUpperCase()}',
          loan.borrowerName,
          formatPhilippineDate(loan.createdAt),
          loan.status,
          '',
          (loan.totalCentavos / 100).toStringAsFixed(2),
        ],
      for (final payment in payments)
        [
          'payment',
          payment.reference,
          payment.borrowerName,
          payment.receivedAt.toIso8601String(),
          payment.status,
          payment.method,
          (payment.amountCentavos / 100).toStringAsFixed(2),
        ],
    ];
    final csv = rows.map((row) => row.map(_csvCell).join(',')).join('\r\n');
    final where = await saveExport(
      name:
          'lending-manager-export-${DateTime.now().toIso8601String().substring(0, 10)}',
      bytes: Uint8List.fromList(utf8.encode(csv)),
      extension: 'csv',
      mimeType: MimeType.csv,
    );
    if (context.mounted && where != null) {
      undoOf(context).notify('CSV export saved to $where.');
    }
  }

  String _csvCell(Object? value) {
    final text = value?.toString() ?? '';
    return '"${text.replaceAll('"', '""')}"';
  }
}

/// Lays metric cards out in equal columns: two on phones, up to six wide.
