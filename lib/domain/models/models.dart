class Borrower {
  const Borrower({
    required this.id,
    required this.organizationId,
    required this.firstName,
    required this.lastName,
    this.phone = '',
    this.email = '',
    this.address = '',
    this.updatedAt,
  });
  final String id, organizationId, firstName, lastName, phone, email, address;
  final DateTime? updatedAt;
  String get displayName => '$lastName, $firstName';
}

class Installment {
  const Installment({
    required this.sequence,
    required this.dueDate,
    required this.amountCentavos,
    required this.principalCentavos,
    required this.interestCentavos,
    this.paidCentavos = 0,
    this.lastPaymentAt,
    this.penaltyCentavos = 0,
  });

  /// [amountCentavos] includes [penaltyCentavos] (penalties charged so far).
  final int sequence,
      amountCentavos,
      principalCentavos,
      interestCentavos,
      paidCentavos,
      penaltyCentavos;
  final DateTime dueDate;
  final DateTime? lastPaymentAt;
  int get outstandingCentavos => amountCentavos - paidCentavos;
}

/// How a loan charges late penalties (fixed once the loan is released).
class PenaltyPolicy {
  const PenaltyPolicy({
    this.mode = 'none',
    this.amountCentavos,
    this.rateBasisPoints,
    this.graceDays = 3,
  });

  /// none, fixed, percentage or manual.
  final String mode;
  final int? amountCentavos, rateBasisPoints;
  final int graceDays;

  static const none = PenaltyPolicy();

  bool get charges => mode != 'none';

  Map<String, dynamic> toJson() => {
    'mode': mode,
    'grace_days': graceDays,
    if (mode == 'fixed') 'amount_centavos': amountCentavos,
    if (mode == 'percentage') 'rate_basis_points': rateBasisPoints,
  };

  static PenaltyPolicy fromJson(Object? json) {
    if (json is! Map) return none;
    return PenaltyPolicy(
      mode: '${json['mode'] ?? 'none'}',
      amountCentavos: (json['amount_centavos'] as num?)?.toInt(),
      rateBasisPoints: (json['rate_basis_points'] as num?)?.toInt(),
      graceDays: (json['grace_days'] as num?)?.toInt() ?? 3,
    );
  }

  String get typeLabel => switch (mode) {
    'fixed' => 'Fixed amount',
    'percentage' => 'Percentage of overdue',
    'manual' => 'Manual',
    _ => 'None',
  };
}

/// One penalty charged on an installment.
class PenaltyCharge {
  const PenaltyCharge({
    required this.id,
    required this.sequence,
    required this.chargeDate,
    required this.amountCentavos,
    required this.source,
    this.note,
    this.waived = false,
    this.waiveReason,
  });
  final String id, source;
  final int sequence, amountCentavos;
  final DateTime chargeDate;
  final String? note, waiveReason;
  final bool waived;
}

class LoanQuote {
  const LoanQuote({
    required this.principalCentavos,
    required this.interestCentavos,
    required this.totalCentavos,
    required this.monthlyRateBasisPoints,
    required this.termMonths,
    required this.installments,
  });
  final int principalCentavos,
      interestCentavos,
      totalCentavos,
      monthlyRateBasisPoints,
      termMonths;
  final List<Installment> installments;
}

class LoanSummary {
  const LoanSummary({
    required this.id,
    required this.organizationId,
    required this.borrowerId,
    required this.borrowerName,
    required this.principalCentavos,
    required this.totalCentavos,
    required this.monthlyRateBasisPoints,
    required this.termMonths,
    required this.status,
    required this.createdAt,
    this.isPersonal = false,
    this.borrowedOn,
    this.paidOn,
  });

  final String id, organizationId, borrowerId, borrowerName, status;
  final int principalCentavos,
      totalCentavos,
      monthlyRateBasisPoints,
      termMonths;
  final DateTime createdAt;
  final bool isPersonal;

  /// Disbursement date; null until the loan is released (drafts, cancelled).
  final DateTime? borrowedOn;

  /// Date of the last verified payment, set only once the loan is fully paid.
  final DateTime? paidOn;

  /// Date used to order loans: disbursement date, else creation date.
  DateTime get borrowedSortDate => borrowedOn ?? createdAt;

  LoanSummary copyWith({
    String? status,
    bool? isPersonal,
    DateTime? borrowedOn,
    bool clearBorrowedOn = false,
  }) => LoanSummary(
    id: id,
    organizationId: organizationId,
    borrowerId: borrowerId,
    borrowerName: borrowerName,
    principalCentavos: principalCentavos,
    totalCentavos: totalCentavos,
    monthlyRateBasisPoints: monthlyRateBasisPoints,
    termMonths: termMonths,
    status: status ?? this.status,
    createdAt: createdAt,
    isPersonal: isPersonal ?? this.isPersonal,
    borrowedOn: clearBorrowedOn ? null : borrowedOn ?? this.borrowedOn,
    paidOn: paidOn,
  );
}

