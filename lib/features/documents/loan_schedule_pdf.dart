import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../core/formatting.dart';
import '../../domain/models/models.dart';
import '../settings/business_profile_provider.dart';

part 'loan_documents_pdf.dart';

class LoanSchedulePdf {
  const LoanSchedulePdf._();

  static final _blue = PdfColor.fromHex('#1257B8');
  static final _paleBlue = PdfColor.fromHex('#EAF2FF');
  static final _border = PdfColor.fromHex('#C8D4E3');

  static Future<Uint8List> build(
    LoanDetail loan, {
    DateTime? generatedOn,
    BusinessProfile business = BusinessProfile.fallback,
  }) => _render(
    loan,
    business: business,
    generated: generatedOn ?? DateTime.now(),
    title: 'Loan Schedule - ${loan.summary.borrowerName}',
    subject: 'Installment schedule',
    heading: 'LOAN PAYMENT SCHEDULE',
    sectionTitle: 'INSTALLMENT SCHEDULE',
    table: _scheduleTable(loan.installments, _blue, _paleBlue, _border),
    note:
        'This schedule shows the agreed dates and amounts for this loan. Check payment status and balances against the payment records.',
  );

  static Future<Uint8List> buildLedger(
    LoanDetail loan, {
    DateTime? generatedOn,
    BusinessProfile business = BusinessProfile.fallback,
  }) {
    final generated = generatedOn ?? DateTime.now();
    return _render(
      loan,
      business: business,
      generated: generated,
      title: 'Payment Ledger - ${loan.summary.borrowerName}',
      subject: 'Payment ledger',
      heading: 'LOAN PAYMENT LEDGER',
      sectionTitle: 'PAYMENT LEDGER',
      balances: [
        ('Opening balance', _money(loan.summary.totalCentavos)),
        (
          'Total received',
          _money(loan.payments.fold(0, (sum, p) => sum + p.amountCentavos)),
        ),
        ('Applied', _money(loan.paidCentavos)),
        ('Balance', _money(loan.outstandingCentavos)),
      ],
      table: _ledgerTable(loan.ledgerRows(asOf: generated)),
      note:
          'Received shows each payment on the installment it paid, with the date the money came in. Applied is what was credited to that installment; payments pay the oldest unpaid installment first and any extra goes to the next one. '
          '${_lateLine(loan)}'
          'Verified payments as of ${formatPhilippineDate(generated)}; pending, rejected, and reversed payments are not included.',
    );
  }

