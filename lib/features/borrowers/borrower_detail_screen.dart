import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_saver/file_saver.dart';
import 'dart:convert';
import 'dart:typed_data';
import '../../core/formatting.dart';
import '../../core/widgets/app_status_badge.dart';
import '../../domain/models/models.dart';
import '../loans/loans_controller.dart';
import '../payments/payments_controller.dart';
import 'borrowers_controller.dart';

class BorrowerDetailScreen extends ConsumerWidget {
  const BorrowerDetailScreen({super.key, required this.borrowerId});
  final String borrowerId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final borrowerState = ref.watch(borrowersControllerProvider);
    if (borrowerState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final matches =
        borrowerState.value?.where((b) => b.id == borrowerId).toList() ??
        const <Borrower>[];
    if (matches.isEmpty) {
      return const Center(child: Text('Borrower was not found.'));
    }
    final borrower = matches.first;
    final loans =
        (ref.watch(loansControllerProvider).value ?? const <LoanSummary>[])
            .where((l) => l.borrowerId == borrower.id)
            .toList();
    final loanIds = loans.map((l) => l.id).toSet();
    final payments =
        (ref.watch(paymentsControllerProvider).value ??
                const <PaymentSummary>[])
            .where((p) => loanIds.contains(p.loanId))
            .toList();
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => context.go('/borrowers'),
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Back to borrowers',
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  child: Text(
                    '${borrower.firstName[0]}${borrower.lastName[0]}',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    borrower.displayName,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      _exportBorrower(context, borrower, loans, payments),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Export Data'),
                ),
              ],
            ),
          ),
          const TabBar(
            tabs: [
              Tab(text: 'Profile'),
              Tab(text: 'Loans'),
              Tab(text: 'Payments'),
              Tab(text: 'Activity'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Card(
                      child: Column(
                        children: [
                          _field(Icons.phone_outlined, 'Phone', borrower.phone),
                          const Divider(height: 1),
                          _field(Icons.email_outlined, 'Email', borrower.email),
                          const Divider(height: 1),
                          _field(
                            Icons.location_on_outlined,
                            'Address',
                            borrower.address,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                _loans(context, loans),
                _payments(payments),
                _activity(loans, payments),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _field(IconData icon, String label, String value) => ListTile(
    leading: Icon(icon),
    title: Text(label),
    subtitle: Text(value.isEmpty ? 'Not provided' : value),
  );
  static Widget _loans(BuildContext context, List<LoanSummary> loans) =>
      loans.isEmpty
      ? const Center(child: Text('No loans for this borrower.'))
      : ListView.separated(
          padding: const EdgeInsets.all(24),
          itemCount: loans.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, i) => Card(
            child: ListTile(
              onTap: () => context.go(
                '/loans/${loans[i].id}?from=borrower&borrowerId=${loans[i].borrowerId}',
              ),
              title: Text('LN-${loans[i].id.substring(0, 8).toUpperCase()}'),
              subtitle: Align(
                alignment: Alignment.centerLeft,
                child: AppStatusBadge(loans[i].status),
              ),
              trailing: Text(
                formatPeso(loans[i].totalCentavos),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        );
  static Widget _payments(List<PaymentSummary> payments) => payments.isEmpty
      ? const Center(child: Text('No payment records for this borrower.'))
      : ListView.separated(
          padding: const EdgeInsets.all(24),
          itemCount: payments.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, i) => Card(
            child: ListTile(
              title: Text(formatPhilippineDateTime(payments[i].receivedAt)),
              subtitle: Text('${payments[i].method} · ${payments[i].status}'),
              trailing: Text(
                formatPeso(payments[i].amountCentavos),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        );

  static Widget _activity(
    List<LoanSummary> loans,
    List<PaymentSummary> payments,
  ) {
    final events = <({DateTime at, IconData icon, String title, String detail})>[
      for (final loan in loans)
        (
          at: loan.createdAt,
          icon: Icons.request_quote_outlined,
          title: 'Loan ${loan.status}',
          detail:
              'LN-${loan.id.substring(0, 8).toUpperCase()} · ${formatPeso(loan.totalCentavos)}',
        ),
      for (final payment in payments)
        (
          at: payment.receivedAt,
          icon: Icons.payments_outlined,
          title: 'Payment ${payment.status}',
          detail: '${payment.method} · ${formatPeso(payment.amountCentavos)}',
        ),
    ]..sort((a, b) => b.at.compareTo(a.at));
    if (events.isEmpty) {
      return const Center(child: Text('No borrower activity yet.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: events.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, index) {
        final event = events[index];
        return ListTile(
          leading: Icon(event.icon),
          title: Text(event.title),
          subtitle: Text(event.detail),
          trailing: Text(formatPhilippineDate(event.at)),
        );
      },
    );
  }

  static Future<void> _exportBorrower(
    BuildContext context,
    Borrower borrower,
    List<LoanSummary> loans,
    List<PaymentSummary> payments,
  ) async {
    final data = <String, dynamic>{
      'format': 'lending-manager-borrower-export-v1',
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'borrower': {
        'id': borrower.id,
        'first_name': borrower.firstName,
        'last_name': borrower.lastName,
        'phone': borrower.phone,
        'email': borrower.email,
        'address': borrower.address,
      },
      'loans': [
        for (final loan in loans)
          {
            'id': loan.id,
            'status': loan.status,
            'principal_centavos': loan.principalCentavos,
            'total_centavos': loan.totalCentavos,
            'created_at': loan.createdAt.toUtc().toIso8601String(),
          },
      ],
      'payments': [
        for (final payment in payments)
          {
            'id': payment.id,
            'loan_id': payment.loanId,
            'amount_centavos': payment.amountCentavos,
            'received_at': payment.receivedAt.toUtc().toIso8601String(),
            'method': payment.method,
            'reference': payment.reference,
            'status': payment.status,
          },
      ],
    };
    await FileSaver.instance.saveFile(
      name: 'borrower-${borrower.id.substring(0, 8)}-data',
      bytes: Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(data)),
      ),
      fileExtension: 'json',
      mimeType: MimeType.json,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Borrower data export created.')),
      );
    }
  }
}
