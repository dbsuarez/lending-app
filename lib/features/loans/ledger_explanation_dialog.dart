import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/undo/undo_controller.dart';
import '../../domain/models/models.dart';
import '../../domain/services/ledger_explainer.dart';

/// "How payments were applied" for one loan, with a copy-ready text for the
/// borrower. Built from the loan's own records, so it works for any loan.
class LedgerExplanationDialog extends StatelessWidget {
  const LedgerExplanationDialog(this.loan, {super.key});
  final LoanDetail loan;

  static Future<void> show(BuildContext context, LoanDetail loan) {
    final phone = MediaQuery.sizeOf(context).width < 600;
    return phone
        ? Navigator.of(context).push(
            MaterialPageRoute<void>(
              fullscreenDialog: true,
              builder: (_) => LedgerExplanationDialog(loan),
            ),
          )
        : showDialog<void>(
            context: context,
            builder: (_) => LedgerExplanationDialog(loan),
          );
  }

  @override
  Widget build(BuildContext context) {
    final e = explainLedger(loan);
    final phone = MediaQuery.sizeOf(context).width < 600;
    final theme = Theme.of(context);
    final reference = 'LN-${loan.summary.id.substring(0, 8).toUpperCase()}';
    Future<void> copy() async {
      await Clipboard.setData(ClipboardData(text: e.customerText()));
      if (context.mounted) undoOf(context).notify('Explanation copied.');
    }

    final body = ListView(
      shrinkWrap: !phone,
      padding: EdgeInsets.all(phone ? 16 : 0),
      children: [
        Text(
          '$reference · ${loan.summary.borrowerName}',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(e.terms),
        const SizedBox(height: 4),
        Text(
          'Each payment pays the oldest unpaid installment first: interest, '
          'then principal. Anything left goes to the next one.',
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        Text('Payments', style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        if (e.payments.isEmpty)
          const Text('No verified payments yet.')
        else
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Table(
              columnWidths: const {
                0: IntrinsicColumnWidth(),
                1: IntrinsicColumnWidth(),
                2: FlexColumnWidth(),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.top,
              border: TableBorder(
                horizontalInside: BorderSide(color: theme.dividerColor),
              ),
              children: [
                TableRow(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                  ),
                  children: [
                    for (final h in ['Date', 'Paid', 'Where it went'])
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          h,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                ),
                for (final step in e.payments)
                  TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          LedgerExplanation.date(step.payment.receivedOn),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          LedgerExplanation.peso(step.payment.amountCentavos),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(e.describe(step)),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        Text('Where the loan stands', style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        for (final line in e.statusLines())
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('•  '),
                Expanded(child: Text(line)),
              ],
            ),
          ),
        if (phone) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: copy,
            icon: const Icon(Icons.copy),
            label: const Text('Copy for customer'),
          ),
        ],
      ],
    );

    if (phone) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('How payments were applied'),
          actions: [
            IconButton(
              tooltip: 'Copy for customer',
              onPressed: copy,
              icon: const Icon(Icons.copy),
            ),
          ],
        ),
        body: body,
      );
    }
    return AlertDialog(
      title: const Text('How payments were applied'),
      content: SizedBox(width: 720, child: body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: copy,
          icon: const Icon(Icons.copy),
          label: const Text('Copy for customer'),
        ),
      ],
    );
  }
}
