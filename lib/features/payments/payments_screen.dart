import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../documents/loan_print_menu.dart';
import '../../core/widgets/table_columns.dart';
import '../../core/preferences/filter_defaults.dart';
import '../../core/widgets/info_tip.dart';
import '../../core/formatting.dart';
import '../../core/undo/undo_controller.dart';
import '../../core/widgets/responsive_card_list.dart';
import '../../core/widgets/app_status_badge.dart';
import '../../core/widgets/clearable_search_field.dart';
import '../../domain/models/models.dart';
import '../loans/loans_controller.dart';
import '../settings/operations_config_provider.dart';
import 'payment_edit_dialog.dart';
import 'payments_controller.dart';

class PaymentsScreen extends ConsumerStatefulWidget {
  const PaymentsScreen({super.key});

  @override
  ConsumerState<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends ConsumerState<PaymentsScreen> {
  String query = '';
  late String statusFilter = ref
      .read(filterDefaultsProvider)
      .get('payments.status', 'all');
  DateTimeRange? dateFilter;

  /// Pending payments ticked for bulk Verify.
  final Set<String> selected = {};
  int sortColumnIndex = 0;
  bool sortAscending = false;
  int page = 0;
  int pageSize = 20;

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
                    label: const Text('Record Payment…'),
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
                  child: DefaultableFilterDropdown(
                    listKey: 'payments.status',
                    listName: 'Payments',
                    label: 'Status',
                    value: statusFilter,
                    fallback: 'all',
                    options: const [
                      ('all', 'All statuses'),
                      ('pending', 'Pending'),
                      ('verified', 'Verified'),
                      ('rejected', 'Rejected'),
                      ('reversed', 'Reversed'),
                    ],
                    onChanged: (value) => setState(() => statusFilter = value),
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
    // Only pending payments that are visible right now can be bulk-verified,
    // so nothing hidden by search or filters is verified by accident.
    final pageCount = (payments.length / pageSize).ceil();
    if (page >= pageCount) page = pageCount - 1;
    if (page < 0) page = 0;
    final start = page * pageSize;
    final pagePayments = payments.skip(start).take(pageSize).toList();
    final pending = pagePayments.where((p) => p.status == 'pending').toList();
    final chosen = pending.where((p) => selected.contains(p.id)).toList();
    void toggle(PaymentSummary payment, bool on) => setState(
      () => on ? selected.add(payment.id) : selected.remove(payment.id),
    );
    final list = LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 760
          ? ResponsiveCardList(
              itemCount: pagePayments.length,
              itemBuilder: (_, index) => _PaymentCard(
                pagePayments[index],
                selected: pagePayments[index].status == 'pending'
                    ? selected.contains(pagePayments[index].id)
                    : null,
                onSelected: (on) => toggle(pagePayments[index], on),
                onVerify: () => _verify(pagePayments[index]),
                onReject: () => _reject(pagePayments[index]),
                onReverse: () => _reverse(pagePayments[index]),
                onEdit: () => _edit(pagePayments[index]),
              ),
            )
          : ColumnToggle(
              tableId: 'payments',
              labels: const [
                'Received',
                'Borrower',
                'Amount',
                'Method',
                'Reference',
                'Status',
                'Actions',
              ],
              builder: (view) => Card(
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  child: DataTable(
                    // Checkboxes only when there is something to bulk-verify.
                    showCheckboxColumn: pending.isNotEmpty,
                    onSelectAll: (on) => setState(() {
                      for (final p in pending) {
                        on == true ? selected.add(p.id) : selected.remove(p.id);
                      }
                    }),
                    sortColumnIndex: view.sortIndex(sortColumnIndex),
                    sortAscending: sortAscending,
                    columns: view.columns([
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
                    ]),
                    rows: [
                      for (final payment in pagePayments)
                        DataRow(
                          selected: selected.contains(payment.id),
                          onSelectChanged: payment.status == 'pending'
                              ? (on) => toggle(payment, on ?? false)
                              : null,
                          cells: view.cells([
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    formatPhilippineDateTime(
                                      payment.receivedAt,
                                    ),
                                  ),
                                  LateReasonMarker(payment.lateReason),
                                ],
                              ),
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
                          ]),
                        ),
                    ],
                  ),
                ),
              ),
            ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (chosen.isNotEmpty)
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 4,
                children: [
                  Text(
                    '${chosen.length} selected · '
                    '${formatPeso(chosen.fold(0, (sum, p) => sum + p.amountCentavos))}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => setState(selected.clear),
                        child: const Text('Clear'),
                      ),
                      FilledButton.icon(
                        onPressed: () => _verifySelected(chosen),
                        icon: const Icon(Icons.done_all),
                        label: const Text('Verify selected…'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        Expanded(child: list),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          runSpacing: 4,
          children: [
            Text('${start + 1}–${start + pagePayments.length} of ${payments.length}'),
            const SizedBox(width: 12),
            Tooltip(
              message: 'Rows per page',
              child: DropdownButton<int>(
                value: pageSize,
                items: const [10, 20, 50].map((size) => DropdownMenuItem(value: size, child: Text('$size rows'))).toList(),
                onChanged: (size) => setState(() { pageSize = size!; page = 0; selected.clear(); }),
              ),
            ),
            IconButton(tooltip: 'Previous page', onPressed: page == 0 ? null : () => setState(() { page--; selected.clear(); }), icon: const Icon(Icons.chevron_left)),
            Text('${page + 1} / $pageCount'),
            IconButton(tooltip: 'Next page', onPressed: page + 1 >= pageCount ? null : () => setState(() { page++; selected.clear(); }), icon: const Icon(Icons.chevron_right)),
          ],
        ),
      ],
    );
  }

  Future<void> _verifySelected(List<PaymentSummary> chosen) async {
    final total = chosen.fold(0, (sum, p) => sum + p.amountCentavos);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: TitleWithInfo('Verify ${chosen.length} payments?', 'verify'),
        content: Text(
          'This confirms ${formatPeso(total)} arrived, in ${chosen.length} '
          'payments. Each is applied to the oldest unpaid installments '
          '(interest first, then principal), oldest payment first. You can '
          'undo this right after.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm Received'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final payments = ref.read(paymentsControllerProvider.notifier);
    final verified = await payments.verifyMany(chosen);
    if (!mounted) return;
    setState(selected.clear);
    final failed = chosen.length - verified.length;
    if (verified.isEmpty) {
      _undo.record(
        'No payments could be verified. Check your access and try again.',
      );
      return;
    }
    _undo.offer(
      '${verified.length} payments confirmed and applied'
      '${failed > 0 ? '; $failed could not be verified' : ''}.',
      () => payments.undoVerifications(verified),
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
      builder: (_) => _PaymentDialog(
        loans: activeLoans,
        methods: methods,
        loadLoan: ref.read(loansControllerProvider.notifier).fetchDetail,
      ),
    );
    if (values == null) return;
    final loan = activeLoans.firstWhere((item) => item.id == values.loanId);
    final payments = ref.read(paymentsControllerProvider.notifier);
    final paymentId = await payments.recordPending(
      loan: loan,
      amountCentavos: values.amountCentavos,
      receivedAt: values.receivedAt,
      method: values.method,
      reference: values.reference,
      lateReason: values.lateReason,
    );
    if (!mounted) return;
    if (paymentId != null) {
      _undo.offer(
        values.method == 'Cash'
            ? 'Cash payment recorded and applied to the balance.'
            : 'Payment recorded as Pending Verification.',
        () => payments.undoRecord(paymentId),
      );
    } else {
      _undo.record('Payment could not be recorded. Try again.');
    }
  }

  UndoController get _undo => ref.read(undoControllerProvider.notifier);

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
    _undo.record(
      rejected
          ? 'Payment rejected. The reason was recorded in the audit log.'
          : 'Payment could not be rejected. Try again.',
    );
  }

  /// Table actions as icons; the tooltip (hover, or long-press on a phone)
  /// names each one. All of them open a window first.
  Widget _paymentActions(PaymentSummary payment) {
    final scheme = Theme.of(context).colorScheme;
    Widget action(
      String tooltip,
      IconData icon,
      VoidCallback onPressed, {
      Color? color,
    }) => IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      color: color,
      onPressed: onPressed,
      icon: Icon(icon),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (payment.status == 'pending') ...[
          action(
            'Verify…',
            Icons.check_circle_outline,
            () => _verify(payment),
            color: scheme.primary,
          ),
          action(
            'Reject…',
            Icons.block,
            () => _reject(payment),
            color: scheme.error,
          ),
        ],
        if (payment.status == 'verified') ...[
          action(
            'Receipt…',
            Icons.receipt_outlined,
            () => printFromContext(
              context,
              (c) => printPaymentReceipt(c, payment),
            ),
          ),
          action(
            'Reverse…',
            Icons.undo,
            () => _reverse(payment),
            color: scheme.error,
          ),
        ],
        if (payment.status == 'pending' || payment.status == 'verified')
          action('Edit…', Icons.edit_outlined, () => _edit(payment)),
      ],
    );
  }

  /// Fix when it was received, the method or reference (not the amount).
  Future<void> _edit(PaymentSummary payment) async {
    final methods =
        ref.read(operationsConfigProvider).value?.paymentMethods ??
        OperationsConfig.defaults.paymentMethods;
    final values = await PaymentEditDialog.show(context, payment, methods);
    if (values == null || !mounted) return;
    await applyPaymentEdit(
      payments: ref.read(paymentsControllerProvider.notifier),
      undo: _undo,
      payment: payment,
      values: values,
    );
  }

  Future<void> _verify(PaymentSummary payment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const TitleWithInfo('Verify payment?', 'verify'),
        content: Text(
          'This confirms the money arrived and applies ${formatPeso(payment.amountCentavos)} to the oldest unpaid installments, interest first, then principal.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm Received'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final payments = ref.read(paymentsControllerProvider.notifier);
    final saved = await payments.verify(payment);
    if (!mounted) return;
    if (saved) {
      _undo.offer(
        'Payment confirmed and applied to the balance.',
        () => payments.undoVerification(payment.id),
      );
    } else {
      _undo.record('Payment verification failed.');
    }
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
    _undo.record(
      saved
          ? 'Payment reversed with an audit record.'
          : 'Payment reversal failed.',
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard(
    this.payment, {
    required this.onVerify,
    required this.onReject,
    required this.onReverse,
    required this.onEdit,
    this.selected,
    this.onSelected,
  });
  final PaymentSummary payment;
  final VoidCallback onVerify, onReject, onReverse, onEdit;

  /// Null when the payment cannot be selected (not pending).
  final bool? selected;
  final ValueChanged<bool>? onSelected;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (selected != null)
                Checkbox(
                  value: selected,
                  onChanged: (on) => onSelected?.call(on ?? false),
                ),
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
          if (payment.lateReason?.isNotEmpty ?? false)
            Text(
              'Late: ${payment.lateReason}',
              style: TextStyle(color: Theme.of(context).colorScheme.tertiary),
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
                  TextButton(onPressed: onEdit, child: const Text('Edit…')),
                  TextButton(onPressed: onVerify, child: const Text('Verify…')),
                  TextButton(onPressed: onReject, child: const Text('Reject…')),
                ],
              ),
            ),
          ],
          if (payment.status == 'verified')
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                children: [
                  TextButton(onPressed: onEdit, child: const Text('Edit…')),
                  TextButton(
                    onPressed: onReverse,
                    child: const Text('Reverse Payment'),
                  ),
                ],
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
    this.lateReason,
  });
  final String loanId, method, reference;
  final int amountCentavos;
  final DateTime receivedAt;
  final String? lateReason;
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({
    required this.loans,
    required this.methods,
    required this.loadLoan,
  });
  final List<LoanSummary> loans;
  final List<String> methods;

  /// Loads the loan's schedule, to tell whether the payment is late.
  final Future<LoanDetail> Function(String loanId) loadLoan;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final key = GlobalKey<FormState>();
  final amount = TextEditingController();
  final reference = TextEditingController();
  final lateReason = TextEditingController();
  late String loanId = widget.loans.first.id;
  late String method = widget.methods.first;
  DateTime receivedAt = DateTime.now();
  final Map<String, LoanDetail> _details = {};

  @override
  void initState() {
    super.initState();
    _loadDetail(loanId);
  }

  Future<void> _loadDetail(String id) async {
    if (_details.containsKey(id)) return;
    try {
      final detail = await widget.loadLoan(id);
      if (mounted) setState(() => _details[id] = detail);
    } catch (_) {
      // Without the schedule the late check is skipped; recording still works.
    }
  }

  ({int days, DateTime due})? get _late {
    final detail = _details[loanId];
    return detail == null ? null : lateness(detail, receivedAt);
  }

  @override
  void dispose() {
    amount.dispose();
    reference.dispose();
    lateReason.dispose();
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
                onChanged: (value) {
                  setState(() => loanId = value!);
                  _loadDetail(value!);
                },
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
              ReceivedAtField(
                value: receivedAt,
                onChanged: (value) => setState(() => receivedAt = value),
              ),
              if (_late case final late?) ...[
                const SizedBox(height: 8),
                Text(
                  'This payment is ${late.days} day${late.days == 1 ? '' : 's'} '
                  'after the due date (${formatPhilippineDate(late.due)}).',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.tertiary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                LateReasonField(controller: lateReason),
                const SizedBox(height: 12),
              ],
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
              lateReason: _late == null ? null : lateReason.text.trim(),
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
    // Scrolls so fields never hide under the buttons (phones, keyboard).
    scrollable: true,
    title: const TitleWithInfo('Reject payment?', 'reject'),
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
    // Scrolls so fields never hide under the buttons (phones, keyboard).
    scrollable: true,
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