/// The part of one payment credited to one installment.
class AllocationShare {
  const AllocationShare({
    required this.sequence,
    required this.interestCentavos,
    required this.principalCentavos,
  });
  final int sequence, interestCentavos, principalCentavos;
  int get totalCentavos => interestCentavos + principalCentavos;
}

/// A verified payment as received from the borrower (before it is split
/// across installments).
class ReceivedPayment {
  const ReceivedPayment({
    required this.amountCentavos,
    required this.receivedAt,
    this.appliedSequence,
    this.allocations = const [],
  });

  /// How this payment was split across installments, in sequence order.
  final List<AllocationShare> allocations;
  final int amountCentavos;
  final DateTime receivedAt;

  /// The installment this payment paid the most of (from its allocations).
  /// The ledger shows the payment on that row, so a payment entered a day
  /// late still appears on the cutoff it was meant for. Null when the
  /// payment was not applied to any installment (e.g. an overpayment).
  final int? appliedSequence;

  /// Calendar day received, in local time (what the borrower sees).
  DateTime get receivedOn {
    final local = receivedAt.toLocal();
    return DateTime(local.year, local.month, local.day);
  }
}

/// What the edit form needs beyond [LoanDetail]: the payday pattern, first
/// due date and the money-release record (null for drafts).
class LoanEditTerms {
  const LoanEditTerms({
    required this.firstDueDate,
    required this.paydayPattern,
    this.disbursedOn,
    this.method,
    this.reference,
    this.penaltyPolicy = PenaltyPolicy.none,
  });
  final PenaltyPolicy penaltyPolicy;
  final DateTime firstDueDate;
  final List<int> paydayPattern;
  final DateTime? disbursedOn;
  final String? method, reference;
}

class LoanDetail {
  const LoanDetail({
    required this.summary,
    required this.installments,
    this.payments = const [],
  });

  final LoanSummary summary;
  final List<Installment> installments;

  /// Verified payments on this loan, as received.
  final List<ReceivedPayment> payments;

  /// Verified payments received after the final due date (late), which no
  /// cutoff row covers.
  List<ReceivedPayment> get paymentsAfterFinalDue {
    if (installments.isEmpty) return const [];
    final finalDue = installments
        .map((i) => i.dueDate)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final lastDay = DateTime(finalDue.year, finalDue.month, finalDue.day);
    return [
      for (final p in payments)
        if (p.appliedSequence == null && p.receivedOn.isAfter(lastDay)) p,
    ]..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
  }

  int get paidCentavos =>
      installments.fold(0, (sum, item) => sum + item.paidCentavos);
  int get outstandingCentavos =>
      (summary.totalCentavos - paidCentavos).clamp(0, summary.totalCentavos);

  /// Payment ledger rows in installment order with a running balance.
  /// Shared by the on-screen ledger and the printed ledger PDF.
  List<LedgerRow> ledgerRows({DateTime? asOf}) {
    final today = asOf ?? DateTime.now();
    var runningBalance = summary.totalCentavos;
    final sorted = [...installments]
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    final received = [...payments]
      ..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
    DateTime? previousDue;
    return [
      for (final item in sorted)
        LedgerRow(
          installment: item,
          // What the borrower actually paid during this cutoff: verified
          // payments received after the previous due date, up to this one.
          received: () {
            final due = DateTime(
              item.dueDate.year,
              item.dueDate.month,
              item.dueDate.day,
            );
            final from = previousDue;
            previousDue = due;
            return [
              for (final p in received)
                // Applied payments go on the installment they paid most of;
                // unapplied ones fall back to the cutoff their date is in.
                if (p.appliedSequence != null
                    ? p.appliedSequence == item.sequence
                    : !p.receivedOn.isAfter(due) &&
                          (from == null || p.receivedOn.isAfter(from)))
                  p,
            ];
          }(),
          endingBalanceCentavos: runningBalance =
              (runningBalance - item.paidCentavos).clamp(
                0,
                summary.totalCentavos,
              ),
          status: item.paidCentavos >= item.amountCentavos
              ? 'paid'
              : item.paidCentavos > 0
              ? 'partial'
              : item.dueDate.isBefore(today)
              ? 'overdue'
              : 'upcoming',
        ),
    ];
  }
}

