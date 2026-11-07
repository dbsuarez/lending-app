import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/formatting.dart';
import '../../core/undo/undo_controller.dart';
import '../../core/widgets/info_tip.dart';
import '../../domain/models/models.dart';
import '../../domain/services/extension_preview.dart';

/// "What would they owe if I extend to now?" Read-only: nothing is saved.
class ExtensionPreviewDialog extends StatefulWidget {
  const ExtensionPreviewDialog(this.loan, {super.key, this.today});
  final LoanDetail loan;

  /// Injected in tests; defaults to the current date.
  final DateTime? today;

  @override
  State<ExtensionPreviewDialog> createState() => _ExtensionPreviewDialogState();
}

class _ExtensionPreviewDialogState extends State<ExtensionPreviewDialog> {
  static const _calc = ExtensionCalculator();
  late DateTime date = _dateOnly(widget.today ?? DateTime.now());
  var base = ExtensionInterestBase.unpaidPrincipal;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final loan = widget.loan;
    final byDate = _calc.asOfDate(loan, date, base: base);
    final byCutoff = _calc.asOfCutoff(loan, date, base: base);
    final rate = loan.summary.monthlyRateBasisPoints / 100;
    final compact = MediaQuery.sizeOf(context).width < 600;
    final options = [
      _Option(
        'As of ${formatPhilippineDate(byDate.asOf)}',
        'Part of a month is pro-rated by days.',
        byDate,
      ),
      _Option(
        'At payday cutoff ${formatPhilippineDate(byCutoff.asOf)}',
        'Whole pay periods only, up to the next cutoff.',
        byCutoff,
      ),
    ];
    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 40,
        vertical: 24,
      ),
      title: const TitleWithInfo('Extension preview', 'extension_preview'),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Preview only. Nothing is saved or sent to the borrower.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${loan.summary.borrowerName} · final due date '
                '${formatPhilippineDate(byDate.finalDueDate)} · '
                '${rate.toStringAsFixed(rate % 1 == 0 ? 0 : 2)}% a month',
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Compute up to'),
                subtitle: Text(formatPhilippineDate(date)),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: _pickDate,
              ),
              Row(
                children: [
                  const Flexible(child: Text('Charge extra interest on')),
                  const SizedBox(width: 4),
                  const InfoTip('extension_base', size: 16),
                ],
              ),
              const SizedBox(height: 6),
              SegmentedButton<ExtensionInterestBase>(
                // Short labels and no check icon so it fits on phones.
                showSelectedIcon: !compact,
                segments: [
                  ButtonSegment(
                    value: ExtensionInterestBase.unpaidPrincipal,
                    label: Text(compact ? 'Unpaid' : 'Unpaid principal'),
                  ),
                  ButtonSegment(
                    value: ExtensionInterestBase.originalPrincipal,
                    label: Text(compact ? 'Original' : 'Original principal'),
                  ),
                ],
                selected: {base},
                onSelectionChanged: (value) =>
                    setState(() => base = value.single),
              ),
              const SizedBox(height: 14),
              if (byDate.extensionMonths == 0 && byCutoff.extensionMonths == 0)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Text(
                    'This date is not past the final due date, so no extra '
                    'interest applies yet.',
                  ),
                ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final option in options)
                    SizedBox(
                      width: compact ? double.infinity : 330,
                      child: _PreviewCard(option: option, ratePercent: rate),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Uses verified payments only; payments still pending '
                'verification are not subtracted.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => _copy(options),
          icon: const Icon(Icons.copy),
          label: const Text('Copy summary'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
      initialDate: date,
    );
    if (picked != null) setState(() => date = _dateOnly(picked));
  }

  Future<void> _copy(List<_Option> options) async {
    final loan = widget.loan;
    final lines = <String>[
      'Loan of ${loan.summary.borrowerName} '
          '(LN-${loan.summary.id.substring(0, 8).toUpperCase()})',
      for (final option in options) ...[
        '',
        option.title,
        '  Unpaid from schedule: '
            '${formatPeso(option.preview.unpaidScheduleCentavos)}',
        '  Extra interest (${_months(option.preview.extensionMonths)}): '
            '${formatPeso(option.preview.extensionInterestCentavos)}',
        '  Total: ${formatPeso(option.preview.totalCentavos)}',
      ],
    ];
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (mounted) undoOf(context).notify('Summary copied.');
  }
}

String _months(double months) {
  final text = months == months.roundToDouble()
      ? months.toStringAsFixed(0)
      : months.toStringAsFixed(2);
  return '$text ${months == 1 ? 'month' : 'months'}';
}

class _Option {
  const _Option(this.title, this.note, this.preview);
  final String title, note;
  final ExtensionPreview preview;
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.option, required this.ratePercent});
  final _Option option;
  final double ratePercent;

  @override
  Widget build(BuildContext context) {
    final p = option.preview;
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(option.title, style: theme.textTheme.titleMedium),
            Text(option.note, style: theme.textTheme.bodySmall),
            const Divider(height: 20),
            _row('Unpaid principal', p.unpaidPrincipalCentavos),
            _row(
              'Unpaid interest (original schedule)',
              p.unpaidInterestCentavos,
            ),
            const SizedBox(height: 6),
            Text(
              '${_months(p.extensionMonths)} past the final due date',
              style: theme.textTheme.bodySmall,
            ),
            _row(
              'Extra interest: ${ratePercent.toStringAsFixed(ratePercent % 1 == 0 ? 0 : 2)}% '
              '× ${formatPeso(p.interestBaseCentavos)} × '
              '${p.extensionMonths.toStringAsFixed(2)}',
              p.extensionInterestCentavos,
            ),
            const Divider(height: 20),
            _row('Would owe', p.totalCentavos, bold: true),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, int centavos, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 12),
        Text(
          formatPeso(centavos),
          style: TextStyle(
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            fontSize: bold ? 17 : null,
          ),
        ),
      ],
    ),
  );
}
