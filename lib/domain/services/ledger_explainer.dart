import 'package:intl/intl.dart';
import '../models/models.dart';

/// One payment, described by where its money went.
class ExplainedPayment {
  const ExplainedPayment({
    required this.payment,
    required this.parts,
    required this.unappliedCentavos,
  });
  final ReceivedPayment payment;
  final List<ExplainedPart> parts;

  /// Money from this payment not credited to any installment (extra).
  final int unappliedCentavos;
}

/// The share of a payment that went to one installment.
class ExplainedPart {
  const ExplainedPart({
    required this.sequence,
    required this.amountCentavos,
    required this.dueCentavos,
    required this.leftCentavos,
    required this.paidInOne,
  });
  final int sequence, amountCentavos, dueCentavos;

  /// Still owed on this installment after this payment.
  final int leftCentavos;

  /// This payment alone paid the whole installment.
  final bool paidInOne;

  bool get finishes => leftCentavos == 0;
}

/// A plain-language account of how a loan's payments were applied.
class LedgerExplanation {
  const LedgerExplanation({
    required this.loan,
    required this.payments,
    required this.paid,
    required this.partial,
    required this.overdue,
    required this.upcoming,
    required this.receivedCentavos,
  });
  final LoanDetail loan;
  final List<ExplainedPayment> payments;

  /// Installment numbers by state, in order.
  final List<int> paid, overdue, upcoming;
  final List<Installment> partial;
  final int receivedCentavos;

  static final _date = DateFormat('MMM d, yyyy');
  static final _peso = NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 2,
  );

  static String date(DateTime d) => _date.format(d);

  /// Pesos without centavos when they are zero (₱2,950 rather than
  /// ₱2,950.00), which reads better in chat messages.
  static String peso(int centavos) {
    final text = _peso.format(centavos / 100);
    return text.endsWith('.00') ? text.substring(0, text.length - 3) : text;
  }

  Installment _inst(int sequence) =>
      loan.installments.firstWhere((i) => i.sequence == sequence);

  /// "#1–#4", "#1, #3" or "#5".
  static String ranges(List<int> seqs) {
    if (seqs.isEmpty) return '';
    final parts = <String>[];
    var start = seqs.first, prev = seqs.first;
    void flush() => parts.add(start == prev ? '#$start' : '#$start–#$prev');
    for (final s in seqs.skip(1)) {
      if (s == prev + 1) {
        prev = s;
        continue;
      }
      flush();
      start = prev = s;
    }
    flush();
    return parts.join(', ');
  }

  String get terms {
    final s = loan.summary;
    final rate = s.monthlyRateBasisPoints / 100;
    final amounts = loan.installments.map((i) => i.amountCentavos).toSet();
    final each = amounts.length == 1
        ? 'of ${peso(amounts.first)}'
        : 'of about ${peso(loan.installments.first.amountCentavos)}';
    return '${peso(s.principalCentavos)} at '
        '${rate.toStringAsFixed(rate % 1 == 0 ? 0 : 2)}% a month for '
        '${s.termMonths} ${s.termMonths == 1 ? 'month' : 'months'} = '
        '${peso(s.totalCentavos)} total, in ${loan.installments.length} '
        'installments $each.';
  }

  /// "finished #1 (₱350), paid #2 in full (₱2,950), ₱70 to #3"
  String describe(ExplainedPayment step) {
    final bits = <String>[
      for (final part in step.parts)
        if (part.paidInOne)
          'paid #${part.sequence} in full (${peso(part.amountCentavos)})'
        else if (part.finishes)
          'finished #${part.sequence} (${peso(part.amountCentavos)})'
        else
          '${peso(part.amountCentavos)} to #${part.sequence} '
              '(${peso(part.leftCentavos)} still due on #${part.sequence})',
      if (step.unappliedCentavos > 0)
        '${peso(step.unappliedCentavos)} extra, not yet applied',
    ];
    if (bits.isEmpty) return 'not applied yet';
    return bits.join(', ');
  }

  int get balanceCentavos => loan.outstandingCentavos;

  /// The oldest installment still owing, with what is left on it.
  ({Installment installment, int leftCentavos})? get nextDue {
    for (final i in [
      ...loan.installments,
    ]..sort((a, b) => a.sequence.compareTo(b.sequence))) {
      if (i.paidCentavos < i.amountCentavos) {
        return (
          installment: i,
          leftCentavos: i.amountCentavos - i.paidCentavos,
        );
      }
    }
    return null;
  }

  /// Status lines (also used in the copied text).
  List<String> statusLines({DateTime? today}) {
    final now = today ?? DateTime.now();
    final lines = <String>[
      if (paid.isNotEmpty)
        '${ranges(paid)} ${paid.length == 1 ? 'is' : 'are'} fully paid.',
      for (final i in partial)
        '#${i.sequence} is partly paid: ${peso(i.paidCentavos)} of '
            '${peso(i.amountCentavos)} '
            '(${peso(i.amountCentavos - i.paidCentavos)} left).',
      if (overdue.isNotEmpty)
        '${ranges(overdue)} ${overdue.length == 1 ? 'is' : 'are'} not paid '
            'yet and past due (since '
            '${date(_inst(overdue.first).dueDate)}).',
      if (upcoming.isNotEmpty)
        '${ranges(upcoming)} ${upcoming.length == 1 ? 'is' : 'are'} not due '
            'yet.',
      'Total paid: ${peso(receivedCentavos)}. Remaining balance: '
          '${peso(balanceCentavos)}.',
    ];
    final next = nextDue;
    if (next != null) {
      final late = next.installment.dueDate.isBefore(
        DateTime(now.year, now.month, now.day),
      );
      lines.add(
        'Next to pay: ${peso(next.leftCentavos)} for #${next.installment.sequence} '
        '(due ${date(next.installment.dueDate)}${late ? ', past due' : ''}).',
      );
    }
    return lines;
  }

  /// Plain text for Messenger/SMS: short lines, no table.
  String customerText({DateTime? today}) {
    final reference = 'LN-${loan.summary.id.substring(0, 8).toUpperCase()}';
    return [
      'Loan $reference – ${loan.summary.borrowerName}',
      terms,
      '',
      'How your payments were applied (oldest due first; interest, then '
          'principal):',
      for (final step in payments)
        '• ${date(step.payment.receivedOn)} – '
            '${peso(step.payment.amountCentavos)}: ${describe(step)}',
      if (payments.isEmpty) '• No payments yet.',
      '',
      ...statusLines(today: today),
    ].join('\n');
  }
}

