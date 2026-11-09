import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import '../../core/formatting.dart';
import '../../core/undo/undo_controller.dart';
import '../../core/widgets/window_title.dart';
import '../../domain/models/models.dart';
import '../loans/loans_controller.dart';

/// Plain words for a penalty policy (Settings, loan page, agreement).
String describePenalty(PenaltyPolicy p) {
  final start = p.graceDays == 0
      ? 'from the due date'
      : 'starting ${p.graceDays} day${p.graceDays == 1 ? '' : 's'} after the due date';
  return switch (p.mode) {
    'fixed' =>
      '${formatPeso(p.amountCentavos ?? 0)} for each payday cutoff an '
          'installment stays unpaid, $start.',
    'percentage' =>
      '${((p.rateBasisPoints ?? 0) / 100).toStringAsFixed(2)}% of the unpaid '
          'installment for each payday cutoff it stays unpaid, $start.',
    'manual' => 'Charged by hand on a late installment, with a reason.',
    _ => 'No penalties.',
  };
}

/// The organization's default policy for new loans (Settings).
final penaltyDefaultProvider = FutureProvider<PenaltyPolicy>((ref) async {
  if (!AppConfig.hasSupabase ||
      Supabase.instance.client.auth.currentUser == null) {
    return PenaltyPolicy.none;
  }
  final client = Supabase.instance.client;
  final membership = await client
      .from('organization_members')
      .select('organization_id')
      .eq('user_id', client.auth.currentUser!.id)
      .eq('status', 'active')
      .limit(1)
      .single();
  final row = await client
      .from('organizations')
      .select('policy_preferences')
      .eq('id', membership['organization_id'] as String)
      .single();
  return PenaltyPolicy.fromJson(
    (row['policy_preferences'] as Map?)?['penalty_default'],
  );
});

/// Saves the default policy (owner), keeping the other policy settings.
Future<void> savePenaltyDefault(PenaltyPolicy policy) async {
  final client = Supabase.instance.client;
  final membership = await client
      .from('organization_members')
      .select('organization_id')
      .eq('user_id', client.auth.currentUser!.id)
      .eq('status', 'active')
      .limit(1)
      .single();
  final orgId = membership['organization_id'] as String;
  final row = await client
      .from('organizations')
      .select('policy_preferences')
      .eq('id', orgId)
      .single();
  final prefs = Map<String, dynamic>.from(
    (row['policy_preferences'] as Map?) ?? const {},
  )..['penalty_default'] = policy.toJson();
  await client
      .from('organizations')
      .update({'policy_preferences': prefs})
      .eq('id', orgId);
}

/// Choose a penalty type, amount or rate, and grace days.
class PenaltyPolicyDialog extends StatefulWidget {
  const PenaltyPolicyDialog({
    super.key,
    required this.initial,
    required this.title,
    required this.note,
  });
  final PenaltyPolicy initial;
  final String title, note;

  static Future<PenaltyPolicy?> show(
    BuildContext context, {
    required PenaltyPolicy initial,
    String title = 'Penalties',
    String note = '',
  }) => showDialog<PenaltyPolicy>(
    context: context,
    builder: (_) =>
        PenaltyPolicyDialog(initial: initial, title: title, note: note),
  );

  @override
  State<PenaltyPolicyDialog> createState() => _PenaltyPolicyDialogState();
}

class _PenaltyPolicyDialogState extends State<PenaltyPolicyDialog> {
  final key = GlobalKey<FormState>();
  late String mode = widget.initial.mode;
  late final amount = TextEditingController(
    text: widget.initial.amountCentavos == null
        ? ''
        : (widget.initial.amountCentavos! / 100).toStringAsFixed(2),
  );
  late final rate = TextEditingController(
    text: widget.initial.rateBasisPoints == null
        ? ''
        : (widget.initial.rateBasisPoints! / 100).toString(),
  );
  late final grace = TextEditingController(text: '${widget.initial.graceDays}');

  @override
  void dispose() {
    amount.dispose();
    rate.dispose();
    grace.dispose();
    super.dispose();
  }

  PenaltyPolicy get _policy => PenaltyPolicy(
    mode: mode,
    amountCentavos: mode == 'fixed'
        ? ((double.tryParse(amount.text) ?? 0) * 100).round()
        : null,
    rateBasisPoints: mode == 'percentage'
        ? ((double.tryParse(rate.text) ?? 0) * 100).round()
        : null,
    graceDays: int.tryParse(grace.text) ?? 3,
  );