  static Future<Uint8List> _render(
    LoanDetail loan, {
    required BusinessProfile business,
    required DateTime generated,
    required String title,
    required String subject,
    required String heading,
    required String sectionTitle,
    required pw.Widget table,
    required String note,
    List<(String, String)> balances = const [],
  }) async {
    final document = pw.Document(
      title: title,
      author: business.name,
      subject: subject,
    );
    final blue = _blue;
    final paleBlue = _paleBlue;
    final border = _border;
    final paymentQrs = await _paymentQrs();

    document.addPage(
      pw.MultiPage(
        theme: await _theme(),
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(34, 32, 34, 32),
        header: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 10),
          decoration: pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: blue, width: 2)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                business.name.toUpperCase(),
                style: pw.TextStyle(
                  color: blue,
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                heading,
                style: pw.TextStyle(
                  color: blue,
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        footer: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(top: 8),
          decoration: pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: border, width: .6)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Generated ${formatPhilippineDate(generated)}',
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.grey700,
                ),
              ),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
        ),
        build: (context) => [
          pw.SizedBox(height: 18),
          _identity(loan, blue),
          pw.SizedBox(height: 16),
          _summary(loan, paleBlue, border),
          if (balances.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: border, width: .6),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
              ),
              child: pw.Row(
                children: [
                  for (var i = 0; i < balances.length; i++) ...[
                    if (i > 0) _divider(),
                    _summaryValue(balances[i].$1, balances[i].$2),
                  ],
                ],
              ),
            ),
          ],
          pw.SizedBox(height: 18),
          pw.Text(
            sectionTitle,
            style: pw.TextStyle(
              color: blue,
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          table,
          pw.SizedBox(height: 14),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#F7F9FC'),
              border: pw.Border.all(color: border, width: .6),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Text(
              note,
              style: const pw.TextStyle(
                fontSize: 8.5,
                color: PdfColors.grey800,
              ),
            ),
          ),
          if (paymentQrs.isNotEmpty)
            _howToPay(paymentQrs, _reference(loan.summary.id), border),
        ],
      ),
    );
    return document.save();
  }

  /// InstaPay QR codes printed on borrower documents (schedule and ledger).
  static const _qrAssets = [
    ('GCash', 'assets/payment_qr/gcash.png'),
    ('AUB HelloMoney', 'assets/payment_qr/aub.png'),
    ('MariBank', 'assets/payment_qr/maribank.png'),
  ];
  static List<(String, pw.ImageProvider)>? _cachedQrs;

  static Future<List<(String, pw.ImageProvider)>> _paymentQrs() async {
    final cached = _cachedQrs;
    if (cached != null) return cached;
    final loaded = <(String, pw.ImageProvider)>[];
    for (final (label, path) in _qrAssets) {
      final data = await rootBundle.load(path);
      loaded.add((label, pw.MemoryImage(data.buffer.asUint8List())));
    }
    return _cachedQrs = loaded;
  }

  /// One block (title, instructions, QR row) so it moves to the next page
  /// as a whole instead of splitting.
  static pw.Widget _howToPay(
    List<(String, pw.ImageProvider)> qrs,
    String reference,
    PdfColor border,
  ) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 16),
    // A horizontal Row cannot span pages (vertical Columns can), so this
    // keeps the heading and QR codes together, moving them to the next page
    // as one block when they do not fit.
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'HOW TO PAY',
                style: pw.TextStyle(
                  color: _blue,
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Scan any QR code with a banking or e-wallet app that supports '
                'InstaPay. Put your loan reference $reference in the note, then '
                'send us the transaction reference number so we can confirm it.',
                style: const pw.TextStyle(
                  fontSize: 8.5,
                  color: PdfColors.grey800,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < qrs.length; i++) ...[
                    if (i > 0) pw.SizedBox(width: 10),
                    pw.Expanded(
                      child: pw.Container(
                        padding: const pw.EdgeInsets.all(6),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: border, width: .6),
                          borderRadius: const pw.BorderRadius.all(
                            pw.Radius.circular(4),
                          ),
                        ),
                        child: pw.Column(
                          children: [
                            pw.Image(
                              qrs[i].$2,
                              height: 165,
                              fit: pw.BoxFit.contain,
                            ),
                            pw.SizedBox(height: 4),
                            pw.Text(
                              qrs[i].$1,
                              style: pw.TextStyle(
                                fontSize: 9,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );

  static pw.Widget _identity(LoanDetail loan, PdfColor blue) => pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'BORROWER',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              loan.summary.borrowerName,
              style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      ),
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text(
            _reference(loan.summary.id),
            style: pw.TextStyle(
              color: blue,
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            loan.summary.status.toUpperCase(),
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ),
    ],
  );

  static pw.Widget _summary(
    LoanDetail loan,
    PdfColor background,
    PdfColor border,
  ) => pw.Container(
    padding: const pw.EdgeInsets.all(12),
    decoration: pw.BoxDecoration(
      color: background,
      border: pw.Border.all(color: border, width: .6),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
    ),
    child: pw.Row(
      children: [
        _summaryValue('Principal', _money(loan.summary.principalCentavos)),
        _divider(),
        _summaryValue(
          'Flat interest',
          _money(loan.summary.totalCentavos - loan.summary.principalCentavos),
        ),
        _divider(),
        _summaryValue('Total repayable', _money(loan.summary.totalCentavos)),
        _divider(),
        _summaryValue('Term', '${loan.summary.termMonths} months'),
        _divider(),
        _summaryValue(
          'Monthly rate',
          '${(loan.summary.monthlyRateBasisPoints / 100).toStringAsFixed(2)}%',
        ),
      ],
    ),
  );

  static pw.Widget _summaryValue(String label, String value) => pw.Expanded(
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          label,
          textAlign: pw.TextAlign.center,
          style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          value,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        ),
      ],
    ),
  );

  static pw.Widget _divider() =>
      pw.Container(width: .6, height: 32, color: PdfColors.blueGrey200);

  static pw.Widget _scheduleTable(
    List<Installment> installments,
    PdfColor blue,
    PdfColor alternate,
    PdfColor border,
  ) => pw.Table(
    border: pw.TableBorder.all(color: border, width: .55),
    columnWidths: const {
      0: pw.FixedColumnWidth(34),
      1: pw.FlexColumnWidth(1.4),
      2: pw.FlexColumnWidth(1.4),
      3: pw.FlexColumnWidth(1.4),
      4: pw.FlexColumnWidth(1.5),
    },
    children: [
      pw.TableRow(
        decoration: pw.BoxDecoration(color: blue),
        children: [
          _headerCell('#'),
          _headerCell('Due date'),
          _headerCell('Principal', right: true),
          _headerCell('Interest', right: true),
          _headerCell('Amount due', right: true),
        ],
      ),
      for (var index = 0; index < installments.length; index++)
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: index.isOdd ? alternate : PdfColors.white,
          ),
          children: [
            _cell('${installments[index].sequence}', center: true),
            _cell(formatPhilippineDate(installments[index].dueDate)),
            _cell(_money(installments[index].principalCentavos), right: true),
            _cell(_money(installments[index].interestCentavos), right: true),
            _cell(
              _money(installments[index].amountCentavos),
              right: true,
              bold: true,
            ),
          ],
        ),
    ],
  );

  static pw.Widget _ledgerTable(List<LedgerRow> rows) => pw.Table(
    border: pw.TableBorder.all(color: _border, width: .55),
    columnWidths: const {
      0: pw.FixedColumnWidth(24),
      1: pw.FlexColumnWidth(1.25),
      2: pw.FlexColumnWidth(1.2),
      3: pw.FlexColumnWidth(1.2),
      4: pw.FlexColumnWidth(1.25),
      5: pw.FlexColumnWidth(1.2),
      6: pw.FlexColumnWidth(1.3),
      7: pw.FlexColumnWidth(1),
    },
    children: [
      pw.TableRow(
        decoration: pw.BoxDecoration(color: _blue),
        children: [
          _headerCell('#'),
          _headerCell('Due date'),
          _headerCell('Amount due', right: true),
          _headerCell('Received', right: true),
          _headerCell('Payment date'),
          _headerCell('Applied', right: true),
          _headerCell('Ending balance', right: true),
          _headerCell('Status'),
        ],
      ),
      for (var index = 0; index < rows.length; index++)
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: index.isOdd ? _paleBlue : PdfColors.white,
          ),
          children: [
            _cell('${rows[index].installment.sequence}', center: true),
            _cell(formatPhilippineDate(rows[index].installment.dueDate)),
            _cell(_money(rows[index].installment.amountCentavos), right: true),
            _cell(
              rows[index].received.isEmpty
                  ? '-'
                  : _money(rows[index].receivedCentavos),
              right: true,
              bold: true,
            ),
            _cell(
              rows[index].received.isEmpty
                  ? '-'
                  : rows[index].received
                        .map((p) => formatPhilippineDate(p.receivedOn))
                        .join('\n'),
            ),
            _cell(_money(rows[index].installment.paidCentavos), right: true),
            _cell(
              _money(rows[index].endingBalanceCentavos),
              right: true,
              bold: true,
            ),
            _cell(_statusLabel(rows[index].status)),
          ],
        ),
    ],
  );

  static String _lateLine(LoanDetail loan) {
    final late = loan.paymentsAfterFinalDue;
    if (late.isEmpty) return '';
    final total = late.fold(0, (sum, p) => sum + p.amountCentavos);
    return 'Not applied to any installment (received after the final due date): ${_money(total)} '
        '(${late.map((p) => '${_money(p.amountCentavos)} on ${formatPhilippineDate(p.receivedOn)}').join(', ')}). ';
  }

  static String _statusLabel(String status) =>
      status[0].toUpperCase() + status.substring(1);

  static pw.Widget _headerCell(String text, {bool right = false}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 7),
    child: pw.Text(
      text,
      textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
      style: pw.TextStyle(
        color: PdfColors.white,
        fontSize: 8,
        fontWeight: pw.FontWeight.bold,
      ),
    ),
  );

  static pw.Widget _cell(
    String text, {
    bool right = false,
    bool center = false,
    bool bold = false,
  }) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 6),
    child: pw.Text(
      text,
      textAlign: center
          ? pw.TextAlign.center
          : right
          ? pw.TextAlign.right
          : pw.TextAlign.left,
      style: pw.TextStyle(
        fontSize: 8.5,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );

  static pw.ThemeData? _cachedTheme;

  /// Roboto is embedded so borrower names with ñ/accents and the peso
  /// sign render; the PDF built-in Helvetica has no Unicode support.
  static Future<pw.ThemeData> _theme() async {
    final cached = _cachedTheme;
    if (cached != null) return cached;
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
    );
    return _cachedTheme = pw.ThemeData.withFont(base: regular, bold: bold);
  }

  static String _money(int centavos) {
    final value = (centavos / 100).toStringAsFixed(2);
    final parts = value.split('.');
    final formatted = parts.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '₱$formatted.${parts.last}';
  }

  static String _reference(String id) =>
      'LN-${id.substring(0, 8).toUpperCase()}';
}
