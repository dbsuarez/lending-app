import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/info_tip.dart';
import '../../core/config/app_config.dart';
import '../../core/formatting.dart';
import '../../core/widgets/metric_grid.dart';
import '../../core/widgets/app_status_badge.dart';
import '../../domain/models/models.dart';
import '../../domain/services/loan_calculator.dart';
import '../../core/undo/undo_controller.dart';
import '../documents/loan_print_menu.dart';
import '../settings/operations_config_provider.dart';
import 'extension_preview_dialog.dart';
import 'loans_controller.dart';

class LoanDetailScreen extends ConsumerStatefulWidget {
  const LoanDetailScreen({
    super.key,
    required this.loanId,
    this.origin,
    this.borrowerId,
  });
  final String loanId;
  final String? origin, borrowerId;

  @override
  ConsumerState<LoanDetailScreen> createState() => _LoanDetailScreenState();
}

class _LoanDetailScreenState extends ConsumerState<LoanDetailScreen> {
  late Future<LoanDetail> detail;

  @override
  void initState() {
    super.initState();
    detail = ref
        .read(loansControllerProvider.notifier)
        .fetchDetail(widget.loanId);
  }

  void _reload() {
    setState(() {
      detail = ref
          .read(loansControllerProvider.notifier)
          .fetchDetail(widget.loanId);
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<LoanDetail>(
    future: detail,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError || !snapshot.hasData) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Loan details could not be loaded.'),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        );
      }
      return _content(snapshot.data!);
    },
  );

