import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../penalties/penalty_widgets.dart';
import '../../core/formatting.dart';
import '../../core/undo/undo_controller.dart';
import '../../domain/models/models.dart';
import '../../domain/services/loan_calculator.dart';
import '../borrowers/borrowers_controller.dart';
import '../settings/operations_config_provider.dart';
import 'loans_controller.dart';

class LoanFormScreen extends ConsumerStatefulWidget {
  /// With [loanId], edits that draft (or corrects that active loan without
  /// payments) instead of creating a new one.
  const LoanFormScreen({super.key, this.loanId});
  final String? loanId;
  @override
  ConsumerState<LoanFormScreen> createState() => _LoanFormScreenState();
}

class _LoanFormScreenState extends ConsumerState<LoanFormScreen> {
  final key = GlobalKey<FormState>(),
      principal = TextEditingController(text: '20000'),
      term = TextEditingController(text: '5'),
      rate = TextEditingController(text: '6'),
      customPaydays = TextEditingController(text: '10,25');
  int step = 0;
  List<int> pattern = [15, 30];
  late DateTime firstDue;
  String? borrowerId;
  LoanQuote? quote;
  bool saving = false;

  // Edit mode.
  bool get editing => widget.loanId != null;
  LoanDetail? original;
  LoanEditTerms? originalTerms;
  Object? loadError;
  final reason = TextEditingController(),
      releaseReference = TextEditingController();
  DateTime? releaseDate;
  String? releaseMethod;

  /// Null until chosen: new loans use the Settings default.
  PenaltyPolicy? penalty;
  PenaltyPolicy get _penalty =>
      penalty ??
      (editing
          ? originalTerms?.penaltyPolicy ?? PenaltyPolicy.none
          : PenaltyPolicy.none);
  bool get correctingActive => original?.summary.status == 'active';

  @override
  void initState() {
    super.initState();
    firstDue = _nextPayday(DateTime.now(), pattern);
    if (editing) {
      _loadOriginal();
    } else {
      // New loans start with the Settings default.
      ref
          .read(penaltyDefaultProvider.future)
          .then((policy) {
            if (mounted && penalty == null) setState(() => penalty = policy);
          })
          .catchError((_) {});
    }
  }

  Future<void> _loadOriginal() async {
    final loans = ref.read(loansControllerProvider.notifier);
    try {
      final detail = await loans.fetchDetail(widget.loanId!);
      final terms = await loans.fetchEditTerms(widget.loanId!);
      if (!mounted) return;
      final s = detail.summary;
      setState(() {
        original = detail;
        originalTerms = terms;
        borrowerId = s.borrowerId;
        principal.text = _plain(s.principalCentavos / 100);
        rate.text = _plain(s.monthlyRateBasisPoints / 100);
        term.text = '${s.termMonths}';
        pattern = terms.paydayPattern;
        customPaydays.text = pattern.join(',');
        firstDue = terms.firstDueDate;
        releaseDate = terms.disbursedOn;
        releaseMethod = terms.method;
        releaseReference.text = terms.reference ?? '';
      });
    } catch (error) {
      if (mounted) setState(() => loadError = error);
    }
  }

  static String _plain(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);

  /// Where a new payday pattern starts counting from: today for new loans,
  /// the release date when correcting a released loan.
  DateTime get _patternBase => correctingActive && releaseDate != null
      ? releaseDate!.add(const Duration(days: 1))
      : DateTime.now();

  @override
  void dispose() {
    principal.dispose();
    term.dispose();
    rate.dispose();
    customPaydays.dispose();
    reason.dispose();
    releaseReference.dispose();
    super.dispose();
  }

  void calculate() {
    if (!key.currentState!.validate()) return;
    final result = const LoanCalculator().calculate(
      principalCentavos: (double.parse(principal.text) * 100).round(),
      monthlyRateBasisPoints: (double.parse(rate.text) * 100).round(),
      termMonths: int.parse(term.text),
      firstDueDate: firstDue,
      paydayPattern: pattern,
    );
    if (!_sameDate(result.installments.first.dueDate, firstDue)) {
      undoOf(
        context,
      ).notify('First due date must match the selected payday pattern.');
      return;
    }
    setState(() => quote = result);
  }