class LedgerRow {
  const LedgerRow({
    required this.installment,
    required this.endingBalanceCentavos,
    required this.status,
    this.received = const [],
  });
  final Installment installment;
  final int endingBalanceCentavos;

  /// Payments actually received during this cutoff (may be more or less
  /// than what was applied to this installment).
  final List<ReceivedPayment> received;
  int get receivedCentavos =>
      received.fold(0, (sum, p) => sum + p.amountCentavos);

  /// One of paid, partial, overdue, upcoming.
  final String status;
}

/// How much interest an early payoff charges (see the payoff migration).
enum PayoffRule {
  waiveFuture(
    'waive_future',
    'Waive future interest',
    'Interest only for installments due on or before the payoff date.',
  ),
  currentMonth(
    'current_month',
    "Charge this month's interest",
    'Interest for every installment due in the payoff month, even if not due yet.',
  ),
  allInterest(
    'all_interest',
    'Charge all remaining interest',
    'No discount: the same total as paying on schedule.',
  );

  const PayoffRule(this.code, this.label, this.explanation);
  final String code, label, explanation;
}

class EarlyPayoffQuote {
  const EarlyPayoffQuote({
    required this.principalCentavos,
    required this.earnedInterestCentavos,
    required this.payoffCentavos,
    required this.payoffDate,
    this.rule = PayoffRule.waiveFuture,
  });
  final int principalCentavos, earnedInterestCentavos, payoffCentavos;
  final DateTime payoffDate;
  final PayoffRule rule;
}

class PaymentSummary {
  const PaymentSummary({
    required this.id,
    required this.loanId,
    required this.borrowerName,
    required this.amountCentavos,
    required this.receivedAt,
    required this.method,
    required this.reference,
    required this.status,
    this.unappliedCentavos = 0,
    this.lateReason,
  });

  final String id, loanId, borrowerName, method, reference, status;
  final int amountCentavos;
  final int unappliedCentavos;
  final DateTime receivedAt;

  /// Why the payment came after its due date, when one was given.
  final String? lateReason;
}

class AuditEventSummary {
  const AuditEventSummary({
    required this.id,
    required this.action,
    required this.recordType,
    required this.recordId,
    required this.createdAt,
    required this.payload,
  });

  final String id, action, recordType, recordId;
  final DateTime createdAt;
  final Map<String, dynamic> payload;
}

class SharedLoanStatus {
  const SharedLoanStatus({
    required this.businessName,
    required this.borrower,
    required this.loanReference,
    required this.loanStatus,
    required this.principalCentavos,
    required this.totalCentavos,
    required this.verifiedPaidCentavos,
    required this.pendingCentavos,
    required this.outstandingCentavos,
    required this.schedule,
    required this.payments,
  });

  final String businessName, borrower, loanReference, loanStatus;
  final int principalCentavos,
      totalCentavos,
      verifiedPaidCentavos,
      pendingCentavos,
      outstandingCentavos;
  final List<SharedScheduleItem> schedule;
  final List<SharedPaymentItem> payments;
}

class SharedScheduleItem {
  const SharedScheduleItem({
    required this.sequence,
    required this.dueDate,
    required this.scheduledCentavos,
    required this.paidCentavos,
    required this.status,
  });
  final int sequence, scheduledCentavos, paidCentavos;
  final DateTime dueDate;
  final String status;
}

class SharedPaymentItem {
  const SharedPaymentItem({
    required this.receivedAt,
    required this.amountCentavos,
    required this.method,
    required this.status,
  });
  final DateTime receivedAt;
  final int amountCentavos;
  final String method, status;
}

class LoanShareLinkSummary {
  const LoanShareLinkSummary({
    required this.id,
    required this.createdAt,
    required this.revokedAt,
    required this.lastAccessedAt,
    this.token,
  });
  final String id;
  final DateTime createdAt;
  final DateTime? revokedAt, lastAccessedAt;

  /// Null for links created before tokens were stored; those still work but
  /// cannot be copied again.
  final String? token;
  bool get isActive => revokedAt == null;
  bool get canCopy => isActive && token != null;
}

/// Result of "get customer link": the loan's link, and whether it already
/// existed (reused) or was just created.
typedef CustomerLink = ({String id, String token, bool reused});

class CollectionActivity {
  const CollectionActivity({
    required this.id,
    required this.loanId,
    required this.borrowerName,
    required this.type,
    required this.outcome,
    required this.notes,
    required this.promisedOn,
    required this.promisedAmountCentavos,
    required this.contactedAt,
  });

  final String id, loanId, borrowerName, type, outcome, notes;
  final DateTime? promisedOn;
  final int? promisedAmountCentavos;
  final DateTime contactedAt;
}
