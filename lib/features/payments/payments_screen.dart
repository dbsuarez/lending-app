import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/formatting.dart';
import '../../core/widgets/app_status_badge.dart';
import '../../core/widgets/clearable_search_field.dart';
import '../../domain/models/models.dart';
import '../loans/loans_controller.dart';
import '../settings/operations_config_provider.dart';
import 'payments_controller.dart';

class PaymentsScreen extends ConsumerStatefulWidget {
  const PaymentsScreen({super.key});

  @override
  ConsumerState<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends ConsumerState<PaymentsScreen> {
  String query = '';
  String statusFilter = 'all';
  DateTimeRange? dateFilter;
  int sortColumnIndex = 0;
  bool sortAscending = false;

  @override
  Widget build(BuildContext context) {
    final payments = ref.watch(paymentsControllerProvider);
    final loans =
        ref.watch(loansControllerProvider).value ?? const <LoanSummary>[];
    final activeLoans = loans
        .where((loan) => loan.status == 'active' && !loan.isPersonal)
        .toList();
    final controller = ref.read(paymentsControllerProvider.notifier);
    final methods =
        ref.watch(operationsConfigProvider).value?.paymentMethods ??
        OperationsConfig.defaults.paymentMethods;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 12,
            children: [
              Text(
                'Payments',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (controller.isLive)
                    IconButton(
                      tooltip: 'Refresh payments',
                      onPressed: payments.isLoading ? null : controller.refresh,
                      icon: const Icon(Icons.refresh),
                    ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: payments.isLoading || activeLoans.isEmpty
                        ? null
                        : () => _record(activeLoans, methods),
                    icon: const Icon(Icons.add_card_outlined),
                    label: const Text('Record Payment'),
                  ),
                ],
              ),
            ],
          ),
          if (activeLoans.isEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Activate a loan before recording a payment.',
              style: TextStyle(fontSize: 12),
            ),
          ],
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: constraints.maxWidth < 440
                      ? constraints.maxWidth
                      : 420,
                  child: ClearableSearchField(
                    onChanged: (value) => setState(() => query = value),
                    hintText: 'Search borrower, method, or reference',
                  ),
                ),
                SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: statusFilter,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: const [
                      DropdownMenuItem(
                        value: 'all',
                        child: Text('All statuses'),
                      ),
                      DropdownMenuItem(
                        value: 'pending',
                        child: Text('Pending'),
                      ),
                      DropdownMenuItem(
                        value: 'verified',
                        child: Text('Verified'),
                      ),
                      DropdownMenuItem(
                        value: 'rejected',
                        child: Text('Rejected'),
                      ),
                      DropdownMenuItem(
                        value: 'reversed',
                        child: Text('Reversed'),
                      ),
                    ],
                    onChanged: (value) => setState(() => statusFilter = value!),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _chooseDateRange,
                  icon: const Icon(Icons.date_range_outlined),
                  label: Text(
                    dateFilter == null
                        ? 'All dates'
                        : '${formatPhilippineDate(dateFilter!.start)} - ${formatPhilippineDate(dateFilter!.end)}',
                  ),
                ),
                if (dateFilter != null)
                  IconButton(
                    tooltip: 'Clear date filter',
                    onPressed: () => setState(() => dateFilter = null),
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: payments.when(
              skipLoadingOnReload: true,
              data: (items) => _buildPayments(
                items
                    .where(
                      (payment) => loans.any(
                        (loan) => loan.id == payment.loanId && !loan.isPersonal,
                      ),
                    )
                    .toList(),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => _PaymentsError(onRetry: controller.refresh),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayments(List<PaymentSummary> allPayments) {
    final normalized = query.trim().toLowerCase();
    final payments = allPayments
        .where(
          (payment) =>
              (statusFilter == 'all' || payment.status == statusFilter) &&
              (dateFilter == null ||
                  (!payment.receivedAt.isBefore(dateFilter!.start) &&
                      payment.receivedAt.isBefore(
                        dateFilter!.end.add(const Duration(days: 1)),
                      ))) &&
              (normalized.isEmpty ||
                  payment.borrowerName.toLowerCase().contains(normalized) ||
                  payment.method.toLowerCase().contains(normalized) ||
                  payment.reference.toLowerCase().contains(normalized)),
        )
        .toList();
    payments.sort((left, right) {
      final comparison = switch (sortColumnIndex) {
        0 => left.receivedAt.compareTo(right.receivedAt),
        1 => left.borrowerName.toLowerCase().compareTo(
          right.borrowerName.toLowerCase(),
        ),
        2 => left.amountCentavos.compareTo(right.amountCentavos),
        3 => left.method.toLowerCase().compareTo(right.method.toLowerCase()),
        4 => left.reference.toLowerCase().compareTo(
          right.reference.toLowerCase(),
        ),
        5 => left.status.compareTo(right.status),
        _ => 0,
      };
      return sortAscending ? comparison : -comparison;
    });
    if (payments.isEmpty) {
      return Center(
        child: Text(
          allPayments.isEmpty
              ? 'No payment records yet.'
              : 'No payments match your search.',
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 760
          ? ListView.separated(
              itemCount: payments.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, index) => _PaymentCard(
                payments[index],
                onVerify: () => _verify(payments[index]),
                onReject: () => _reject(payments[index]),
                onReverse: () => _reverse(payments[index]),
              ),
            )
          : Card(
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                child: DataTable(
                  sortColumnIndex: sortColumnIndex,
                  sortAscending: sortAscending,
                  columns: [
                    DataColumn(label: const Text('Received'), onSort: _sort),
                    DataColumn(label: const Text('Borrower'), onSort: _sort),
                    DataColumn(
                      label: const Text('Amount'),
                      numeric: true,
                      onSort: _sort,
                    ),
                    DataColumn(label: const Text('Method'), onSort: _sort),
                    DataColumn(label: const Text('Reference'), onSort: _sort),
                    DataColumn(label: const Text('Status'), onSort: _sort),
                    const DataColumn(label: Text('Actions')),
                  ],
                  rows: [
                    for (final payment in payments)
                      DataRow(
                        cells: [
                          DataCell(
                            Text(formatPhilippineDateTime(payment.receivedAt)),
                          ),
                          DataCell(Text(payment.borrowerName)),
                          DataCell(Text(formatPeso(payment.amountCentavos))),
                          DataCell(Text(payment.method)),
                          DataCell(
                            Text(
                              payment.reference.isEmpty
                                  ? '—'
                                  : payment.reference,
                            ),
                          ),
                          DataCell(AppStatusBadge(payment.status)),
                          DataCell(_paymentActions(payment)),
                        ],
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  void _sort(int columnIndex, bool ascending) => setState(() {
    sortColumnIndex = columnIndex;
    sortAscending = ascending;
  });

  Future<void> _chooseDateRange() async {
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: dateFilter,
    );
    if (selected != null) setState(() => dateFilter = selected);
  }

  Future<void> _record(
    List<LoanSummary> activeLoans,
    List<String> methods,
  ) async {
    final values = await showDialog<_PaymentValues>(
      context: context,
      builder: (_) => _PaymentDialog(loans: activeLoans, methods: methods),
    );
    if (values == null) return;
    final loan = activeLoans.firstWhere((item) => item.id == values.loanId);
    final saved = await ref
        .read(paymentsControllerProvider.notifier)
        .recordPending(
          loan: loan,
          amountCentavos: values.amountCentavos,
          receivedAt: values.receivedAt,
          method: values.method,
          reference: values.reference,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved
              ? values.method == 'Cash'
                    ? 'Cash payment verified and allocated automatically.'
                    : 'Payment recorded as Pending Verification.'
              : 'Payment could not be recorded. Try again.',
        ),
      ),
    );
  }

  Future<void> _reject(PaymentSummary payment) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _RejectPaymentDialog(),
    );
    if (reason == null) return;
    final rejected = await ref
        .read(paymentsControllerProvider.notifier)
        .reject(payment, reason);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          rejected
              ? 'Payment rejected. The reason was recorded in the audit log.'
              : 'Payment could not be rejected. Try again.',
        ),
      ),
    );
  }

  Widget _paymentActions(PaymentSummary payment) => Wrap(
    spacing: 4,
    children: [
      if (payment.status == 'pending') ...[
        TextButton(
          onPressed: () => _verify(payment),
          child: const Text('Verify'),
        ),
        TextButton(
          onPressed: () => _reject(payment),
          child: const Text('Reject'),
        ),
      ],
      if (payment.status == 'verified')
        TextButton(
          onPressed: () => _reverse(payment),
          child: const Text('Reverse'),
        ),
    ],
  );

  Future<void> _verify(PaymentSummary payment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Verify payment?'),
        content: Text(
          'This will allocate ${formatPeso(payment.amountCentavos)} to the oldest unpaid installments, interest first then principal.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Verify and Allocate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final saved = await ref
        .read(paymentsControllerProvider.notifier)
        .verify(payment);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved
              ? 'Payment verified and allocated.'
              : 'Payment verification failed.',
        ),
      ),
    );
  }

  Future<void> _reverse(PaymentSummary payment) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _ReasonDialog(
        title: 'Reverse verified payment?',
        actionLabel: 'Reverse Payment',
      ),
    );
    if (reason == null) return;
    final saved = await ref
        .read(paymentsControllerProvider.notifier)
        .reverse(payment, reason);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved
              ? 'Payment reversed with an audit record.'
              : 'Payment reversal failed.',
        ),
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard(
    this.payment, {
    required this.onVerify,
    required this.onReject,
    required this.onReverse,
  });
  final PaymentSummary payment;
  final VoidCallback onVerify, onReject, onReverse;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  payment.borrowerName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              AppStatusBadge(payment.status),
            ],
          ),
          const SizedBox(height: 8),
          Text(formatPhilippineDateTime(payment.receivedAt)),
          Text(
            '${payment.method} · ${payment.reference.isEmpty ? 'No reference' : payment.reference}',
          ),
          const SizedBox(height: 8),
          Text(
            formatPeso(payment.amountCentavos),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          if (payment.unappliedCentavos > 0)
            Text(
              '${formatPeso(payment.unappliedCentavos)} remains as unapplied credit',
              textAlign: TextAlign.right,
            ),
          if (payment.status == 'pending') ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                children: [
                  TextButton(onPressed: onVerify, child: const Text('Verify')),
                  TextButton(onPressed: onReject, child: const Text('Reject')),
                ],
              ),
            ),
          ],
          if (payment.status == 'verified')
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onReverse,
                child: const Text('Reverse Payment'),
              ),
            ),
        ],
      ),
    ),
  );
}

