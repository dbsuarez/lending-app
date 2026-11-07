import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/formatting.dart';
import '../../domain/models/models.dart';
import '../../domain/services/loan_calculator.dart';
import '../borrowers/borrowers_controller.dart';
import '../settings/operations_config_provider.dart';
import 'loans_controller.dart';

class LoanFormScreen extends ConsumerStatefulWidget {
  const LoanFormScreen({super.key});
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

  @override
  void initState() {
    super.initState();
    firstDue = _nextPayday(DateTime.now(), pattern);
  }

  @override
  void dispose() {
    principal.dispose();
    term.dispose();
    rate.dispose();
    customPaydays.dispose();
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'First due date must match the selected payday pattern.',
          ),
        ),
      );
      return;
    }
    setState(() => quote = result);
  }

  Future<void> _saveDraft() async {
    final currentQuote = quote;
    final borrowers = ref.read(borrowersControllerProvider).value;
    if (currentQuote == null || borrowers == null || borrowerId == null) return;
    final borrower = borrowers.firstWhere((item) => item.id == borrowerId);
    setState(() => saving = true);
    final saved = await ref
        .read(loansControllerProvider.notifier)
        .createDraft(
          borrower: borrower,
          quote: currentQuote,
          firstDueDate: firstDue,
          paydayPattern: pattern,
        );
    if (!mounted) return;
    setState(() => saving = false);
    if (saved) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Loan draft created.')));
      context.go('/loans');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Loan draft could not be created. Try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: key,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Create loan',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const Text(
                'A draft does not disburse funds or create a confirmed obligation.',
              ),
              const SizedBox(height: 20),
              Stepper(
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
                        : Text(step == 2 ? 'Create Draft' : 'Continue'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
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
              firstDue = _nextPayday(DateTime.now(), pattern);
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
                  firstDue = _nextPayday(DateTime.now(), pattern);
                  quote = null;
                });
              }
            },
          ),
        ],
        const SizedBox(height: 12),
        ListTile(
          title: const Text('First due date'),
          subtitle: Text(formatPhilippineDate(firstDue)),
          trailing: const Icon(Icons.event),
          onTap: () async {
            final v = await showDatePicker(
              context: context,
              firstDate: DateTime.now(),
              lastDate: DateTime(2035),
              initialDate: firstDue,
            );
            if (v != null) setState(() => firstDue = v);
          },
        ),
        const ListTile(
          leading: Icon(Icons.gavel_outlined),
          title: Text('Penalty policy: None'),
          subtitle: Text('Default. No penalties are assessed or backdated.'),
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
        SizedBox(
          height: 320,
          child: ListView.builder(
            itemCount: quote!.installments.length,
            itemBuilder: (_, i) {
              final x = quote!.installments[i];
              return ListTile(
                leading: CircleAvatar(child: Text('${x.sequence}')),
                title: Text(formatPhilippineDate(x.dueDate)),
                trailing: Text(
                  formatPeso(x.amountCentavos),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _review() => quote == null
      ? const Text('No quote available.')
      : Column(
          children: [
            _totals(),
            const SizedBox(height: 16),
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Review before confirmation'),
              subtitle: Text(
                'Interest uses the original principal. Confirmed terms will be immutable; changes require an auditable event.',
              ),
            ),
          ],
        );
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
