import 'package:flutter/material.dart';
import '../../core/formatting.dart';
import '../../core/undo/undo_controller.dart';
import '../../domain/models/models.dart';
import 'payments_controller.dart';

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

/// Saves what [PaymentEditDialog] returned: a correction (with undo) when
/// the date, method or reference changed, and the late reason when it
/// changed. [onChanged] runs after anything was saved or undone.
Future<void> applyPaymentEdit({
  required PaymentsController payments,
  required UndoController undo,
  required PaymentSummary payment,
  required PaymentCorrectionValues values,
  VoidCallback? onChanged,
}) async {
  String? correctionId;
  if (values.detailsChanged) {
    correctionId = await payments.correctDetails(
      payment,
      receivedAt: values.receivedAt,
      method: values.method,
      reference: values.reference,
      reason: values.reason,
    );
    if (correctionId == null) {
      undo.record(
        'Payment could not be updated: '
        '${payments.lastCorrectionError ?? 'try again.'}',
      );
      return;
    }
  }
  var lateSaved = true;
  if (values.lateReasonChanged) {
    lateSaved = await payments.setLateReason(payment, values.lateReason);
  }
  onChanged?.call();
  if (!lateSaved) {
    undo.record(
      correctionId == null
          ? 'The late-payment reason could not be saved. Try again.'
          : 'Payment details updated, but the late-payment reason could not '
                'be saved. Try again.',
    );
  } else if (correctionId != null) {
    final id = correctionId;
    undo.offer(
      'Payment details updated. The change is in the history.',
      () async {
        final undone = await payments.undoCorrection(id);
        if (undone) onChanged?.call();
        return undone;
      },
    );
  } else {
    undo.notify(
      values.lateReason.isEmpty
          ? 'Late-payment reason removed.'
          : 'Late-payment reason saved.',
    );
  }
}

/// A small "late" marker with the reason as its tooltip.
class LateReasonMarker extends StatelessWidget {
  const LateReasonMarker(this.reason, {super.key});
  final String? reason;
  @override
  Widget build(BuildContext context) {
    final text = reason;
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    return Tooltip(
      message: 'Late: $text',
      child: Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Icon(
          Icons.schedule,
          size: 16,
          color: Theme.of(context).colorScheme.tertiary,
        ),
      ),
    );
  }
}

/// Common reasons, offered as one-tap choices.
const lateReasonChoices = [
  'Payday was delayed',
  'Medical or family emergency',
  'Bank or transfer delay',
  'Forgot / overlooked',
  'Paid in parts',
];

/// How many days after its due date a payment received on [receivedAt] is,
/// judged by the oldest installment still unpaid. Null when not late.
({int days, DateTime due})? lateness(LoanDetail loan, DateTime receivedAt) {
  final unpaid = [
    for (final i in loan.installments)
      if (i.outstandingCentavos > 0) i,
  ]..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  if (unpaid.isEmpty) return null;
  final due = unpaid.first.dueDate;
  final day = DateTime(receivedAt.year, receivedAt.month, receivedAt.day);
  final days = day.difference(DateTime(due.year, due.month, due.day)).inDays;
  return days > 0 ? (days: days, due: due) : null;
}

/// Optional "why was this late" text with quick picks.
class LateReasonField extends StatelessWidget {
  const LateReasonField({super.key, required this.controller, this.label});
  final TextEditingController controller;
  final String? label;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextFormField(
        controller: controller,
        minLines: 1,
        maxLines: 3,
        decoration: InputDecoration(
          labelText: label ?? 'Reason for late payment (optional)',
          hintText: 'e.g. Payday was delayed',
        ),
      ),
      const SizedBox(height: 6),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final choice in lateReasonChoices)
            ActionChip(
              label: Text(choice),
              visualDensity: VisualDensity.compact,
              onPressed: () => controller.text = choice,
            ),
        ],
      ),
    ],
  );
}

class PaymentCorrectionValues {
  const PaymentCorrectionValues({
    required this.receivedAt,
    required this.method,
    required this.reference,
    required this.reason,
    required this.detailsChanged,
    required this.lateReason,
    required this.lateReasonChanged,
  });
  final DateTime receivedAt;
  final String method, reference, reason, lateReason;

  /// Date, method or reference changed (needs a correction with a reason).
  final bool detailsChanged;
  final bool lateReasonChanged;
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
  late final lateReason = TextEditingController(
    text: widget.payment.lateReason ?? '',
  );
  late DateTime receivedAt = widget.payment.receivedAt.toLocal();
  late String method = widget.payment.method;

  bool get _detailsChanged =>
      !receivedAt.isAtSameMomentAs(widget.payment.receivedAt.toLocal()) ||
      method != widget.payment.method ||
      reference.text.trim() != widget.payment.reference;

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
    lateReason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit payment'),
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
                  helperText:
                      'Needed when the date, method or reference '
                      'changes',
                ),
                validator: (value) =>
                    !_detailsChanged || (value?.trim().length ?? 0) >= 3
                    ? null
                    : 'Enter a short reason (kept in the history)',
              ),
              const SizedBox(height: 16),
              LateReasonField(controller: lateReason),
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
          final late = lateReason.text.trim();
          final lateChanged = late != (widget.payment.lateReason ?? '');
          if (!_detailsChanged && !lateChanged) {
            Navigator.pop(context);
            return;
          }
          Navigator.pop(
            context,
            PaymentCorrectionValues(
              receivedAt: receivedAt,
              method: method,
              reference: reference.text.trim(),
              reason: reason.text.trim(),
              detailsChanged: _detailsChanged,
              lateReason: late,
              lateReasonChanged: lateChanged,
            ),
          );
        },
        child: const Text('Save Changes'),
      ),
    ],
  );
}