  @override
  Widget build(BuildContext context) {
    final decimal = [
      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
    ];
    return AlertDialog(
      title: WindowTitle(Text(widget.title)),
      content: SizedBox(
        width: 480,
        child: Form(
          key: key,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.note.isNotEmpty) ...[
                  Text(widget.note),
                  const SizedBox(height: 8),
                ],
                RadioGroup<String>(
                  groupValue: mode,
                  onChanged: (v) => setState(() => mode = v ?? mode),
                  child: Column(
                    children: [
                      for (final (value, label, help) in const [
                        ('none', 'None', 'No penalties on late payments.'),
                        (
                          'fixed',
                          'Fixed amount',
                          'A set amount at each payday cutoff while late.',
                        ),
                        (
                          'percentage',
                          'Percentage of overdue',
                          'A % of the unpaid installment at each cutoff while late.',
                        ),
                        (
                          'manual',
                          'Manual',
                          'Nothing automatic; you add a penalty when you decide to.',
                        ),
                      ])
                        RadioListTile<String>(
                          value: value,
                          contentPadding: EdgeInsets.zero,
                          title: Text(label),
                          subtitle: Text(help),
                        ),
                    ],
                  ),
                ),
                if (mode == 'fixed')
                  TextFormField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: decimal,
                    decoration: const InputDecoration(
                      labelText: 'Amount per cutoff',
                      prefixText: '₱ ',
                    ),
                    validator: (v) => (double.tryParse(v ?? '') ?? 0) > 0
                        ? null
                        : 'Enter an amount',
                  ),
                if (mode == 'percentage')
                  TextFormField(
                    controller: rate,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: decimal,
                    decoration: const InputDecoration(
                      labelText: 'Percent of the unpaid installment',
                      suffixText: '%',
                    ),
                    validator: (v) {
                      final n = double.tryParse(v ?? '') ?? 0;
                      return n > 0 && n <= 100 ? null : 'Enter 0.01 to 100';
                    },
                  ),
                if (mode == 'fixed' || mode == 'percentage') ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: grace,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Grace days after the due date',
                      helperText: 'The first penalty is charged after this',
                    ),
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      return n != null && n >= 0 && n <= 60
                          ? null
                          : 'Enter 0 to 60';
                    },
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  'Payments pay penalties first, then interest, then '
                  'principal. Penalties apply only to loans created with them, '
                  'never to existing loans.',
                  style: Theme.of(context).textTheme.bodySmall,
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
            Navigator.pop(context, _policy);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Loan page: the loan's penalty policy, its charges (with Waive), and Add
/// penalty for loans that allow it.
class LoanPenaltiesCard extends ConsumerStatefulWidget {
  const LoanPenaltiesCard({super.key, required this.loan, this.onChanged});
  final LoanDetail loan;
  final VoidCallback? onChanged;

  @override
  ConsumerState<LoanPenaltiesCard> createState() => _LoanPenaltiesCardState();
}

class _LoanPenaltiesCardState extends ConsumerState<LoanPenaltiesCard> {
  late Future<(PenaltyPolicy, List<PenaltyCharge>)> data = _load();

  Future<(PenaltyPolicy, List<PenaltyCharge>)> _load() async {
    final loans = ref.read(loansControllerProvider.notifier);
    final id = widget.loan.summary.id;
    return (
      await loans.fetchPenaltyPolicy(id),
      await loans.fetchPenaltyCharges(id),
    );
  }

  void _reload() {
    setState(() => data = _load());
    widget.onChanged?.call();
  }

  Future<void> _waive(PenaltyCharge charge) async {
    final reason = await _askText(
      context,
      title: 'Waive ${formatPeso(charge.amountCentavos)} penalty?',
      label: 'Reason',
      hint: 'e.g. First late payment, forgiven',
    );
    if (reason == null || !mounted) return;
    final undo = undoOf(context);
    try {
      await ref
          .read(loansControllerProvider.notifier)
          .waivePenalty(charge.id, reason);
      undo.record('Penalty waived. It is kept in the history.');
      _reload();
    } catch (e) {
      undo.record(_message(e));
    }
  }

