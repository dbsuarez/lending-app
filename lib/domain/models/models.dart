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
  });
  final int sequence,
      amountCentavos,
      principalCentavos,
      interestCentavos,
      paidCentavos;
  final DateTime dueDate;
  final DateTime? lastPaymentAt;
  int get outstandingCentavos => amountCentavos - paidCentavos;
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
  });

  final String id, organizationId, borrowerId, borrowerName, status;
  final int principalCentavos,
      totalCentavos,
      monthlyRateBasisPoints,
      termMonths;
  final DateTime createdAt;
  final bool isPersonal;
}

class LoanDetail {
  const LoanDetail({required this.summary, required this.installments});

  final LoanSummary summary;
  final List<Installment> installments;
  int get paidCentavos =>
      installments.fold(0, (sum, item) => sum + item.paidCentavos);
  int get outstandingCentavos =>
      (summary.totalCentavos - paidCentavos).clamp(0, summary.totalCentavos);
}

class EarlyPayoffQuote {
  const EarlyPayoffQuote({
    required this.principalCentavos,
    required this.earnedInterestCentavos,
    required this.payoffCentavos,
    required this.payoffDate,
  });
  final int principalCentavos, earnedInterestCentavos, payoffCentavos;
  final DateTime payoffDate;
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
  });

  final String id, loanId, borrowerName, method, reference, status;
  final int amountCentavos;
  final int unappliedCentavos;
  final DateTime receivedAt;
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
  });
  final String id;
  final DateTime createdAt;
  final DateTime? revokedAt, lastAccessedAt;
  bool get isActive => revokedAt == null;
}

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
