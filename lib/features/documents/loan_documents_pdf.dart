part of 'loan_schedule_pdf.dart';

/// Receipt, statement of account, loan agreement and acknowledgment of
/// release. Shares fonts, tables and the "How to pay" block with the
/// schedule and ledger.
class LoanDocumentsPdf {
  const LoanDocumentsPdf._();

  // ---- Payment receipt ------------------------------------------------------

  static Future<Uint8List> receipt({
    required LoanDetail loan,
    required PaymentSummary payment,
    required BusinessProfile business,
    DateTime? issuedOn,
  }) async {
    final issued = issuedOn ?? DateTime.now();
    final received = payment.receivedAt.toLocal();
    final match = loan.payments
        .where(
          (p) =>
              p.amountCentavos == payment.amountCentavos &&
              p.receivedAt.isAtSameMomentAs(payment.receivedAt),
        )
        .firstOrNull;
    final doc = pw.Document(
      title: 'Payment Receipt - ${loan.summary.borrowerName}',
      author: business.name,
    );
    doc.addPage(
      pw.Page(
        theme: await LoanSchedulePdf._theme(),
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.fromLTRB(28, 26, 28, 26),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _businessHeader(business, 'PAYMENT RECEIPT'),
            pw.SizedBox(height: 10),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _label(
                  'Receipt no.',
                  'PR-${payment.id.substring(0, 8).toUpperCase()}',
                ),
                _label('Date issued', formatPhilippineDate(issued), end: true),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: _box(fill: LoanSchedulePdf._paleBlue),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Received from',
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.Text(
                    loan.summary.borrowerName,
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    'the amount of',
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.Text(
                    LoanSchedulePdf._money(payment.amountCentavos),
                    style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                      color: LoanSchedulePdf._blue,
                    ),
                  ),
                  pw.Text(
                    amountInWords(payment.amountCentavos),
                    style: const pw.TextStyle(fontSize: 8.5),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),
            _rows([
              ('For loan', LoanSchedulePdf._reference(loan.summary.id)),
              ('Date received', formatPhilippineDateTime(received)),
              if (borrowerFacing(payment.method).isNotEmpty)
                ('Payment method', borrowerFacing(payment.method)),
              if (borrowerFacing(payment.reference).isNotEmpty)
                ('Transaction reference', borrowerFacing(payment.reference)),
              if (match != null && match.allocations.isNotEmpty)
                (
                  'Applied to',
                  match.allocations
                      .map(
                        (a) =>
                            'Installment ${a.sequence}: '
                            '${LoanSchedulePdf._money(a.totalCentavos)}',
                      )
                      .join('\n'),
                ),
              (
                'Remaining balance',
                '${LoanSchedulePdf._money(loan.outstandingCentavos)} '
                    '(as of ${formatPhilippineDate(issued)})',
              ),
            ]),
            pw.Spacer(),
            _signatures(['Received by (for ${business.name})']),
            pw.SizedBox(height: 10),
            pw.Text(
              'This receipt confirms a payment recorded and verified in our '
              'books. It is an acknowledgment for your records and not a '
              'BIR-registered official receipt.',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
            ),
          ],
        ),
      ),
    );
    return doc.save();
  }

  // ---- Statement of account ------------------------------------------------

  static Future<Uint8List> statement({
    required LoanDetail loan,
    required BusinessProfile business,
    DateTime? asOf,
  }) async {
    final date = asOf ?? DateTime.now();
    final today = DateTime(date.year, date.month, date.day);
    final unpaid = [
      for (final i in loan.installments)
        if (i.outstandingCentavos > 0) i,
    ]..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final pastDue = unpaid.where((i) => i.dueDate.isBefore(today)).toList();
    final pastDueAmount = pastDue.fold(0, (s, i) => s + i.outstandingCentavos);
    final next = unpaid.where((i) => !i.dueDate.isBefore(today)).firstOrNull;
    final daysPastDue = pastDue.isEmpty
        ? 0
        : today.difference(pastDue.first.dueDate).inDays;
    final amountDueNow =
        pastDueAmount + (next == null ? 0 : next.outstandingCentavos);
    final qrs = await LoanSchedulePdf._paymentQrs();
    final doc = pw.Document(
      title: 'Statement of Account - ${loan.summary.borrowerName}',
      author: business.name,
    );
    doc.addPage(
      pw.MultiPage(
        theme: await LoanSchedulePdf._theme(),
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(34, 32, 34, 32),
        header: (_) => _businessHeader(business, 'STATEMENT OF ACCOUNT'),
        footer: (context) => _footer(date, context),
        build: (context) => [
          pw.SizedBox(height: 14),
          LoanSchedulePdf._identity(loan, LoanSchedulePdf._blue),
          pw.SizedBox(height: 4),
          pw.Text(
            'Statement date: ${formatPhilippineDate(date)}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
          ),
          pw.SizedBox(height: 12),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: _box(fill: LoanSchedulePdf._paleBlue),
            child: pw.Row(
              children: [
                LoanSchedulePdf._summaryValue(
                  'Total repayable',
                  LoanSchedulePdf._money(loan.summary.totalCentavos),
                ),
                LoanSchedulePdf._divider(),
                LoanSchedulePdf._summaryValue(
                  'Paid to date',
                  LoanSchedulePdf._money(loan.paidCentavos),
                ),
                LoanSchedulePdf._divider(),
                LoanSchedulePdf._summaryValue(
                  'Outstanding balance',
                  LoanSchedulePdf._money(loan.outstandingCentavos),
                ),
                LoanSchedulePdf._divider(),
                LoanSchedulePdf._summaryValue(
                  'Past due',
                  pastDueAmount == 0
                      ? 'None'
                      : '${LoanSchedulePdf._money(pastDueAmount)}\n'
                            '($daysPastDue days)',
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: _box(),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  loan.outstandingCentavos == 0
                      ? 'This loan is fully paid. Thank you.'
                      : 'AMOUNT DUE NOW'
                            '${next == null ? '' : ' (including the installment due ${formatPhilippineDate(next.dueDate)})'}',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if (loan.outstandingCentavos > 0)
                  pw.Text(
                    LoanSchedulePdf._money(amountDueNow),
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      color: LoanSchedulePdf._blue,
                    ),
                  ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          // Only what is still owed; the full history is the payment ledger.
          _sectionTitle('STILL TO PAY'),
          pw.SizedBox(height: 6),
          if (unpaid.isEmpty)
            pw.Text('Nothing left to pay.')
          else
            _unpaidTable(unpaid, today),
          pw.SizedBox(height: 16),
          _sectionTitle('PAYMENTS RECEIVED'),
          pw.SizedBox(height: 6),
          if (loan.payments.isEmpty)
            pw.Text('No verified payments yet.')
          else
            pw.Table(
              border: pw.TableBorder.all(
                color: LoanSchedulePdf._border,
                width: .55,
              ),
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: LoanSchedulePdf._blue),
                  children: [
                    LoanSchedulePdf._headerCell('Date received'),
                    LoanSchedulePdf._headerCell('Amount', right: true),
                  ],
                ),
                for (final p in [
                  ...loan.payments,
                ]..sort((a, b) => a.receivedAt.compareTo(b.receivedAt)))
                  pw.TableRow(
                    children: [
                      LoanSchedulePdf._cell(formatPhilippineDate(p.receivedOn)),
                      LoanSchedulePdf._cell(
                        LoanSchedulePdf._money(p.amountCentavos),
                        right: true,
                      ),
                    ],
                  ),
              ],
            ),
          pw.SizedBox(height: 12),
          _note(
            'Only verified payments are included. If you have paid recently '
            'and it is not shown, please send us the transaction reference. '
            'For questions about this statement, contact '
            '${_contact(business)}.',
          ),
          if (qrs.isNotEmpty && loan.outstandingCentavos > 0)
            LoanSchedulePdf._howToPay(
              qrs,
              LoanSchedulePdf._reference(loan.summary.id),
              LoanSchedulePdf._border,
            ),
        ],
      ),
    );
    return doc.save();
  }

  // ---- Loan agreement ------------------------------------------------------

  static Future<Uint8List> agreement({
    required LoanDetail loan,
    required BusinessProfile business,
    Borrower? borrower,
    DateTime? releasedOn,
    PenaltyPolicy penalty = PenaltyPolicy.none,
  }) async {
    final s = loan.summary;
    final charged = loan.installments.fold(0, (t, i) => t + i.penaltyCentavos);
    // The agreement shows the loan as agreed: without penalties charged since.
    final interest = s.totalCentavos - charged - s.principalCentavos;
    final n = loan.installments.length;
    final rate = (s.monthlyRateBasisPoints / 100).toStringAsFixed(2);
    final first = loan.installments.isEmpty
        ? null
        : loan.installments
              .map((i) => i.dueDate)
              .reduce((a, b) => a.isBefore(b) ? a : b);
    final last = loan.installments.isEmpty
        ? null
        : loan.installments
              .map((i) => i.dueDate)
              .reduce((a, b) => a.isAfter(b) ? a : b);
    final borrowerName = borrower == null
        ? s.borrowerName
        : '${borrower.firstName} ${borrower.lastName}';
    final doc = pw.Document(
      title: 'Loan Agreement - ${s.borrowerName}',
      author: business.name,
    );
    final clauses = <(String, String)>[
      (
        'Loan amount',
        'The Lender lends the Borrower ${LoanSchedulePdf._money(s.principalCentavos)} '
            '(${amountInWords(s.principalCentavos)}), released '
            '${releasedOn == null ? 'on the release date stated in the Acknowledgment of Release' : 'on ${formatPhilippineDate(releasedOn)}'}.',
      ),
      (
        'Interest',
        'Interest is a flat $rate% per month on the original amount for '
            '${s.termMonths} month${s.termMonths == 1 ? '' : 's'}, a total of '
            '${LoanSchedulePdf._money(interest)}. Interest is not compounded.',
      ),
      (
        'Repayment',
        'The Borrower will repay ${LoanSchedulePdf._money(s.totalCentavos - charged)} in '
            '$n installment${n == 1 ? '' : 's'} on the dates in the schedule '
            'below${first == null ? '' : ', from ${formatPhilippineDate(first)} to ${formatPhilippineDate(last!)}'}. '
            'Payments may be made in cash or by transfer to the Lender\'s '
            'accounts; the Borrower will send the transaction reference.',
      ),
      (
        'How payments are applied',
        'Each payment is applied to the oldest unpaid installment, first to '
            '${penalty.charges ? 'any penalty, then ' : ''}interest and then to '
            'principal. Any amount above what is due is held as credit for the '
            'next installment.',
      ),
      (
        'Late payment',
        '${switch (penalty.mode) {
              'fixed' || 'percentage' => 'A penalty of ${describePenalty(penalty)[0].toLowerCase()}${describePenalty(penalty).substring(1)} ',
              'manual' => 'The Lender may charge a penalty on a late installment; the amount and reason are recorded and shown to the Borrower. ',
              _ => 'No penalty or late charge is imposed. ',
            }}If a payment will be late, the Borrower agrees to tell the Lender '
            'the reason and the date payment will be made.',
      ),
      (
        'Early payment',
        'The Borrower may pay the whole balance early. The payoff amount is '
            'the remaining principal plus at least the interest for the month '
            'of payoff; interest for later months may be waived at the '
            'Lender\'s discretion.',
      ),
      (
        'Collection',
        'The Lender will only contact the Borrower (and persons the Borrower '
            'has named) in a respectful manner, at reasonable hours, and will '
            'not use threats, insults, false representations or disclosure of '
            'the debt to others.',
      ),
      (
        'Personal data',
        'The Borrower consents to the Lender collecting and keeping the '
            'Borrower\'s name, contact details and loan records to manage '
            'this loan and as required by law, in line with the Data Privacy '
            'Act of 2012. The Borrower may ask to see or correct this '
            'information.',
      ),
      (
        'Governing law',
        'This agreement is governed by the laws of the Republic of the '
            'Philippines.',
      ),
    ];
    doc.addPage(
      pw.MultiPage(
        theme: await LoanSchedulePdf._theme(),
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 34, 40, 34),
        header: (_) => _businessHeader(business, 'LOAN AGREEMENT'),
        footer: (context) => _footer(DateTime.now(), context),
        build: (context) => [
          pw.SizedBox(height: 12),
          pw.Text(
            'This Loan Agreement for loan '
            '${LoanSchedulePdf._reference(s.id)} is made between:',
            style: const pw.TextStyle(fontSize: 9.5),
          ),
          pw.SizedBox(height: 8),
          _rows([
            (
              'Lender',
              [
                business.name,
                if (business.address.isNotEmpty) business.address,
                if (_contact(business, fallback: '').isNotEmpty)
                  _contact(business, fallback: ''),
              ].join('\n'),
            ),
            (
              'Borrower',
              [
                borrowerName,
                if ((borrower?.address ?? '').isNotEmpty) borrower!.address,
                if ((borrower?.phone ?? '').isNotEmpty) borrower!.phone,
              ].join('\n'),
            ),
          ]),
          pw.SizedBox(height: 12),
          _sectionTitle('DISCLOSURE'),
          pw.SizedBox(height: 6),
          _rows([
            ('Amount borrowed', LoanSchedulePdf._money(s.principalCentavos)),
            ('Finance charge (interest)', LoanSchedulePdf._money(interest)),
            (
              'Total to be repaid',
              LoanSchedulePdf._money(s.totalCentavos - charged),
            ),
            (
              'Interest rate',
              '$rate% per month, flat, for ${s.termMonths} months',
            ),
            ('Number of installments', '$n'),
            (
              'Penalties and other charges',
              penalty.charges ? describePenalty(penalty) : 'None',
            ),
          ]),
          pw.SizedBox(height: 12),
          _sectionTitle('TERMS'),
          pw.SizedBox(height: 6),
          for (var i = 0; i < clauses.length; i++)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: pw.RichText(
                text: pw.TextSpan(
                  style: const pw.TextStyle(fontSize: 9.5, lineSpacing: 2),
                  children: [
                    pw.TextSpan(
                      text: '${i + 1}. ${clauses[i].$1}. ',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    pw.TextSpan(text: clauses[i].$2),
                  ],
                ),
              ),
            ),
          pw.SizedBox(height: 10),
          _sectionTitle('REPAYMENT SCHEDULE'),
          pw.SizedBox(height: 6),
          LoanSchedulePdf._scheduleTable(
            // As agreed: amounts without penalties charged since.
            [
              for (final i in loan.installments)
                Installment(
                  sequence: i.sequence,
                  dueDate: i.dueDate,
                  amountCentavos: i.amountCentavos - i.penaltyCentavos,
                  principalCentavos: i.principalCentavos,
                  interestCentavos: i.interestCentavos,
                ),
            ],
            LoanSchedulePdf._blue,
            LoanSchedulePdf._paleBlue,
            LoanSchedulePdf._border,
          ),
          pw.SizedBox(height: 18),
          pw.Text(
            'Signed on ____________________ at ____________________.',
            style: const pw.TextStyle(fontSize: 9.5),
          ),
          pw.SizedBox(height: 24),
          _signatures(['Lender: ${business.name}', 'Borrower: $borrowerName']),
          pw.SizedBox(height: 22),
          _signatures(['Witness', 'Witness']),
        ],
      ),
    );
    return doc.save();
  }

  // ---- Acknowledgment of release ------------------------------------------

  static Future<Uint8List> acknowledgment({
    required LoanDetail loan,
    required BusinessProfile business,
    required DateTime releasedOn,
    String method = '',
    String reference = '',
    Borrower? borrower,
  }) async {
    final s = loan.summary;
    final borrowerName = borrower == null
        ? s.borrowerName
        : '${borrower.firstName} ${borrower.lastName}';
    final first = loan.installments.isEmpty
        ? null
        : loan.installments
              .map((i) => i.dueDate)
              .reduce((a, b) => a.isBefore(b) ? a : b);
    final doc = pw.Document(
      title: 'Acknowledgment of Release - ${s.borrowerName}',
      author: business.name,
    );
    doc.addPage(
      pw.Page(
        theme: await LoanSchedulePdf._theme(),
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(46, 38, 46, 38),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _businessHeader(business, 'ACKNOWLEDGMENT OF RELEASE'),
            pw.SizedBox(height: 30),
            pw.Text(
              'ACKNOWLEDGMENT OF RECEIPT OF LOAN PROCEEDS',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 24),
            pw.Text(
              'I, $borrowerName'
              '${(borrower?.address ?? '').isNotEmpty ? ', of ${borrower!.address},' : ','} '
              'acknowledge that on ${formatPhilippineDate(releasedOn)} I received '
              'from ${business.name} the amount of '
              '${LoanSchedulePdf._money(s.principalCentavos)} '
              '(${amountInWords(s.principalCentavos)})'
              '${method.isEmpty ? '' : ' by $method'}'
              '${reference.isEmpty ? '' : ' (reference $reference)'}, '
              'being the full proceeds of loan '
              '${LoanSchedulePdf._reference(s.id)}.',
              style: const pw.TextStyle(fontSize: 11, lineSpacing: 4),
            ),
            pw.SizedBox(height: 14),
            pw.Text(
              'I agree to repay a total of '
              '${LoanSchedulePdf._money(s.totalCentavos)} in '
              '${loan.installments.length} installments'
              '${first == null ? '' : ' starting ${formatPhilippineDate(first)}'}, '
              'as set out in the loan agreement and payment schedule given '
              'to me.',
              style: const pw.TextStyle(fontSize: 11, lineSpacing: 4),
            ),
            pw.SizedBox(height: 60),
            _signatures(['Borrower: $borrowerName', 'Date']),
            pw.SizedBox(height: 40),
            _signatures(['Released by: ${business.name}', 'Witness']),
            pw.Spacer(),
            pw.Text(
              'Loan ${LoanSchedulePdf._reference(s.id)} · generated '
              '${formatPhilippineDate(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
            ),
          ],
        ),
      ),
    );
    return doc.save();
  }

  /// Unpaid installments: what each still needs, and whether it is overdue.
  static pw.Widget _unpaidTable(List<Installment> unpaid, DateTime today) =>
      pw.Table(
        border: pw.TableBorder.all(color: LoanSchedulePdf._border, width: .55),
        columnWidths: const {
          0: pw.FixedColumnWidth(26),
          1: pw.FlexColumnWidth(1.3),
          2: pw.FlexColumnWidth(1.3),
          3: pw.FlexColumnWidth(1.3),
          4: pw.FlexColumnWidth(1.3),
          5: pw.FlexColumnWidth(1.4),
        },
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(color: LoanSchedulePdf._blue),
            children: [
              LoanSchedulePdf._headerCell('#'),
              LoanSchedulePdf._headerCell('Due date'),
              LoanSchedulePdf._headerCell('Installment', right: true),
              LoanSchedulePdf._headerCell('Paid so far', right: true),
              LoanSchedulePdf._headerCell('Still owed', right: true),
              LoanSchedulePdf._headerCell('Status'),
            ],
          ),
          for (var i = 0; i < unpaid.length; i++)
            pw.TableRow(
              decoration: pw.BoxDecoration(
                color: i.isOdd ? LoanSchedulePdf._paleBlue : PdfColors.white,
              ),
              children: [
                LoanSchedulePdf._cell('${unpaid[i].sequence}', center: true),
                LoanSchedulePdf._cell(formatPhilippineDate(unpaid[i].dueDate)),
                LoanSchedulePdf._cell(
                  LoanSchedulePdf._money(unpaid[i].amountCentavos),
                  right: true,
                ),
                LoanSchedulePdf._cell(
                  LoanSchedulePdf._money(unpaid[i].paidCentavos),
                  right: true,
                ),
                LoanSchedulePdf._cell(
                  LoanSchedulePdf._money(unpaid[i].outstandingCentavos),
                  right: true,
                  bold: true,
                ),
                LoanSchedulePdf._cell(_dueStatus(unpaid[i].dueDate, today)),
              ],
            ),
        ],
      );

  static String _dueStatus(DateTime due, DateTime today) {
    final day = DateTime(due.year, due.month, due.day);
    if (day.isBefore(today)) {
      final days = today.difference(day).inDays;
      return 'Overdue $days day${days == 1 ? '' : 's'}';
    }
    return day == today ? 'Due today' : 'Upcoming';
  }

  // ---- Shared pieces --------------------------------------------------------

  static pw.Widget _businessHeader(BusinessProfile b, String title) =>
      pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 8),
        decoration: pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(color: LoanSchedulePdf._blue, width: 2),
          ),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    b.name.toUpperCase(),
                    style: pw.TextStyle(
                      color: LoanSchedulePdf._blue,
                      fontSize: 15,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  for (final line in [
                    if (b.address.isNotEmpty) b.address,
                    if (_contact(b, fallback: '').isNotEmpty)
                      _contact(b, fallback: ''),
                  ])
                    pw.Text(
                      line,
                      style: const pw.TextStyle(
                        fontSize: 7.5,
                        color: PdfColors.grey800,
                      ),
                    ),
                ],
              ),
            ),
            pw.Text(
              title,
              style: pw.TextStyle(
                color: LoanSchedulePdf._blue,
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      );

  static String _contact(BusinessProfile b, {String fallback = 'us'}) {
    final parts = [
      if (b.phone.isNotEmpty) b.phone,
      if (b.email.isNotEmpty) b.email,
    ];
    return parts.isEmpty ? fallback : parts.join(' · ');
  }

  static pw.Widget _footer(DateTime generated, pw.Context context) =>
      pw.Container(
        padding: const pw.EdgeInsets.only(top: 8),
        decoration: pw.BoxDecoration(
          border: pw.Border(
            top: pw.BorderSide(color: LoanSchedulePdf._border, width: .6),
          ),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Generated ${formatPhilippineDate(generated)}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
          ],
        ),
      );

  static pw.BoxDecoration _box({PdfColor? fill}) => pw.BoxDecoration(
    color: fill,
    border: pw.Border.all(color: LoanSchedulePdf._border, width: .6),
    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
  );

  static pw.Widget _sectionTitle(String text) => pw.Text(
    text,
    style: pw.TextStyle(
      color: LoanSchedulePdf._blue,
      fontSize: 11,
      fontWeight: pw.FontWeight.bold,
    ),
  );

  static pw.Widget _note(String text) => pw.Container(
    padding: const pw.EdgeInsets.all(10),
    decoration: _box(fill: PdfColor.fromHex('#F7F9FC')),
    child: pw.Text(
      text,
      style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey800),
    ),
  );

  static pw.Widget _label(String label, String value, {bool end = false}) =>
      pw.Column(
        crossAxisAlignment: end
            ? pw.CrossAxisAlignment.end
            : pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
        ],
      );

  static pw.Widget _rows(List<(String, String)> rows) => pw.Table(
    columnWidths: const {0: pw.FixedColumnWidth(120), 1: pw.FlexColumnWidth()},
    children: [
      for (final (label, value) in rows)
        pw.TableRow(
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              child: pw.Text(
                label,
                style: const pw.TextStyle(
                  fontSize: 8.5,
                  color: PdfColors.grey700,
                ),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              child: pw.Text(value, style: const pw.TextStyle(fontSize: 9.5)),
            ),
          ],
        ),
    ],
  );

  static pw.Widget _signatures(List<String> labels) => pw.Row(
    children: [
      for (var i = 0; i < labels.length; i++) ...[
        if (i > 0) pw.SizedBox(width: 30),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.SizedBox(height: 22),
              pw.Container(height: .8, color: PdfColors.grey800),
              pw.SizedBox(height: 3),
              pw.Text(
                labels[i],
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.grey800,
                ),
              ),
              pw.Text(
                'Signature over printed name',
                style: const pw.TextStyle(
                  fontSize: 6.5,
                  color: PdfColors.grey600,
                ),
              ),
            ],
          ),
        ),
      ],
    ],
  );
}