  Future<void> _add() async {
    final unpaid = [
      for (final i in widget.loan.installments)
        if (i.outstandingCentavos > 0) i,
    ];
    if (unpaid.isEmpty) return;
    final result = await showDialog<(int, int, String)>(
      context: context,
      builder: (_) => _AddPenaltyDialog(installments: unpaid),
    );
    if (result == null || !mounted) return;
    final undo = undoOf(context);
    try {
      await ref
          .read(loansControllerProvider.notifier)
          .addPenalty(
            loanId: widget.loan.summary.id,
            sequence: result.$1,
            amountCentavos: result.$2,
            note: result.$3,
          );
      undo.record('Penalty added.');
      _reload();
    } catch (e) {
      undo.record(_message(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<(PenaltyPolicy, List<PenaltyCharge>)>(
      future: data,
      builder: (context, snapshot) {
        final policy = snapshot.data?.$1;
        final charges = snapshot.data?.$2 ?? const <PenaltyCharge>[];
        if (policy == null) return const SizedBox.shrink();
        final active = charges.where((c) => !c.waived);
        final total = active.fold(0, (s, c) => s + c.amountCentavos);
        final canAdd = policy.charges && widget.loan.summary.status == 'active';
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.gavel_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Penalties: ${policy.typeLabel}',
                            style: theme.textTheme.titleMedium,
                          ),
                          Text(
                            describePenalty(policy),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (canAdd)
                      OutlinedButton.icon(
                        onPressed: _add,
                        icon: const Icon(Icons.add),
                        label: const Text('Add penalty…'),
                      ),
                  ],
                ),
                if (charges.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Charged so far: ${formatPeso(total)}',
                    style: theme.textTheme.labelLarge,
                  ),
                  for (final c in charges)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${formatPhilippineDate(c.chargeDate)} · '
                        'installment ${c.sequence} · '
                        '${formatPeso(c.amountCentavos)}',
                        style: c.waived
                            ? const TextStyle(
                                decoration: TextDecoration.lineThrough,
                              )
                            : null,
                      ),
                      subtitle: Text(
                        [
                          c.source == 'manual' ? 'Added by hand' : 'Automatic',
                          if ((c.note ?? '').isNotEmpty) c.note!,
                          if (c.waived) 'Waived: ${c.waiveReason ?? ''}',
                        ].join(' · '),
                      ),
                      trailing: c.waived
                          ? null
                          : TextButton(
                              onPressed: () => _waive(c),
                              child: const Text('Waive…'),
                            ),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AddPenaltyDialog extends StatefulWidget {
  const _AddPenaltyDialog({required this.installments});
  final List<Installment> installments;
  @override
  State<_AddPenaltyDialog> createState() => _AddPenaltyDialogState();
}

class _AddPenaltyDialogState extends State<_AddPenaltyDialog> {
  final key = GlobalKey<FormState>();
  late int sequence = widget.installments.first.sequence;
  final amount = TextEditingController();
  final note = TextEditingController();

  @override
  void dispose() {
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    // Scrolls so fields never hide under the buttons (phones, keyboard).
    scrollable: true,
    title: const WindowTitle(Text('Add penalty')),
    content: SizedBox(
      width: 440,
      child: Form(
        key: key,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              initialValue: sequence,
              decoration: const InputDecoration(labelText: 'Installment'),
              items: [
                for (final i in widget.installments)
                  DropdownMenuItem(
                    value: i.sequence,
                    child: Text(
                      '${i.sequence} · due ${formatPhilippineDate(i.dueDate)} · '
                      '${formatPeso(i.outstandingCentavos)} unpaid',
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => sequence = v ?? sequence),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '₱ ',
              ),
              validator: (v) => (double.tryParse(v ?? '') ?? 0) > 0
                  ? null
                  : 'Enter an amount',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: note,
              decoration: const InputDecoration(
                labelText: 'Reason',
                hintText: 'e.g. Missed payment after two reminders',
              ),
              validator: (v) => (v?.trim().length ?? 0) >= 3
                  ? null
                  : 'Enter a short reason (kept in the history)',
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
          if (!key.currentState!.validate()) return;
          Navigator.pop(context, (
            sequence,
            (double.parse(amount.text) * 100).round(),
            note.text.trim(),
          ));
        },
        child: const Text('Add Penalty'),
      ),
    ],
  );
}

Future<String?> _askText(
  BuildContext context, {
  required String title,
  required String label,
  String hint = '',
}) {
  final controller = TextEditingController();
  final key = GlobalKey<FormState>();
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      // Scrolls so fields never hide under the buttons (phones, keyboard).
      scrollable: true,
      title: WindowTitle(Text(title)),
      content: Form(
        key: key,
        child: TextFormField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label, hintText: hint),
          validator: (v) => (v?.trim().length ?? 0) >= 3
              ? null
              : 'Enter a short reason (kept in the history)',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!key.currentState!.validate()) return;
            Navigator.pop(c, controller.text.trim());
          },
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
}

String _message(Object e) =>
    e is PostgrestException ? e.message : 'That could not be saved. Try again.';