  Future<void> _saveDraft() async {
    if (editing) return _saveCorrection();
    final currentQuote = quote;
    final borrowers = ref.read(borrowersControllerProvider).value;
    if (currentQuote == null || borrowers == null || borrowerId == null) return;
    final borrower = borrowers.firstWhere((item) => item.id == borrowerId);
    setState(() => saving = true);
    final loans = ref.read(loansControllerProvider.notifier);
    final undo = ref.read(undoControllerProvider.notifier);
    final loanId = await loans.createDraft(
      borrower: borrower,
      quote: currentQuote,
      firstDueDate: firstDue,
      paydayPattern: pattern,
    );
    if (!mounted) return;
    setState(() => saving = false);
    if (loanId != null) {
      if (_penalty.charges) {
        try {
          await loans.setPenaltyPolicy(loanId, _penalty);
        } catch (_) {
          undo.record(
            'Draft created, but its penalties could not be saved. Open the '
            'draft and set them again.',
          );
        }
      }
      if (!mounted) return;
      undo.offer('Loan draft created.', () => loans.undoCreateDraft(loanId));
      // Open the new draft (the Loans list defaults to Active, so the draft
      // would not be listed there); its next step is Confirm & Disburse.
      context.go('/loans/$loanId?from=loans');
    } else {
      undo.record('Loan draft could not be created. Try again.');
    }
  }