class _PaymentValues {
  const _PaymentValues({
    required this.loanId,
    required this.amountCentavos,
    required this.receivedAt,
    required this.method,
    required this.reference,
  });
  final String loanId, method, reference;
  final int amountCentavos;
  final DateTime receivedAt;
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.loans, required this.methods});
  final List<LoanSummary> loans;
  final List<String> methods;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final key = GlobalKey<FormState>();
  final amount = TextEditingController();
  final reference = TextEditingController();
  late String loanId = widget.loans.first.id;
  late String method = widget.methods.first;
  final DateTime receivedAt = DateTime.now();

  @override
  void dispose() {
    amount.dispose();
    reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Record payment'),
    content: SizedBox(
      width: 520,
      child: Form(
        key: key,
        child: SingleChildScrollView(
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                initialValue: loanId,
                decoration: const InputDecoration(labelText: 'Active loan'),
                items: [
                  for (final loan in widget.loans)
                    DropdownMenuItem(
                      value: loan.id,
                      child: Text(loan.borrowerName),
                    ),
                ],
                onChanged: (value) => setState(() => loanId = value!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textAlign: TextAlign.right,
                decoration: const InputDecoration(
                  labelText: 'Amount received',
                  prefixText: '₱ ',
                ),
                validator: (value) => (double.tryParse(value ?? '') ?? 0) > 0
                    ? null
                    : 'Enter a positive amount',
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: method,
                decoration: const InputDecoration(labelText: 'Method'),
                items: [
                  for (final item in widget.methods)
                    DropdownMenuItem(value: item, child: Text(item)),
                ],
                onChanged: (value) => setState(() => method = value!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: reference,
                decoration: const InputDecoration(
                  labelText: 'Reference (optional)',
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule),
                title: const Text('Received at'),
                subtitle: Text(formatPhilippineDateTime(receivedAt)),
              ),
              const Text(
                'This payment will remain Pending Verification and will not reduce the balance yet.',
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!key.currentState!.validate()) return;
          Navigator.pop(
            context,
            _PaymentValues(
              loanId: loanId,
              amountCentavos: (double.parse(amount.text) * 100).round(),
              receivedAt: receivedAt,
              method: method,
              reference: reference.text.trim(),
            ),
          );
        },
        child: const Text('Record Pending Payment'),
      ),
    ],
  );
}

