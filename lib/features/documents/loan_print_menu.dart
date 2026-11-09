import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:printing/printing.dart';

import '../../core/undo/undo_controller.dart';
import '../../domain/models/models.dart';
import '../borrowers/borrowers_controller.dart';
import '../loans/loans_controller.dart';
import '../settings/business_profile_provider.dart';
import 'loan_schedule_pdf.dart';

enum LoanPrintDocument {
  schedule('Loan schedule', 'schedule', Icons.calendar_month_outlined),
  ledger('Payment ledger', 'payment-ledger', Icons.receipt_long_outlined),
  statement('Statement of account', 'statement', Icons.request_page_outlined),
  agreement('Loan agreement', 'agreement', Icons.gavel_outlined),
  acknowledgment(
    'Acknowledgment of release',
    'acknowledgment-of-release',
    Icons.handshake_outlined,
  );

  const LoanPrintDocument(this.label, this.fileSuffix, this.icon);
  final String label, fileSuffix;
  final IconData icon;
}

/// Opens the print/save dialog for one loan document, with the business
/// details, the borrower's contact details and the release record filled in.
Future<void> printLoanDocument(
  ProviderContainer container,
  LoanDetail loan,
  LoanPrintDocument document,
) async {
  final reference = 'LN-${loan.summary.id.substring(0, 8).toUpperCase()}';
  final business = await _business(container);
  Borrower? borrower;
  LoanEditTerms? terms;
  if (document == LoanPrintDocument.agreement ||
      document == LoanPrintDocument.acknowledgment) {
    borrower = await _borrower(container, loan.summary.borrowerId);
    if (loan.summary.status != 'draft') {
      try {
        terms = await container
            .read(loansControllerProvider.notifier)
            .fetchEditTerms(loan.summary.id);
      } catch (_) {}
    }
  }
  if (document == LoanPrintDocument.acknowledgment &&
      terms?.disbursedOn == null) {
    throw StateError(
      'This loan has no money release yet. Release it first, then print '
      'the acknowledgment.',
    );
  }
  final Future<Uint8List> Function() build = switch (document) {
    LoanPrintDocument.schedule => () => LoanSchedulePdf.build(
      loan,
      business: business,
    ),
    LoanPrintDocument.ledger => () => LoanSchedulePdf.buildLedger(
      loan,
      business: business,
    ),
    LoanPrintDocument.statement => () => LoanDocumentsPdf.statement(
      loan: loan,
      business: business,
    ),
    LoanPrintDocument.agreement => () => LoanDocumentsPdf.agreement(
      loan: loan,
      business: business,
      borrower: borrower,
      releasedOn: terms?.disbursedOn,
    ),
    LoanPrintDocument.acknowledgment => () => LoanDocumentsPdf.acknowledgment(
      loan: loan,
      business: business,
      borrower: borrower,
      releasedOn: terms!.disbursedOn!,
      method: borrowerFacing(terms.method),
      reference: borrowerFacing(terms.reference),
    ),
  };
  await Printing.layoutPdf(
    name: '$reference-${document.fileSuffix}.pdf',
    onLayout: (_) => build(),
  );
}

/// Prints the receipt for one verified payment.
Future<void> printPaymentReceipt(
  ProviderContainer container,
  PaymentSummary payment,
) async {
  if (payment.status != 'verified') {
    throw StateError('Receipts are for verified payments only.');
  }
  final loan = await container
      .read(loansControllerProvider.notifier)
      .fetchDetail(payment.loanId);
  final business = await _business(container);
  await Printing.layoutPdf(
    name: 'PR-${payment.id.substring(0, 8).toUpperCase()}-receipt.pdf',
    format: PdfPageFormat.a5,
    onLayout: (_) => LoanDocumentsPdf.receipt(
      loan: loan,
      payment: payment,
      business: business,
    ),
  );
}

/// Same as [printLoanDocument] / [printPaymentReceipt] from a widget, with
/// problems shown as a message instead of thrown.
Future<void> printFromContext(
  BuildContext context,
  Future<void> Function(ProviderContainer container) print,
) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final undo = undoOf(context);
  try {
    await print(container);
  } on StateError catch (e) {
    undo.record(e.message);
  } catch (_) {
    undo.record('The document could not be created. Try again.');
  }
}

Future<BusinessProfile> _business(ProviderContainer container) async {
  try {
    return await container.read(businessProfileProvider.future);
  } catch (_) {
    return BusinessProfile.fallback;
  }
}

Future<Borrower?> _borrower(ProviderContainer container, String id) async {
  try {
    final list = await container.read(borrowersControllerProvider.future);
    return list.where((b) => b.id == id).firstOrNull;
  } catch (_) {
    return null;
  }
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
      for (final document in LoanPrintDocument.values)
        MenuItemButton(
          leadingIcon: Icon(document.icon),
          onPressed: () => _print(context, document),
          child: Text(document.label),
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

  Future<void> _print(BuildContext context, LoanPrintDocument document) async {
    final loan = await loadLoan();
    if (loan == null || !context.mounted) return;
    await printFromContext(
      context,
      (container) => printLoanDocument(container, loan, document),
    );
  }
}