  Future<void> _saveCorrection() async {
    final currentQuote = quote;
    final loan = original;
    final borrowers = ref.read(borrowersControllerProvider).value;
    if (currentQuote == null || loan == null || borrowerId == null) return;
    final why = reason.text.trim();
    if (correctingActive && why.length < 3) {
      undoOf(context).notify('Enter a short reason for the correction.');
      return;
    }
    final borrower =
        borrowers?.where((item) => item.id == borrowerId).firstOrNull ??
        Borrower(
          id: loan.summary.borrowerId,
          organizationId: loan.summary.organizationId,
          firstName: '',
          lastName: loan.summary.borrowerName,
        );
    setState(() => saving = true);
    final loans = ref.read(loansControllerProvider.notifier);
    final undo = ref.read(undoControllerProvider.notifier);
    try {
      final amendmentId = await loans.correctLoan(
        loan: loan.summary,
        borrower: borrower,
        quote: currentQuote,
        firstDueDate: firstDue,
        paydayPattern: pattern,
        disbursedOn: correctingActive ? releaseDate : null,
        method: correctingActive ? releaseMethod : null,
        reference: correctingActive ? releaseReference.text.trim() : null,
        reason: why,
      );
      if (!correctingActive && penalty != null) {
        await loans.setPenaltyPolicy(loan.summary.id, penalty!);
      }
      if (!mounted) return;
      undo.offer(
        correctingActive
            ? 'Loan corrected. The change and reason are in the history.'
            : 'Draft updated.',
        () => loans.undoLoanCorrection(amendmentId),
      );
      context.go('/loans/${loan.summary.id}?from=loans');
    } catch (error) {
      if (!mounted) return;
      setState(() => saving = false);
      undo.record(
        'Loan could not be updated: ${error is PostgrestException ? error.message : 'try again.'}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (editing && original == null) {
      return Center(
        child: loadError == null
            ? const CircularProgressIndicator()
            : const Text('Loan could not be loaded.'),
      );
    }
    final status = original?.summary.status;
    if (editing && status != 'draft' && status != 'active') {
      return const Center(
        child: Text('Only a draft or an active loan can be edited.'),
      );
    }
    // Phones: tighter page/card padding and a slimmer stepper rail so form
    // fields get most of the screen width.
    final compact = MediaQuery.sizeOf(context).width < 600;
    return SingleChildScrollView(
      padding: EdgeInsets.all(compact ? 12 : 24),
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(compact ? 12 : 24),
          child: Form(
            key: key,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  !editing
                      ? 'Create loan'
                      : correctingActive
                      ? 'Correct loan'
                      : 'Edit draft',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                Text(
                  !editing
                      ? 'Saving a draft does not release any money. The borrower owes nothing until you confirm and release the loan.'
                      : correctingActive
                      ? 'Fix a mistake in this released loan. It has no payments yet, so the schedule is simply rebuilt. The money-release record is replaced and the old one is kept in the history.'
                      : 'Change anything in this draft. No money has been released yet.',
                ),
                const SizedBox(height: 20),
                Stepper(
                  // The page scrolls; without this the stepper's own list
                  // swallows touch drags and the form can't scroll on phones.
                  physics: const NeverScrollableScrollPhysics(),
                  margin: compact
                      ? const EdgeInsetsDirectional.only(
                          start: 48,
                          end: 4,
                          bottom: 16,
                        )
                      : null,
                  currentStep: step,
                  onStepTapped: (v) => setState(() => step = v),
                  controlsBuilder: (context, d) => const SizedBox.shrink(),
                  steps: [
                    Step(
                      title: const Text('Terms'),
                      isActive: step >= 0,
                      content: _terms(),
                    ),
                    Step(
                      title: const Text('Schedule'),
                      isActive: step >= 1,
                      content: _schedule(),
                    ),
                    Step(
                      title: const Text('Review'),
                      isActive: step >= 2,
                      content: _review(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (editing)
                      TextButton(
                        onPressed: saving
                            ? null
                            : () => context.go(
                                '/loans/${widget.loanId}?from=loans',
                              ),
                        child: const Text('Cancel'),
                      ),
                    if (step > 0)
                      TextButton(
                        onPressed: () => setState(() => step--),
                        child: const Text('Back'),
                      ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: saving
                          ? null
                          : step == 0
                          ? () {
                              calculate();
                              if (quote != null) setState(() => step = 1);
                            }
                          : step == 1
                          ? () => setState(() => step = 2)
                          : _saveDraft,
                      child: saving
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              step < 2
                                  ? 'Continue'
                                  : editing
                                  ? 'Save Changes'
                                  : 'Create Draft',
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _terms() {
    final config =
        ref.watch(operationsConfigProvider).value ?? OperationsConfig.defaults;
    final selectedPatternKey =
        config.paydays.any((days) => _samePattern(days, pattern))
        ? pattern.join('_')
        : 'custom';
    return Column(
      children: [
        ref
            .watch(borrowersControllerProvider)
            .when(
              data: (borrowers) => DropdownButtonFormField<String>(
                initialValue: borrowerId,
                decoration: const InputDecoration(labelText: 'Borrower'),
                items: [
                  for (final borrower in borrowers)
                    DropdownMenuItem(
                      value: borrower.id,
                      child: Text(borrower.displayName),
                    ),
                  if (original != null &&
                      !borrowers.any(
                        (b) => b.id == original!.summary.borrowerId,
                      ))
                    DropdownMenuItem(
                      value: original!.summary.borrowerId,
                      child: Text(original!.summary.borrowerName),
                    ),
                ],
                onChanged: (value) => setState(() => borrowerId = value),
                validator: (value) =>
                    value == null ? 'Select a borrower' : null,
              ),
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => const ListTile(
                leading: Icon(Icons.error_outline),
                title: Text('Borrowers could not be loaded'),
              ),
            ),
        const SizedBox(height: 12),
        TextFormField(
          controller: principal,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.right,
          decoration: const InputDecoration(
            labelText: 'Principal (PHP)',
            prefixText: '₱ ',
          ),
          validator: _positive,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: rate,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.right,
          decoration: const InputDecoration(
            labelText: 'Flat monthly interest (%)',
            helperText: 'Presets: 3%, 6%, 10%; terms require compliance review',
            helperMaxLines: 2,
          ),
          validator: _nonNegative,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final v in config.rates)
              ChoiceChip(
                label: Text('${v.toString()}%'),
                selected: double.tryParse(rate.text) == v.toDouble(),
                onSelected: (_) {
                  setState(() => rate.text = v.toString());
                },
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: term,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.right,
          decoration: const InputDecoration(labelText: 'Term (whole months)'),
          validator: _positive,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: selectedPatternKey,
          decoration: const InputDecoration(labelText: 'Payday pattern'),
          items: [
            for (final days in config.paydays)
              DropdownMenuItem(
                value: days.join('_'),
                child: Text(days.map(_ordinal).join(' and ')),
              ),
            const DropdownMenuItem(value: 'custom', child: Text('Custom days')),
          ],
          onChanged: (value) {
            setState(() {
              pattern = value == 'custom'
                  ? _parsePaydays(customPaydays.text) ?? [10, 25]
                  : value!.split('_').map(int.parse).toList();
              firstDue = _nextPayday(_patternBase, pattern);
              quote = null;
            });
          },
        ),
        if (selectedPatternKey == 'custom') ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: customPaydays,
            decoration: const InputDecoration(
              labelText: 'Custom payday numbers',
              helperText:
                  'Comma-separated days from 1 to 31, for example 10,25',
            ),
            validator: (value) => _parsePaydays(value ?? '') == null
                ? 'Enter unique days from 1 to 31'
                : null,
            onChanged: (value) {
              final parsed = _parsePaydays(value);
              if (parsed != null) {
                setState(() {
                  pattern = parsed;
                  firstDue = _nextPayday(_patternBase, pattern);
                  quote = null;
                });
              }
            },
          ),
        ],
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('First due date'),
          subtitle: Text(formatPhilippineDate(firstDue)),
          trailing: const Icon(Icons.event),
          onTap: () async {
            final v = await showDatePicker(
              context: context,
              firstDate: editing ? DateTime(2020) : DateTime.now(),
              lastDate: DateTime(2035),
              initialDate: firstDue,
            );
            if (v != null) setState(() => firstDue = v);
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.gavel_outlined),
          title: Text('Penalties: ${_penalty.typeLabel}'),
          subtitle: Text(
            correctingActive
                ? '${describePenalty(_penalty)} Fixed since the loan was released.'
                : describePenalty(_penalty),
          ),
          trailing: correctingActive
              ? null
              : TextButton(
                  onPressed: () async {
                    final next = await PenaltyPolicyDialog.show(
                      context,
                      initial: _penalty,
                      title: 'Penalties for this loan',
                    );
                    if (next != null) setState(() => penalty = next);
                  },
                  child: const Text('Change'),
                ),
        ),
      ],
    );
  }

  Widget _schedule() {
    if (quote == null) return const Text('Complete terms first.');
    return Column(
      children: [
        _totals(),
        const SizedBox(height: 12),
        // Rendered inline (not a nested scroll view) so the page scrolls as
        // one surface on phones.
        for (final x in quote!.installments)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(child: Text('${x.sequence}')),
            title: Text(formatPhilippineDate(x.dueDate)),
            trailing: Text(
              formatPeso(x.amountCentavos),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }

  Widget _review() => quote == null
      ? const Text('No quote available.')
      : Column(
          children: [
            if (editing) _beforeAfter() else _totals(),
            if (editing) ..._editFields(),
            const SizedBox(height: 16),
            if (!editing)
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Review before confirmation'),
                subtitle: Text(
                  'Interest is based on the original amount lent. Once you confirm the loan, its terms are locked, and any later change is recorded in the history.',
                ),
              ),
          ],
        );
  Widget _beforeAfter() {
    final before = original!.summary, after = quote!;
    final beforeEach = original!.installments.isEmpty
        ? 0
        : original!.installments.first.amountCentavos;
    String names(String id, String fallback) =>
        ref
            .read(borrowersControllerProvider)
            .value
            ?.where((b) => b.id == id)
            .firstOrNull
            ?.displayName ??
        fallback;
    final rows = <(String, String, String)>[
      (
        'Borrower',
        before.borrowerName,
        names(borrowerId!, before.borrowerName),
      ),
      (
        'Principal',
        formatPeso(before.principalCentavos),
        formatPeso(after.principalCentavos),
      ),
      (
        'Monthly rate',
        '${_plain(before.monthlyRateBasisPoints / 100)}%',
        '${_plain(after.monthlyRateBasisPoints / 100)}%',
      ),
      ('Months', '${before.termMonths}', '${after.termMonths}'),
      (
        'Total repayable',
        formatPeso(before.totalCentavos),
        formatPeso(after.totalCentavos),
      ),
      (
        'Installments',
        '${original!.installments.length} × ${formatPeso(beforeEach)}',
        '${after.installments.length} × ${formatPeso(after.installments.first.amountCentavos)}',
      ),
      (
        'First due',
        formatPhilippineDate(originalTerms!.firstDueDate),
        formatPhilippineDate(firstDue),
      ),
    ];
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Table(
          columnWidths: const {
            0: IntrinsicColumnWidth(),
            1: FlexColumnWidth(),
            2: FlexColumnWidth(),
          },
          children: [
            TableRow(
              children: [
                for (final h in ['', 'Before', 'After'])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6, right: 8),
                    child: Text(
                      h,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
            for (final (label, was, now) in rows)
              TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 4,
                    ).copyWith(right: 12),
                    child: Text(label),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      was,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      now,
                      style: TextStyle(
                        fontWeight: was == now
                            ? FontWeight.normal
                            : FontWeight.w700,
                        color: was == now ? null : theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _editFields() {
    final methods =
        ref.watch(operationsConfigProvider).value?.paymentMethods ??
        OperationsConfig.defaults.paymentMethods;
    return [
      if (correctingActive) ...[
        const SizedBox(height: 12),
        Text('Money release', style: Theme.of(context).textTheme.titleSmall),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event),
          title: const Text('Released on'),
          subtitle: Text(
            releaseDate == null ? '—' : formatPhilippineDate(releaseDate!),
          ),
          trailing: const Icon(Icons.edit_calendar_outlined),
          onTap: () async {
            final v = await showDatePicker(
              context: context,
              firstDate: DateTime(2020),
              lastDate: DateTime.now(),
              initialDate: releaseDate ?? DateTime.now(),
            );
            if (v != null) setState(() => releaseDate = v);
          },
        ),
        DropdownButtonFormField<String>(
          initialValue: releaseMethod,
          decoration: const InputDecoration(labelText: 'Released via'),
          items: [
            for (final m in {?releaseMethod, ...methods})
              DropdownMenuItem(value: m, child: Text(m)),
          ],
          onChanged: (value) => setState(() => releaseMethod = value),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: releaseReference,
          decoration: const InputDecoration(
            labelText: 'Release reference (optional)',
          ),
        ),
      ],
      const SizedBox(height: 12),
      TextFormField(
        controller: reason,
        minLines: 1,
        maxLines: 3,
        decoration: InputDecoration(
          labelText: correctingActive
              ? 'Reason for the correction'
              : 'Reason (optional)',
          hintText: 'e.g. Amount typed wrong, was 12,000',
          helperText: 'Kept in the loan history.',
        ),
      ),
    ];
  }

  Widget _totals() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _row('Principal', formatPeso(quote!.principalCentavos)),
          _row('Flat interest', formatPeso(quote!.interestCentavos)),
          _row('Total repayable', formatPeso(quote!.totalCentavos)),
          _row(
            'Installments',
            '${quote!.installments.length} × ${formatPeso(quote!.installments.first.amountCentavos)}',
          ),
        ],
      ),
    ),
  );
  Widget _row(String a, String b) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(a),
        Text(b, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
  String? _positive(String? v) =>
      (double.tryParse(v ?? '') ?? 0) > 0 ? null : 'Enter a positive value';
  String? _nonNegative(String? v) =>
      (double.tryParse(v ?? '') ?? -1) >= 0 ? null : 'Enter zero or more';
}

DateTime _nextPayday(DateTime now, List<int> pattern) {
  final start = DateTime(now.year, now.month, now.day);
  for (var offset = 0; offset < 62; offset++) {
    final candidate = start.add(Duration(days: offset));
    final lastDay = DateTime(candidate.year, candidate.month + 1, 0).day;
    if (pattern.any(
      (day) => candidate.day == (day > lastDay ? lastDay : day),
    )) {
      return candidate;
    }
  }
  throw StateError('No payday found');
}

bool _sameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool _samePattern(List<int> a, List<int> b) =>
    a.length == b.length &&
    List.generate(a.length, (i) => a[i] == b[i]).every((v) => v);

String _ordinal(int day) {
  final mod100 = day % 100;
  final suffix = mod100 >= 11 && mod100 <= 13
      ? 'th'
      : switch (day % 10) {
          1 => 'st',
          2 => 'nd',
          3 => 'rd',
          _ => 'th',
        };
  return '$day$suffix';
}

List<int>? _parsePaydays(String value) {
  final days = value
      .split(',')
      .map((part) => int.tryParse(part.trim()))
      .toList();
  if (days.isEmpty || days.any((day) => day == null || day < 1 || day > 31)) {
    return null;
  }
  final result = days.cast<int>().toSet().toList()..sort();
  return result.length == days.length ? result : null;
}
