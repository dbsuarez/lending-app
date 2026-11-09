import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/formatting.dart';
import '../../core/undo/undo_controller.dart';
import '../../core/widgets/window_title.dart';
import '../../domain/models/models.dart';
import '../settings/operations_config_provider.dart';
import 'loans_controller.dart';

/// Settle each open overpayment on [loan]: refunded or kept.
Future<void> settleOverpayments(
  BuildContext context,
  LoanDetail loan,
  VoidCallback? onChanged,
) async {
  final open = [
    for (final p in loan.payments)
      if (p.unappliedCentavos > 0 && p.id != null) p,
  ];
  if (open.isEmpty) return;
  final container = ProviderScope.containerOf(context, listen: false);
  final methods =
      container.read(operationsConfigProvider).value?.paymentMethods ??
      OperationsConfig.defaults.paymentMethods;
  for (final payment in open) {
    if (!context.mounted) return;
    final values = await showDialog<_SettleValues>(
      context: context,
      builder: (_) => _SettleDialog(payment: payment, methods: methods),
    );
    if (values == null || !context.mounted) return;
    final undo = undoOf(context);
    final loans = container.read(loansControllerProvider.notifier);
    try {
      await loans.settleOverpayment(
        paymentId: payment.id!,
        kind: values.kind,
        settledOn: values.date,
        method: values.kind == 'refunded' ? values.method : null,
        reference: values.reference,
        reason: values.reason,
      );
      onChanged?.call();
      undo.offer(
        values.kind == 'refunded'
            ? '${formatPeso(payment.unappliedCentavos)} recorded as refunded.'
            : '${formatPeso(payment.unappliedCentavos)} recorded as kept.',
        () async {
          final undone = await loans.undoOverpaymentSettlement(payment.id!);
          if (undone) onChanged?.call();
          return undone;
        },
      );
    } catch (e) {
      undo.record(
        e is PostgrestException ? e.message : 'Could not save. Try again.',
      );
      return;
    }
  }
}

class _SettleValues {
  const _SettleValues(
    this.kind,
    this.date,
    this.method,
    this.reference,
    this.reason,
  );
  final String kind;
  final DateTime date;
  final String? method, reference, reason;
}

class _SettleDialog extends StatefulWidget {
  const _SettleDialog({required this.payment, required this.methods});
  final ReceivedPayment payment;
  final List<String> methods;
  @override
  State<_SettleDialog> createState() => _SettleDialogState();
}

class _SettleDialogState extends State<_SettleDialog> {
  final key = GlobalKey<FormState>();
  String kind = 'refunded';
  DateTime date = DateTime.now();
  late String method = widget.methods.first;
  final reference = TextEditingController();
  final reason = TextEditingController();

  @override
  void dispose() {
    reference.dispose();
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: WindowTitle(
      Text(
        'Settle ${formatPeso(widget.payment.unappliedCentavos)} overpayment',
      ),
    ),
    content: SizedBox(
      width: 460,
      child: Form(
        key: key,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'From the payment of ${formatPeso(widget.payment.amountCentavos)} '
              'on ${formatPhilippineDate(widget.payment.receivedOn)}.',
            ),
            RadioGroup<String>(
              groupValue: kind,
              onChanged: (v) => setState(() => kind = v ?? kind),
              child: const Column(
                children: [
                  RadioListTile<String>(
                    value: 'refunded',
                    contentPadding: EdgeInsets.zero,
                    title: Text('Refunded to the borrower'),
                    subtitle: Text('You gave the extra back.'),
                  ),
                  RadioListTile<String>(
                    value: 'kept',
                    contentPadding: EdgeInsets.zero,
                    title: Text('Kept'),
                    subtitle: Text(
                      'E.g. the borrower said keep the change. A reason is '
                      'required.',
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(kind == 'refunded' ? 'Refunded on' : 'Decided on'),
              trailing: Text(formatPhilippineDate(date)),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                  initialDate: date,
                );
                if (picked != null) setState(() => date = picked);
              },
            ),
            if (kind == 'refunded') ...[
              DropdownButtonFormField<String>(
                initialValue: method,
                decoration: const InputDecoration(labelText: 'Refunded via'),
                items: [
                  for (final m in widget.methods)
                    DropdownMenuItem(value: m, child: Text(m)),
                ],
                onChanged: (v) => setState(() => method = v ?? method),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: reference,
                decoration: const InputDecoration(
                  labelText: 'Reference (optional)',
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: reason,
              decoration: InputDecoration(
                labelText: kind == 'kept' ? 'Reason' : 'Note (optional)',
                hintText: kind == 'kept'
                    ? 'e.g. Borrower said keep the change'
                    : '',
              ),
              validator: (v) => kind == 'kept' && (v?.trim().length ?? 0) < 3
                  ? 'Enter a short reason (kept in the history)'
                  : null,
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
          Navigator.pop(
            context,
            _SettleValues(
              kind,
              date,
              method,
              reference.text.trim(),
              reason.text.trim(),
            ),
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
}