class _PaymentsError extends StatelessWidget {
  const _PaymentsError({required this.onRetry});
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Payments could not be loaded.'),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Try Again'),
        ),
      ],
    ),
  );
}

class _RejectPaymentDialog extends StatefulWidget {
  const _RejectPaymentDialog();

  @override
  State<_RejectPaymentDialog> createState() => _RejectPaymentDialogState();
}

class _RejectPaymentDialogState extends State<_RejectPaymentDialog> {
  final key = GlobalKey<FormState>();
  final reason = TextEditingController();

  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Reject payment?'),
    content: Form(
      key: key,
      child: TextFormField(
        controller: reason,
        autofocus: true,
        maxLines: 3,
        decoration: const InputDecoration(labelText: 'Reason'),
        validator: (value) =>
            (value?.trim().length ?? 0) >= 3 ? null : 'Enter a clear reason',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (key.currentState!.validate()) {
            Navigator.pop(context, reason.text.trim());
          }
        },
        child: const Text('Reject Payment'),
      ),
    ],
  );
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title, required this.actionLabel});
  final String title, actionLabel;
  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final key = GlobalKey<FormState>();
  final reason = TextEditingController();
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Form(
      key: key,
      child: TextFormField(
        controller: reason,
        autofocus: true,
        maxLines: 3,
        decoration: const InputDecoration(labelText: 'Required reason'),
        validator: (value) =>
            (value?.trim().length ?? 0) >= 3 ? null : 'Enter a clear reason',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (key.currentState!.validate()) {
            Navigator.pop(context, reason.text.trim());
          }
        },
        child: Text(widget.actionLabel),
      ),
    ],
  );
}