/// Loans and payments brought in from the old spreadsheet carry internal
/// notes such as "Imported from IT Avenue.xlsx / Mhaya" or "Legacy import"
/// as their method or reference. Those never go on borrower documents.
String borrowerFacing(String? value) {
  final v = (value ?? '').trim();
  final lower = v.toLowerCase();
  if (lower.contains('.xlsx') ||
      lower.contains('.xls') ||
      lower.contains('.csv') ||
      lower.startsWith('imported from') ||
      lower == 'legacy import' ||
      lower.contains('historical import')) {
    return '';
  }
  return v;
}

/// "One thousand two hundred fifty pesos and 50/100", for amounts on
/// receipts and agreements.
String amountInWords(int centavos) {
  const ones = [
    '',
    'one',
    'two',
    'three',
    'four',
    'five',
    'six',
    'seven',
    'eight',
    'nine',
    'ten',
    'eleven',
    'twelve',
    'thirteen',
    'fourteen',
    'fifteen',
    'sixteen',
    'seventeen',
    'eighteen',
    'nineteen',
  ];
  const tens = [
    '',
    '',
    'twenty',
    'thirty',
    'forty',
    'fifty',
    'sixty',
    'seventy',
    'eighty',
    'ninety',
  ];
  String below1000(int n) {
    final parts = <String>[];
    if (n >= 100) {
      parts.add('${ones[n ~/ 100]} hundred');
      n %= 100;
    }
    if (n >= 20) {
      parts.add(
        n % 10 == 0 ? tens[n ~/ 10] : '${tens[n ~/ 10]}-${ones[n % 10]}',
      );
    } else if (n > 0) {
      parts.add(ones[n]);
    }
    return parts.join(' ');
  }

  final pesos = centavos ~/ 100;
  final cents = centavos % 100;
  String words;
  if (pesos == 0) {
    words = 'zero';
  } else {
    final groups = <String>[];
    const scales = ['', ' thousand', ' million', ' billion'];
    var n = pesos;
    var scale = 0;
    while (n > 0) {
      final chunk = n % 1000;
      if (chunk > 0) groups.insert(0, '${below1000(chunk)}${scales[scale]}');
      n ~/= 1000;
      scale++;
    }
    words = groups.join(' ');
  }
  final text =
      '$words peso${pesos == 1 ? '' : 's'}'
      '${cents > 0 ? ' and ${cents.toString().padLeft(2, '0')}/100' : ' only'}';
  return text[0].toUpperCase() + text.substring(1);
}
