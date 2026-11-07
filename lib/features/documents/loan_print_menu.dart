import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../domain/models/models.dart';
import 'loan_schedule_pdf.dart';

enum LoanPrintDocument { schedule, ledger }

/// Opens the print/save dialog for one loan document.
Future<void> printLoanDocument(LoanDetail loan, LoanPrintDocument document) {
  final reference = 'LN-${loan.summary.id.substring(0, 8).toUpperCase()}';
  return switch (document) {
    LoanPrintDocument.schedule => Printing.layoutPdf(
      name: '$reference-schedule.pdf',
      onLayout: (_) => LoanSchedulePdf.build(loan),
    ),
    LoanPrintDocument.ledger => Printing.layoutPdf(
      name: '$reference-payment-ledger.pdf',
      onLayout: (_) => LoanSchedulePdf.buildLedger(loan),
    ),
  };
}

/// A print button that opens a small menu to pick the document.
///
/// [loadLoan] lets list screens fetch the full loan only after a choice is
/// made; it returns null when the loan could not be loaded.
class LoanPrintMenu extends StatelessWidget {
  const LoanPrintMenu({
    super.key,
    required this.loadLoan,
    this.filled = false,
    this.label = 'Print',
  });

  final Future<LoanDetail?> Function() loadLoan;

  /// Filled button with label; otherwise a compact icon button.
  final bool filled;
  final String label;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    menuChildren: [
      MenuItemButton(
        leadingIcon: const Icon(Icons.calendar_month_outlined),
        onPressed: () => _print(LoanPrintDocument.schedule),
        child: const Text('Loan schedule'),
      ),
      MenuItemButton(
        leadingIcon: const Icon(Icons.receipt_long_outlined),
        onPressed: () => _print(LoanPrintDocument.ledger),
        child: const Text('Payment ledger'),
      ),
    ],
    builder: (context, controller, _) {
      void toggle() =>
          controller.isOpen ? controller.close() : controller.open();
      return filled
          ? FilledButton.icon(
              onPressed: toggle,
              icon: const Icon(Icons.print_outlined),
              label: Text(label),
            )
          : IconButton(
              tooltip: 'Print or save PDF',
              onPressed: toggle,
              icon: const Icon(Icons.picture_as_pdf_outlined),
            );
    },
  );

  Future<void> _print(LoanPrintDocument document) async {
    final loan = await loadLoan();
    if (loan != null) await printLoanDocument(loan, document);
  }
}