  Widget _content(LoanDetail loan) => DefaultTabController(
    length: 6,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _breadcrumbs(loan),
              const SizedBox(height: 6),
              _detailHeader(loan),
            ],
          ),
        ),
        const TabBar(
          isScrollable: true,
          tabs: [
            Tab(text: 'Overview'),
            Tab(text: 'Schedule'),
            Tab(text: 'Payment Ledger'),
            Tab(text: 'Payments'),
            Tab(text: 'Activity'),
            Tab(text: 'Documents'),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [
              _Overview(loan),
              _Schedule(loan.installments),
              _PaymentLedger(loan),
              _LoanPayments(loan.summary.id),
              _LoanActivity(loan.summary.id),
              _LoanDocuments(
                loan: loan,
                onCreateLink: () => _createShareLink(loan),
                onManageLinks: () => _manageShareLinks(loan),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  String get _backPath => switch (widget.origin) {
    'borrower' when widget.borrowerId != null =>
      '/borrowers/${widget.borrowerId}',
    'personal' => '/personal-loans',
    'dashboard' => '/dashboard',
    _ => '/loans',
  };

  Widget _breadcrumbs(LoanDetail loan) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      TextButton(
        // Root crumb goes to the section list; the borrower crumb below
        // (when present) is the one that returns to the borrower profile.
        onPressed: () => context.go(switch (widget.origin) {
          'borrower' => '/borrowers',
          _ => _backPath,
        }),
        child: Text(switch (widget.origin) {
          'borrower' => 'Borrowers',
          'personal' => 'Personal Loans',
          'dashboard' => 'Dashboard',
          _ => 'Loans',
        }),
      ),
      const Icon(Icons.chevron_right, size: 18),
      if (widget.origin == 'borrower') ...[
        TextButton(
          onPressed: () => context.go(_backPath),
          child: Text(loan.summary.borrowerName),
        ),
        const Icon(Icons.chevron_right, size: 18),
      ],
      Text(_reference(loan.summary.id)),
    ],
  );

  Widget _detailHeader(LoanDetail loan) => LayoutBuilder(
    builder: (context, constraints) {
      final mobile = constraints.maxWidth < 700;
      final title = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            loan.summary.borrowerName,
            maxLines: mobile ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text(
            _reference(loan.summary.id),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
      final utilityActions = <Widget>[
        LoanPrintMenu(loadLoan: () async => loan),
        IconButton(
          tooltip: 'Get customer link',
          onPressed: () => _createShareLink(loan),
          icon: const Icon(Icons.link),
        ),
        IconButton(
          tooltip: 'Manage customer links',
          onPressed: () => _manageShareLinks(loan),
          icon: const Icon(Icons.link_off),
        ),
      ];
      final loanActions = <Widget>[
        OutlinedButton.icon(
          onPressed: () => _setPersonal(loan),
          icon: Icon(
            loan.summary.isPersonal
                ? Icons.business_center_outlined
                : Icons.person_outline,
          ),
          label: Text(
            loan.summary.isPersonal ? 'Move to Business' : 'Mark Personal',
          ),
        ),
        if (loan.summary.status == 'active') ...[
          _explained(
            'extension_preview',
            OutlinedButton.icon(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => ExtensionPreviewDialog(loan),
              ),
              icon: const Icon(Icons.request_quote_outlined),
              label: const Text('Preview Extension'),
            ),
          ),
          _explained(
            'amend_due_date',
            OutlinedButton.icon(
              onPressed: () => _amendDueDate(loan),
              icon: const Icon(Icons.edit_calendar_outlined),
              label: const Text('Change Due Date'),
            ),
          ),
          _explained(
            'refinance',
            OutlinedButton.icon(
              onPressed: () => _refinance(loan),
              icon: const Icon(Icons.autorenew),
              label: const Text('Refinance'),
            ),
          ),
          _explained(
            'early_payoff',
            OutlinedButton.icon(
              onPressed: () => _earlyPayoff(loan),
              icon: const Icon(Icons.savings_outlined),
              label: const Text('Early Payoff'),
            ),
          ),
        ],
        if (loan.summary.status == 'draft') ...[
          _explained(
            'cancel_draft',
            OutlinedButton.icon(
              onPressed: () => _cancelDraft(loan),
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancel Draft'),
            ),
          ),
          FilledButton.icon(
            onPressed: () => _activate(loan),
            icon: const Icon(Icons.verified_outlined),
            label: const Text('Confirm & Disburse'),
          ),
        ],
      ];
      if (!mobile) {
        return Row(
          children: [
            IconButton(
              tooltip: 'Back to loans',
              onPressed: () => context.go(_backPath),
              icon: const Icon(Icons.arrow_back),
            ),
            const SizedBox(width: 8),
            Expanded(child: title),
            ...utilityActions,
            AppStatusBadge(loan.summary.status),
            if (loanActions.isNotEmpty) const SizedBox(width: 8),
            ...loanActions.map(
              (action) => Padding(
                padding: const EdgeInsets.only(left: 8),
                child: action,
              ),
            ),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Back to loans',
                onPressed: () => context.go(_backPath),
                icon: const Icon(Icons.arrow_back),
              ),
              const SizedBox(width: 4),
              Expanded(child: title),
              AppStatusBadge(loan.summary.status),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ...utilityActions,
              ...loanActions,
              TextButton.icon(
                onPressed: () => _showActionGlossary(loan),
                icon: const Icon(Icons.info_outline, size: 18),
                label: const Text('What do these mean?'),
              ),
            ],
          ),
        ],
      );
    },
  );

  UndoController get _undo => ref.read(undoControllerProvider.notifier);

  /// Hover (desktop) or long-press (phone) shows the plain explanation.
  Widget _explained(String term, Widget child) => Tooltip(
    message: glossary[term]?.body ?? '',
    waitDuration: const Duration(milliseconds: 500),
    child: child,
  );

  void _showActionGlossary(LoanDetail loan) {
    final terms = [
      if (loan.summary.status == 'draft') ...['disburse', 'cancel_draft'],
      if (loan.summary.status == 'active') ...[
        'extension_preview',
        'amend_due_date',
        'consent_date',
        'refinance',
        'early_payoff',
      ],
      'mark_personal',
      'customer_link',
      'audit_history',
    ];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              Text(
                'What these actions mean',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              for (final term in terms)
                if (glossary[term] case final entry?)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(entry.body),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  LoansController get _loans => ref.read(loansControllerProvider.notifier);

  /// Wraps an undo call so this page refreshes if it is still open.
  Future<bool> Function() _undoThenReload(Future<bool> Function() undo) =>
      () async {
        final undone = await undo();
        if (undone && mounted) _reload();
        return undone;
      };

  Future<void> _setPersonal(LoanDetail loan) async {
    final loanId = loan.summary.id;
    final personal = !loan.summary.isPersonal;
    final changed = await _loans.setPersonal(loanId, personal);
    if (!mounted) return;
    if (changed) {
      _undo.offer(
        personal
            ? 'Loan moved to Personal Loans.'
            : 'Loan moved to Business Loans.',
        _undoThenReload(() => _loans.setPersonal(loanId, !personal)),
      );
      _reload();
    } else {
      _undo.record('Loan classification could not be changed.');
    }
  }

  Future<void> _activate(LoanDetail loan) async {
    final values = await showDialog<_DisbursementValues>(
      context: context,
      builder: (_) => _DisbursementDialog(
        principalCentavos: loan.summary.principalCentavos,
        methods:
            ref.read(operationsConfigProvider).value?.paymentMethods ??
            OperationsConfig.defaults.paymentMethods,
      ),
    );
    if (values == null) return;
    final activated = await ref
        .read(loansControllerProvider.notifier)
        .activate(
          loanId: loan.summary.id,
          disbursedOn: values.date,
          method: values.method,
          reference: values.reference,
        );
    if (!mounted) return;
    if (activated) {
      final loanId = loan.summary.id;
      _undo.offer(
        'Loan confirmed and money release recorded.',
        _undoThenReload(() => _loans.undoActivation(loanId)),
      );
      _reload();
    } else {
      _undo.record(
        'Loan could not be activated. Check the details and try again.',
      );
    }
  }

  Future<void> _cancelDraft(LoanDetail loan) async {
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const TitleWithInfo('Cancel draft loan?', 'cancel_draft'),
        content: TextField(
          controller: reasonController,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Reason',
            hintText: 'Required for the audit history',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Keep Draft'),
          ),
          FilledButton(
            onPressed: () {
              final value = reasonController.text.trim();
              if (value.length >= 3) Navigator.pop(dialogContext, value);
            },
            child: const Text('Cancel Draft'),
          ),
        ],
      ),
    );
    reasonController.dispose();
    if (reason == null) return;
    final cancelled = await ref
        .read(loansControllerProvider.notifier)
        .cancelDraft(loanId: loan.summary.id, reason: reason);
    if (!mounted) return;
    _undo.record(
      cancelled
          ? 'Draft loan cancelled and recorded in the audit history.'
          : 'Draft loan could not be cancelled.',
    );
    if (cancelled) _reload();
  }

  Future<void> _earlyPayoff(LoanDetail loan) async {
    final date = DateTime.now();
    final quote = await ref
        .read(loansControllerProvider.notifier)
        .earlyPayoffQuote(loan.summary.id, date);
    if (!mounted) return;
    if (quote == null) {
      _undo.notify('The payoff quote could not be loaded.');
      return;
    }
    final values = await showDialog<_PayoffValues>(
      context: context,
      builder: (_) => _EarlyPayoffDialog(
        quote: quote,
        methods:
            ref.read(operationsConfigProvider).value?.paymentMethods ??
            OperationsConfig.defaults.paymentMethods,
      ),
    );
    if (values == null) return;
    final paymentId = await ref
        .read(loansControllerProvider.notifier)
        .recordEarlyPayoff(
          loanId: loan.summary.id,
          date: quote.payoffDate,
          method: values.method,
          reference: values.reference,
        );
    if (!mounted) return;
    if (paymentId != null) {
      _undo.offer(
        'Loan settled early; future unearned interest was waived.',
        _undoThenReload(() => _loans.undoEarlyPayoff(paymentId)),
      );
      _reload();
    } else {
      _undo.record('Early payoff could not be recorded.');
    }
  }

  Future<void> _amendDueDate(LoanDetail loan) async {
    final values = await showDialog<_AmendmentValues>(
      context: context,
      builder: (_) => _AmendmentDialog(loan.installments),
    );
    if (values == null) return;
    final amendmentId = await ref
        .read(loansControllerProvider.notifier)
        .amendInstallmentDueDate(
          loanId: loan.summary.id,
          sequence: values.sequence,
          newDueDate: values.newDueDate,
          reason: values.reason,
          consentDate: values.consentDate,
        );
    if (!mounted) return;
    if (amendmentId != null) {
      _undo.offer(
        'Due date changed. The change and consent are in the audit history.',
        _undoThenReload(() => _loans.undoDueDateAmendment(amendmentId)),
      );
      _reload();
    } else {
      _undo.record(
        'Due date could not be changed. Paid installments and dates out of '
        'order cannot be changed.',
      );
    }
  }

  Future<void> _refinance(LoanDetail loan) async {
    final values = await showDialog<_RefinanceValues>(
      context: context,
      builder: (_) => _RefinanceDialog(loan.summary),
    );
    if (values == null) return;
    final quote = const LoanCalculator().calculate(
      principalCentavos: values.principalCentavos,
      monthlyRateBasisPoints: values.rateBasisPoints,
      termMonths: values.termMonths,
      firstDueDate: values.firstDueDate,
      paydayPattern: values.paydays,
    );
    final newId = await ref
        .read(loansControllerProvider.notifier)
        .refinance(
          sourceLoanId: loan.summary.id,
          quote: quote,
          reason: values.reason,
          consentDate: values.consentDate,
        );
    if (!mounted) return;
    if (newId == null) {
      _undo.record('Refinancing could not be created.');
      return;
    }
    _undo.record('Refinancing draft created and linked to the original loan.');
    context.go('/loans/$newId');
  }

  Future<void> _createShareLink(LoanDetail loan) async {
    final link = await ref
        .read(loansControllerProvider.notifier)
        .createShareLink(loan.summary.id);
    if (!mounted) return;
    if (link == null) {
      _undo.record('Customer link could not be created.');
      return;
    }
    if (!link.reused) {
      _undo.offer(
        'Customer status link created.',
        () => _loans.revokeShareLink(link.id),
      );
    }
    await _showLinkDialog(link.token, reused: link.reused);
  }

  String _linkUrl(String token) {
    final base = AppConfig.publicAppUrl.isEmpty
        ? Uri.base
        : Uri.parse(AppConfig.publicAppUrl);
    return base
        .replace(path: '/s/$token', query: null, fragment: null)
        .toString();
  }

  Future<void> _copyLink(String token) async {
    await Clipboard.setData(ClipboardData(text: _linkUrl(token)));
    if (mounted) _undo.notify('Customer link copied.');
  }

  Future<void> _showLinkDialog(String token, {required bool reused}) async {
    final url = _linkUrl(token);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const TitleWithInfo('Customer status link', 'customer_link'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${reused ? 'This loan already has a link; here it is again. ' : ''}'
                'Anyone with this link can see this loan\'s status until you '
                'revoke it. Send it only to the borrower.',
              ),
              const SizedBox(height: 12),
              SelectableText(url),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () async {
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              await _copyLink(token);
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy Link'),
          ),
        ],
      ),
    );
  }

  Future<void> _manageShareLinks(LoanDetail loan) async {
    final controller = ref.read(loansControllerProvider.notifier);
    var links = await controller.fetchShareLinks(loan.summary.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Customer links'),
          content: SizedBox(
            width: 620,
            child: links.isEmpty
                ? const Text('No customer links have been created.')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: links.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (_, index) {
                      final link = links[index];
                      return ListTile(
                        leading: Icon(
                          link.isActive ? Icons.link : Icons.link_off,
                        ),
                        title: Text(
                          link.isActive ? 'Active link' : 'Inactive link',
                        ),
                        subtitle: Text(
                          'Created ${formatPhilippineDateTime(link.createdAt.toLocal())}'
                          '${link.isActive && !link.canCopy ? '\nOlder link: still works, but it cannot be copied. Revoke it and use Get Link for one you can copy.' : ''}',
                        ),
                        isThreeLine: link.isActive && !link.canCopy,
                        trailing: link.isActive
                            ? Wrap(
                                spacing: 4,
                                children: [
                                  if (link.canCopy)
                                    TextButton.icon(
                                      onPressed: () => _copyLink(link.token!),
                                      icon: const Icon(Icons.copy, size: 18),
                                      label: const Text('Copy'),
                                    ),
                                  TextButton(
                                    onPressed: () async {
                                      final revoked = await controller
                                          .revokeShareLink(link.id);
                                      if (revoked) {
                                        links = await controller
                                            .fetchShareLinks(loan.summary.id);
                                        setDialogState(() {});
                                      }
                                    },
                                    child: const Text('Revoke'),
                                  ),
                                ],
                              )
                            : null,
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview(this.loan);
  final LoanDetail loan;

  @override
  Widget build(BuildContext context) => ListView(
    padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 16 : 24),
    children: [
      MetricGrid(
        children: [
          MetricCard(
            'Principal',
            formatPeso(loan.summary.principalCentavos),
            info: 'principal',
          ),
          MetricCard(
            'Flat interest',
            formatPeso(
              loan.summary.totalCentavos - loan.summary.principalCentavos,
            ),
            info: 'flat_interest',
          ),
          MetricCard(
            'Total repayable',
            formatPeso(loan.summary.totalCentavos),
            info: 'total_repayable',
          ),
          MetricCard('Amount paid', formatPeso(loan.paidCentavos)),
          MetricCard(
            'Still owed',
            formatPeso(loan.outstandingCentavos),
            info: 'still_owed',
          ),
          MetricCard(
            'Payment progress',
            loan.summary.totalCentavos == 0
                ? '0.0%'
                : '${(loan.paidCentavos * 100 / loan.summary.totalCentavos).toStringAsFixed(1)}%',
            info: 'payment_progress',
          ),
          MetricCard(
            'Installments paid',
            '${loan.installments.where((item) => item.paidCentavos >= item.amountCentavos).length} of ${loan.installments.length}',
            info: 'installment',
          ),
          MetricCard('Term', '${loan.summary.termMonths} months', info: 'term'),
          MetricCard(
            'Monthly rate',
            '${(loan.summary.monthlyRateBasisPoints / 100).toStringAsFixed(2)}%',
            info: 'monthly_rate',
          ),
          MetricCard(
            'Borrowed',
            loan.summary.borrowedOn == null
                ? 'Not released'
                : formatPhilippineDate(loan.summary.borrowedOn!),
            info: 'borrowed',
          ),
          MetricCard(
            'Paid',
            loan.summary.paidOn == null
                ? 'Not paid'
                : formatPhilippineDate(loan.summary.paidOn!),
            info: 'paid_date',
          ),
          MetricCard('Created', formatPhilippineDate(loan.summary.createdAt)),
        ],
      ),
      const SizedBox(height: 20),
      Card(
        child: ListTile(
          leading: Icon(
            _stateIcon(loan),
            color: _overdueCount(loan) > 0
                ? Theme.of(context).colorScheme.error
                : null,
          ),
          title: const Text('Financial state'),
          subtitle: Text(financialStateText(loan)),
        ),
      ),
    ],
  );

  static IconData _stateIcon(LoanDetail loan) => switch (loan.summary.status) {
    'active' when _overdueCount(loan) > 0 => Icons.warning_amber_rounded,
    'active' => Icons.payments_outlined,
    'fully_paid' => Icons.check_circle_outline,
    'cancelled' => Icons.block,
    'refinanced' => Icons.autorenew,
    _ => Icons.info_outline,
  };
}

int _overdueCount(LoanDetail loan, {DateTime? today}) {
  final now = today ?? DateTime.now();
  final day = DateTime(now.year, now.month, now.day);
  return loan.installments
      .where(
        (i) => i.paidCentavos < i.amountCentavos && i.dueDate.isBefore(day),
      )
      .length;
}

/// Plain-language summary of where the loan stands, by status.
@visibleForTesting
String financialStateText(LoanDetail loan, {DateTime? today}) {
  final summary = loan.summary;
  switch (summary.status) {
    case 'draft':
      return 'No money has been released for this draft yet. Confirm & '
          'Disburse records that you released the money, and locks the '
          'agreed terms as an active loan.';
    case 'cancelled':
      return 'This draft was cancelled before any money was released. '
          'Nothing is owed.';
    case 'refinanced':
      return 'This loan was closed and replaced by a refinanced loan. See the '
          'new loan for what is owed now.';
    case 'fully_paid':
      final paidOn = summary.paidOn;
      return 'Fully paid${paidOn == null ? '' : ' on ${formatPhilippineDate(paidOn)}'}. '
          'Nothing is owed.';
  }
  final released = summary.borrowedOn == null
      ? 'Money released.'
      : 'Money released on ${formatPhilippineDate(summary.borrowedOn!)}.';
  final paid =
      ' ${formatPeso(loan.paidCentavos)} paid so far; '
      '${formatPeso(loan.outstandingCentavos)} still owed.';
  final unpaid = [...loan.installments]
    ..retainWhere((i) => i.paidCentavos < i.amountCentavos)
    ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  final overdue = _overdueCount(loan, today: today);
  final next = unpaid.isEmpty
      ? ''
      : ' Next due: ${formatPeso(unpaid.first.amountCentavos - unpaid.first.paidCentavos)} '
            'on ${formatPhilippineDate(unpaid.first.dueDate)}.';
  final late = overdue == 0
      ? ''
      : ' $overdue ${overdue == 1 ? 'installment is' : 'installments are'} '
            'past due.';
  return '$released$paid$next$late';
}

class _PaymentLedger extends StatelessWidget {
  const _PaymentLedger(this.loan);
  final LoanDetail loan;

  @override
  Widget build(BuildContext context) {
    final rows = loan.ledgerRows();
    final totalPaid = loan.paidCentavos;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              Text(
                'Opening balance: ${formatPeso(loan.summary.totalCentavos)}',
              ),
              Text('Total paid: ${formatPeso(totalPaid)}'),
              Text('Balance: ${formatPeso(loan.outstandingCentavos)}'),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('No.')),
                  DataColumn(label: Text('Due Date')),
                  DataColumn(label: Text('Payment Date')),
                  DataColumn(label: Text('Payment'), numeric: true),
                  DataColumn(label: Text('Ending Balance'), numeric: true),
                  DataColumn(label: Text('Status')),
                ],
                rows: [
                  for (final row in rows)
                    DataRow(
                      cells: [
                        DataCell(Text('${row.installment.sequence}')),
                        DataCell(
                          Text(formatPhilippineDate(row.installment.dueDate)),
                        ),
                        DataCell(
                          Text(
                            row.installment.lastPaymentAt == null
                                ? '—'
                                : formatPhilippineDate(
                                    row.installment.lastPaymentAt!.toLocal(),
                                  ),
                          ),
                        ),
                        DataCell(
                          Text(formatPeso(row.installment.paidCentavos)),
                        ),
                        DataCell(Text(formatPeso(row.endingBalanceCentavos))),
                        DataCell(AppStatusBadge(row.status)),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Schedule extends StatefulWidget {
  const _Schedule(this.installments);
  final List<Installment> installments;

  @override
  State<_Schedule> createState() => _ScheduleState();
}

class _ScheduleState extends State<_Schedule> {
  int sortColumnIndex = 0;
  bool sortAscending = true;

  @override
  Widget build(BuildContext context) {
    final installments = [...widget.installments]
      ..sort((left, right) {
        final comparison = switch (sortColumnIndex) {
          0 => left.sequence.compareTo(right.sequence),
          1 => left.dueDate.compareTo(right.dueDate),
          2 => left.principalCentavos.compareTo(right.principalCentavos),
          3 => left.interestCentavos.compareTo(right.interestCentavos),
          4 => left.amountCentavos.compareTo(right.amountCentavos),
          _ => 0,
        };
        return sortAscending ? comparison : -comparison;
      });
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 700
          ? ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: installments.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, index) {
                final item = installments[index];
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(child: Text('${item.sequence}')),
                    title: Text(formatPhilippineDate(item.dueDate)),
                    trailing: Text(
                      formatPeso(item.amountCentavos),
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                );
              },
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: DataTable(
                  sortColumnIndex: sortColumnIndex,
                  sortAscending: sortAscending,
                  columns: [
                    DataColumn(
                      label: const Text('#'),
                      numeric: true,
                      onSort: _sort,
                    ),
                    DataColumn(label: const Text('Due date'), onSort: _sort),
                    DataColumn(
                      label: const Text('Principal'),
                      numeric: true,
                      onSort: _sort,
                    ),
                    DataColumn(
                      label: const Text('Interest'),
                      numeric: true,
                      onSort: _sort,
                    ),
                    DataColumn(
                      label: const Text('Scheduled'),
                      numeric: true,
                      onSort: _sort,
                    ),
                  ],
                  rows: [
                    for (final item in installments)
                      DataRow(
                        cells: [
                          DataCell(Text('${item.sequence}')),
                          DataCell(Text(formatPhilippineDate(item.dueDate))),
                          DataCell(Text(formatPeso(item.principalCentavos))),
                          DataCell(Text(formatPeso(item.interestCentavos))),
                          DataCell(Text(formatPeso(item.amountCentavos))),
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
}

class _LoanPayments extends ConsumerWidget {
  const _LoanPayments(this.loanId);
  final String loanId;
  @override
  Widget build(
    BuildContext context,
    WidgetRef ref,
  ) => FutureBuilder<List<PaymentSummary>>(
    future: ref
        .read(loansControllerProvider.notifier)
        .fetchLoanPayments(loanId),
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return const Center(
          child: Text('Payment history could not be loaded.'),
        );
      }
      final items = snapshot.data ?? const <PaymentSummary>[];
      if (items.isEmpty) {
        return const Center(child: Text('No payments recorded for this loan.'));
      }
      return ListView.separated(
        padding: const EdgeInsets.all(24),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, index) {
          final item = items[index];
          return Card(
            child: ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: Text(formatPeso(item.amountCentavos)),
              subtitle: Text(
                '${formatPhilippineDateTime(item.receivedAt)} · ${item.method}${item.reference.isEmpty ? '' : ' · ${item.reference}'}',
              ),
              trailing: Chip(label: Text(item.status)),
            ),
          );
        },
      );
    },
  );
}

class _LoanActivity extends ConsumerWidget {
  const _LoanActivity(this.loanId);
  final String loanId;
  @override
  Widget build(
    BuildContext context,
    WidgetRef ref,
  ) => FutureBuilder<List<AuditEventSummary>>(
    future: ref
        .read(loansControllerProvider.notifier)
        .fetchLoanActivity(loanId),
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return const Center(child: Text('Loan activity could not be loaded.'));
      }
      final items = snapshot.data ?? const <AuditEventSummary>[];
      if (items.isEmpty) {
        return const Center(child: Text('No audited activity for this loan.'));
      }
      return ListView.separated(
        padding: const EdgeInsets.all(24),
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, index) {
          final item = items[index];
          return ListTile(
            leading: const Icon(Icons.history),
            title: Text(_actionLabel(item.action)),
            subtitle: Text(formatPhilippineDateTime(item.createdAt)),
          );
        },
      );
    },
  );
}

class _LoanDocuments extends StatelessWidget {
  const _LoanDocuments({
    required this.loan,
    required this.onCreateLink,
    required this.onManageLinks,
  });
  final LoanDetail loan;
  final VoidCallback onCreateLink, onManageLinks;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Card(
        child: ListTile(
          leading: const Icon(Icons.calendar_month_outlined),
          title: const Text('Loan schedule'),
          subtitle: const Text(
            'A4 installment schedule for printing or saving as PDF.',
          ),
          trailing: FilledButton.icon(
            onPressed: () =>
                printLoanDocument(loan, LoanPrintDocument.schedule),
            icon: const Icon(Icons.print_outlined),
            label: const Text('Print'),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Card(
        child: ListTile(
          leading: const Icon(Icons.receipt_long_outlined),
          title: const Text('Payment ledger'),
          subtitle: const Text(
            'A4 ledger of payments and running balance, for printing or saving as PDF.',
          ),
          trailing: FilledButton.icon(
            onPressed: () => printLoanDocument(loan, LoanPrintDocument.ledger),
            icon: const Icon(Icons.print_outlined),
            label: const Text('Print'),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Card(
        child: ListTile(
          leading: const Icon(Icons.link),
          title: const Text('Customer status link'),
          subtitle: const Text(
            'Get, copy, or revoke the read-only status link for the borrower.',
          ),
          trailing: Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: onManageLinks,
                child: const Text('Manage'),
              ),
              FilledButton(
                onPressed: onCreateLink,
                child: const Text('Get Link'),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

String _actionLabel(String action) => action
    .split('_')
    .map(
      (word) =>
          word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}',
    )
    .join(' ');

class _DisbursementValues {
  const _DisbursementValues(this.date, this.method, this.reference);
  final DateTime date;
  final String method, reference;
}

class _AmendmentValues {
  const _AmendmentValues(
    this.sequence,
    this.newDueDate,
    this.consentDate,
    this.reason,
  );
  final int sequence;
  final DateTime newDueDate, consentDate;
  final String reason;
}

class _AmendmentDialog extends StatefulWidget {
  const _AmendmentDialog(this.installments);
  final List<Installment> installments;
  @override
  State<_AmendmentDialog> createState() => _AmendmentDialogState();
}

class _AmendmentDialogState extends State<_AmendmentDialog> {
  late int sequence = widget.installments.first.sequence;
  late DateTime newDueDate = widget.installments.first.dueDate;
  DateTime consentDate = DateTime.now();
  final reason = TextEditingController();
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const TitleWithInfo('Change a due date', 'amend_due_date'),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<int>(
            initialValue: sequence,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Installment'),
            items: [
              for (final item in widget.installments)
                DropdownMenuItem(
                  value: item.sequence,
                  child: Text(
                    '#${item.sequence} · ${formatPhilippineDate(item.dueDate)}',
                  ),
                ),
            ],
            onChanged: (value) => setState(() {
              sequence = value!;
              newDueDate = widget.installments
                  .firstWhere((item) => item.sequence == value)
                  .dueDate;
            }),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('New due date'),
            subtitle: Text(formatPhilippineDate(newDueDate)),
            trailing: const Icon(Icons.event),
            onTap: () async {
              final value = await showDatePicker(
                context: context,
                initialDate: newDueDate,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 3650)),
              );
              if (value != null) setState(() => newDueDate = value);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const TitleWithInfo('Borrower consent date', 'consent_date'),
            subtitle: Text(formatPhilippineDate(consentDate)),
            trailing: const Icon(Icons.fact_check_outlined),
            onTap: () async {
              final value = await showDatePicker(
                context: context,
                initialDate: consentDate,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (value != null) setState(() => consentDate = value);
            },
          ),
          TextField(
            controller: reason,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Reason',
              helperText: 'Required for the audit history',
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final text = reason.text.trim();
          if (text.length >= 3) {
            Navigator.pop(
              context,
              _AmendmentValues(sequence, newDueDate, consentDate, text),
            );
          }
        },
        child: const Text('Save Amendment'),
      ),
    ],
  );
}

class _RefinanceValues {
  const _RefinanceValues(
    this.principalCentavos,
    this.rateBasisPoints,
    this.termMonths,
    this.firstDueDate,
    this.paydays,
    this.consentDate,
    this.reason,
  );
  final int principalCentavos, rateBasisPoints, termMonths;
  final DateTime firstDueDate, consentDate;
  final List<int> paydays;
  final String reason;
}

class _RefinanceDialog extends StatefulWidget {
  const _RefinanceDialog(this.loan);
  final LoanSummary loan;
  @override
  State<_RefinanceDialog> createState() => _RefinanceDialogState();
}

class _RefinanceDialogState extends State<_RefinanceDialog> {
  late final principal = TextEditingController(
    text: (widget.loan.principalCentavos / 100).toStringAsFixed(2),
  );
  late final rate = TextEditingController(
    text: (widget.loan.monthlyRateBasisPoints / 100).toStringAsFixed(2),
  );
  late final term = TextEditingController(text: '${widget.loan.termMonths}');
  final reason = TextEditingController();
  DateTime firstDueDate = DateTime.now().add(const Duration(days: 15));
  DateTime consentDate = DateTime.now();
  List<int> paydays = const [15, 30];
  @override
  void dispose() {
    principal.dispose();
    rate.dispose();
    term.dispose();
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const TitleWithInfo('Create refinancing draft', 'refinance'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          children: [
            const Text(
              'The original loan will be marked Refinanced. The new loan stays a draft until you confirm it and release the money.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: principal,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'New principal (PHP)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: rate,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Monthly flat rate (%)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: term,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Term (months)'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<List<int>>(
              initialValue: paydays,
              decoration: const InputDecoration(labelText: 'Paydays'),
              items: const [
                DropdownMenuItem(value: [15, 30], child: Text('15th and 30th')),
                DropdownMenuItem(value: [5, 20], child: Text('5th and 20th')),
              ],
              onChanged: (value) => setState(() => paydays = value!),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('First due date'),
              subtitle: Text(formatPhilippineDate(firstDueDate)),
              trailing: const Icon(Icons.event),
              onTap: () async {
                final value = await showDatePicker(
                  context: context,
                  initialDate: firstDueDate,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (value != null) setState(() => firstDueDate = value);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const TitleWithInfo(
                'Borrower consent date',
                'consent_date',
              ),
              subtitle: Text(formatPhilippineDate(consentDate)),
              trailing: const Icon(Icons.fact_check_outlined),
              onTap: () async {
                final value = await showDatePicker(
                  context: context,
                  initialDate: consentDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (value != null) setState(() => consentDate = value);
              },
            ),
            TextField(
              controller: reason,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Reason'),
            ),
          ],
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
          final principalValue = double.tryParse(principal.text);
          final rateValue = double.tryParse(rate.text);
          final termValue = int.tryParse(term.text);
          final reasonValue = reason.text.trim();
          if (principalValue == null ||
              principalValue <= 0 ||
              rateValue == null ||
              rateValue < 0 ||
              termValue == null ||
              termValue <= 0 ||
              reasonValue.length < 3) {
            return;
          }
          Navigator.pop(
            context,
            _RefinanceValues(
              (principalValue * 100).round(),
              (rateValue * 100).round(),
              termValue,
              firstDueDate,
              paydays,
              consentDate,
              reasonValue,
            ),
          );
        },
        child: const Text('Create Draft'),
      ),
    ],
  );
}

class _DisbursementDialog extends StatefulWidget {
  const _DisbursementDialog({
    required this.principalCentavos,
    required this.methods,
  });
  final int principalCentavos;
  final List<String> methods;

  @override
  State<_DisbursementDialog> createState() => _DisbursementDialogState();
}

class _DisbursementDialogState extends State<_DisbursementDialog> {
  DateTime date = DateTime.now();
  late String method = widget.methods.first;
  final reference = TextEditingController();

  @override
  void dispose() {
    reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const TitleWithInfo('Confirm and disburse loan', 'disburse'),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'This records that you released ${formatPeso(widget.principalCentavos)} to the borrower and makes the loan active. After this, the terms are locked.',
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Date the money was released'),
            subtitle: Text(formatPhilippineDate(date)),
            trailing: const Icon(Icons.event_outlined),
            onTap: () async {
              final selected = await showDatePicker(
                context: context,
                initialDate: date,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 1)),
              );
              if (selected != null) setState(() => date = selected);
            },
          ),
          const SizedBox(height: 8),
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
          TextField(
            controller: reference,
            decoration: const InputDecoration(
              labelText: 'Reference (optional)',
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          _DisbursementValues(date, method, reference.text.trim()),
        ),
        child: const Text('Confirm & Disburse'),
      ),
    ],
  );
}

class _PayoffValues {
  const _PayoffValues(this.method, this.reference);
  final String method, reference;
}

class _EarlyPayoffDialog extends StatefulWidget {
  const _EarlyPayoffDialog({required this.quote, required this.methods});
  final EarlyPayoffQuote quote;
  final List<String> methods;
  @override
  State<_EarlyPayoffDialog> createState() => _EarlyPayoffDialogState();
}

class _EarlyPayoffDialogState extends State<_EarlyPayoffDialog> {
  late String method = widget.methods.first;
  final reference = TextEditingController();
  @override
  void dispose() {
    reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const TitleWithInfo('Record early payoff', 'early_payoff'),
    content: SizedBox(
      width: 500,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            title: const Text('Remaining principal'),
            trailing: Text(formatPeso(widget.quote.principalCentavos)),
          ),
          ListTile(
            title: const Text('Interest earned through payoff date'),
            trailing: Text(formatPeso(widget.quote.earnedInterestCentavos)),
          ),
          const Divider(),
          ListTile(
            title: const Text(
              'Payoff amount',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            trailing: Text(
              formatPeso(widget.quote.payoffCentavos),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const Text(
            'Future unearned interest will be waived. This operation is permanent and audited.',
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: method,
            decoration: const InputDecoration(labelText: 'Payment method'),
            items: [
              for (final item in widget.methods)
                DropdownMenuItem(value: item, child: Text(item)),
            ],
            onChanged: (value) => setState(() => method = value!),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: reference,
            decoration: const InputDecoration(
              labelText: 'Reference (optional)',
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          _PayoffValues(method, reference.text.trim()),
        ),
        child: const Text('Confirm Payoff'),
      ),
    ],
  );
}

String _reference(String id) => 'LN-${id.substring(0, 8).toUpperCase()}';