/// Builds the explanation from the loan's own records (verified payments and
/// how each was split across installments).
LedgerExplanation explainLedger(LoanDetail loan, {DateTime? today}) {
  final now = today ?? DateTime.now();
  final day = DateTime(now.year, now.month, now.day);
  final due = {for (final i in loan.installments) i.sequence: i.amountCentavos};
  final applied = <int, int>{};
  final steps = <ExplainedPayment>[];
  for (final payment in [
    ...loan.payments,
  ]..sort((a, b) => a.receivedAt.compareTo(b.receivedAt))) {
    final parts = <ExplainedPart>[];
    var used = 0;
    for (final share in [
      ...payment.allocations,
    ]..sort((a, b) => a.sequence.compareTo(b.sequence))) {
      final before = applied[share.sequence] ?? 0;
      final after = before + share.totalCentavos;
      applied[share.sequence] = after;
      used += share.totalCentavos;
      final owed = due[share.sequence] ?? after;
      parts.add(
        ExplainedPart(
          sequence: share.sequence,
          amountCentavos: share.totalCentavos,
          dueCentavos: owed,
          leftCentavos: (owed - after).clamp(0, owed),
          paidInOne: before == 0 && after >= owed,
        ),
      );
    }
    steps.add(
      ExplainedPayment(
        payment: payment,
        parts: parts,
        unappliedCentavos: (payment.amountCentavos - used).clamp(
          0,
          payment.amountCentavos,
        ),
      ),
    );
  }
  final sorted = [...loan.installments]
    ..sort((a, b) => a.sequence.compareTo(b.sequence));
  return LedgerExplanation(
    loan: loan,
    payments: steps,
    paid: [
      for (final i in sorted)
        if (i.paidCentavos >= i.amountCentavos) i.sequence,
    ],
    partial: [
      for (final i in sorted)
        if (i.paidCentavos > 0 && i.paidCentavos < i.amountCentavos) i,
    ],
    overdue: [
      for (final i in sorted)
        if (i.paidCentavos == 0 && i.dueDate.isBefore(day)) i.sequence,
    ],
    upcoming: [
      for (final i in sorted)
        if (i.paidCentavos == 0 && !i.dueDate.isBefore(day)) i.sequence,
    ],
    receivedCentavos: loan.payments.fold(0, (sum, p) => sum + p.amountCentavos),
  );
}
