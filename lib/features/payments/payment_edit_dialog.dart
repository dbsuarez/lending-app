import 'package:flutter/material.dart';
import '../../core/formatting.dart';
import '../../domain/models/models.dart';

/// Lets the user pick a date, then a time, starting from [initial].
/// Returns null when cancelled. Future dates are not offered.
Future<DateTime?> pickReceivedAt(BuildContext context, DateTime initial) async {
  final now = DateTime.now();
  final date = await showDatePicker(
    context: context,
    firstDate: DateTime(2020),
    lastDate: now,
    initialDate: initial.isAfter(now) ? now : initial,
    helpText: 'When was it received?',
  );
  if (date == null || !context.mounted) return null;
  // The time is optional: closing this picker keeps the chosen date with
  // the previous time instead of discarding the date.
  final time =
      await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(initial),
        helpText: 'Time received (optional, approximate is fine)',
      ) ??
      TimeOfDay.fromDateTime(initial);
  final picked = DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  );
  return picked.isAfter(now) ? now : picked;
}

/// A "Received at" row that opens the date and time pickers.
class ReceivedAtField extends StatelessWidget {
  const ReceivedAtField({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const Icon(Icons.schedule),
    title: const Text('Received at'),
    subtitle: Text(formatPhilippineDateTime(value)),
    trailing: const Icon(Icons.edit_calendar_outlined),
    onTap: () async {
      final picked = await pickReceivedAt(context, value);
      if (picked != null) onChanged(picked);
    },
  );
}

class PaymentCorrectionValues {
  const PaymentCorrectionValues({
    required this.receivedAt,
    required this.method,
    required this.reference,
    required this.reason,
  });
  final DateTime receivedAt;
  final String method, reference, reason;
}

/// Edit when a payment was received, its method and reference. The amount
/// is not editable here: a wrong amount is reversed and recorded again.
class PaymentEditDialog extends StatefulWidget {
  const PaymentEditDialog({
    super.key,
    required this.payment,
    required this.methods,
  });
  final PaymentSummary payment;
  final List<String> methods;

  static Future<PaymentCorrectionValues?> show(
    BuildContext context,
    PaymentSummary payment,
    List<String> methods,
  ) => showDialog<PaymentCorrectionValues>(
    context: context,
    builder: (_) => PaymentEditDialog(payment: payment, methods: methods),
  );

  @override
  State<PaymentEditDialog> createState() => _PaymentEditDialogState();
}

class _PaymentEditDialogState extends State<PaymentEditDialog> {
  final key = GlobalKey<FormState>();
  late final reference = TextEditingController(text: widget.payment.reference);
  final reason = TextEditingController();
  late DateTime receivedAt = widget.payment.receivedAt.toLocal();
  late String method = widget.payment.method;

  bool get _isCash => widget.payment.method.toLowerCase() == 'cash';

  /// Cash and non-cash cannot be swapped here (see the server rule).
  List<String> get _methods => {
    widget.payment.method,
    for (final m in widget.methods)
      if ((m.toLowerCase() == 'cash') == _isCash) m,
  }.toList();

  @override
  void dispose() {
    reference.dispose();
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit payment details'),
    content: SizedBox(
      width: 480,
      child: Form(
        key: key,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${widget.payment.borrowerName.isEmpty ? '' : '${widget.payment.borrowerName} · '}'
                '${formatPeso(widget.payment.amountCentavos)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Changing these does not change how the money was applied or '
                'any balance. If the amount is wrong, reverse the payment and '
                'record it again.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              ReceivedAtField(
                value: receivedAt,
                onChanged: (value) => setState(() => receivedAt = value),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: method,
                decoration: const InputDecoration(labelText: 'Method'),
                items: [
                  for (final item in _methods)
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
              TextFormField(
                controller: reason,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Reason for the change',
                  hintText: 'e.g. Paid on Oct 20, recorded late',
                ),
                validator: (value) => (value?.trim().length ?? 0) >= 3
                    ? null
                    : 'Enter a short reason (kept in the history)',
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
            PaymentCorrectionValues(
              receivedAt: receivedAt,
              method: method,
              reference: reference.text.trim(),
              reason: reason.text.trim(),
            ),
          );
        },
        child: const Text('Save Changes'),
      ),
    ],
  );
}
