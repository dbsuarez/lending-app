import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/models/models.dart';

const _loanColumns =
    'id, organization_id, borrower_id, principal_centavos, total_centavos, '
    'monthly_rate_basis_points, term_months, status, is_personal, created_at, '
    'borrower:borrowers(first_name,last_name), '
    'disbursement:loan_disbursements(disbursed_on,voided_at), '
    'payments(id,status,received_at,amount_centavos)';

class SupabaseLoansRepository {
  SupabaseLoansRepository(this._client);

  final SupabaseClient _client;
  String? _organizationId;

  Future<String> organizationId() async {
    final cached = _organizationId;
    if (cached != null) return cached;
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const AuthException('Sign in is required.');
    final row = await _client
        .from('organization_members')
        .select('organization_id')
        .eq('user_id', userId)
        .eq('status', 'active')
        .limit(1)
        .single();
    return _organizationId = row['organization_id'] as String;
  }

  Future<List<LoanSummary>> fetchLoans() async {
    final orgId = await organizationId();
    final rows = await _client
        .from('loans')
        .select(_loanColumns)
        .eq('organization_id', orgId)
        .order('created_at', ascending: false);
    return rows.map(_fromRow).toList();
  }

  Future<String> createDraft({
    required String borrowerId,
    required LoanQuote quote,
    required DateTime firstDueDate,
    required List<int> paydayPattern,
    required String clientOperationId,
  }) async {
    final result = await _client.rpc(
      'create_loan_draft',
      params: {
        'p_organization_id': await organizationId(),
        'p_borrower_id': borrowerId,
        'p_principal_centavos': quote.principalCentavos,
        'p_monthly_rate_basis_points': quote.monthlyRateBasisPoints,
        'p_term_months': quote.termMonths,
        'p_first_due_date': _date(firstDueDate),
        'p_payday_pattern': paydayPattern,
        'p_installments': [
          for (final installment in quote.installments)
            {
              'sequence': installment.sequence,
              'due_date': _date(installment.dueDate),
              'principal_centavos': installment.principalCentavos,
              'interest_centavos': installment.interestCentavos,
              'scheduled_centavos': installment.amountCentavos,
            },
        ],
        'p_client_operation_id': clientOperationId,
      },
    );
    return result as String;
  }

  Future<LoanDetail> fetchLoan(String id) async {
    final orgId = await organizationId();
    final row = await _client
        .from('loans')
        .select(_loanColumns)
        .eq('organization_id', orgId)
        .eq('id', id)
        .single();
    final installmentRows = await _client
        .from('installments')
        .select(
          'sequence, due_date, principal_centavos, interest_centavos, scheduled_centavos',
        )
        .eq('organization_id', orgId)
        .eq('loan_id', id)
        .order('sequence');
    final allocationRows = await _client
        .from('payment_allocations')
        .select(
          'installment_id,payment_id,principal_centavos,interest_centavos,penalty_centavos,installment:installments!inner(sequence),payment:payments!inner(status,received_at)',
        )
        .eq('organization_id', orgId)
        .eq('installment.loan_id', id)
        .eq('payment.status', 'verified');
    final paidBySequence = <int, int>{};
    final paidAtBySequence = <int, DateTime>{};
    // payment id -> sequence -> amount applied, to place each payment on the
    // installment it paid the most of.
    final appliedByPayment = <String, Map<int, int>>{};
    // payment id -> sequence -> (interest, principal), for explanations.
    final splitByPayment = <String, Map<int, (int, int)>>{};
    for (final allocation in allocationRows) {
      final sequence = (allocation['installment'] as Map)['sequence'] as int;
      final split = splitByPayment.putIfAbsent(
        allocation['payment_id'] as String,
        () => {},
      );
      final before = split[sequence] ?? (0, 0);
      split[sequence] = (
        before.$1 +
            (allocation['interest_centavos'] as int) +
            (allocation['penalty_centavos'] as int),
        before.$2 + (allocation['principal_centavos'] as int),
      );
      final share =
          (allocation['principal_centavos'] as int) +
          (allocation['interest_centavos'] as int) +
          (allocation['penalty_centavos'] as int);
      final perSequence = appliedByPayment.putIfAbsent(
        allocation['payment_id'] as String,
        () => {},
      );
      perSequence[sequence] = (perSequence[sequence] ?? 0) + share;
      paidBySequence[sequence] =
          (paidBySequence[sequence] ?? 0) +
          (allocation['principal_centavos'] as int) +
          (allocation['interest_centavos'] as int) +
          (allocation['penalty_centavos'] as int);
      final receivedAt = DateTime.parse(
        (allocation['payment'] as Map)['received_at'] as String,
      );
      final current = paidAtBySequence[sequence];
      if (current == null || receivedAt.isAfter(current)) {
        paidAtBySequence[sequence] = receivedAt;
      }
    }
    return LoanDetail(
      summary: _fromRow(row),
      payments: [
        for (final payment in (row['payments'] as List?) ?? const [])
          if ((payment as Map)['status'] == 'verified')
            ReceivedPayment(
              amountCentavos: payment['amount_centavos'] as int,
              receivedAt: DateTime.parse(payment['received_at'] as String),
              appliedSequence: _largestShare(
                appliedByPayment[payment['id'] as String],
              ),
              allocations: [
                for (final entry
                    in (splitByPayment[payment['id'] as String]?.entries
                              .toList() ??
                          const <MapEntry<int, (int, int)>>[])
                      ..sort((a, b) => a.key.compareTo(b.key)))
                  AllocationShare(
                    sequence: entry.key,
                    interestCentavos: entry.value.$1,
                    principalCentavos: entry.value.$2,
                  ),
              ],
            ),
      ],
      installments: [
        for (final item in installmentRows)
          Installment(
            sequence: item['sequence'] as int,
            dueDate: DateTime.parse(item['due_date'] as String),
            amountCentavos: item['scheduled_centavos'] as int,
            principalCentavos: item['principal_centavos'] as int,
            interestCentavos: item['interest_centavos'] as int,
            paidCentavos: paidBySequence[item['sequence'] as int] ?? 0,
            lastPaymentAt: paidAtBySequence[item['sequence'] as int],
          ),
      ],
    );
  }

  Future<void> activate({
    required String loanId,
    required DateTime disbursedOn,
    required String method,
    required String reference,
    required String clientOperationId,
  }) async {
    await _client.rpc(
      'activate_loan',
      params: {
        'p_loan_id': loanId,
        'p_disbursed_on': _date(disbursedOn),
        'p_method': method,
        'p_reference': reference,
        'p_client_operation_id': clientOperationId,
      },
    );
  }

  /// Returns the loan's active link, creating one only if none exists.
  Future<CustomerLink> createShareLink({required String loanId}) async {
    final result = Map<String, dynamic>.from(
      await _client.rpc(
            'create_loan_share_link',
            params: {
              'p_loan_id': loanId,
              'p_expires_at': '9999-12-31T23:59:59Z',
            },
          )
          as Map,
    );
    return (
      id: result['id'] as String,
      token: result['token'] as String,
      reused: result['reused'] as bool? ?? false,
    );
  }

  Future<List<LoanShareLinkSummary>> fetchShareLinks(String loanId) async {
    final rows = await _client
        .from('loan_share_links')
        .select('id, created_at, revoked_at, last_accessed_at, token')
        .eq('loan_id', loanId)
        .order('created_at', ascending: false);
    return [
      for (final row in rows)
        LoanShareLinkSummary(
          id: row['id'] as String,
          createdAt: DateTime.parse(row['created_at'] as String),
          revokedAt: row['revoked_at'] == null
              ? null
              : DateTime.parse(row['revoked_at'] as String),
          lastAccessedAt: row['last_accessed_at'] == null
              ? null
              : DateTime.parse(row['last_accessed_at'] as String),
          token: row['token'] as String?,
        ),
    ];
  }

  Future<void> revokeShareLink(String linkId) =>
      _client.rpc('revoke_loan_share_link', params: {'p_link_id': linkId});

  Future<void> setPersonal({required String loanId, required bool personal}) =>
      _client.rpc(
        'set_loan_personal',
        params: {'p_loan_id': loanId, 'p_personal': personal},
      );

  Future<void> cancelDraft({required String loanId, required String reason}) =>
      _client.rpc(
        'cancel_loan_draft',
        params: {'p_loan_id': loanId, 'p_reason': reason},
      );

  /// Returns the amendment id.
  Future<String> amendInstallmentDueDate({
    required String loanId,
    required int sequence,
    required DateTime newDueDate,
    required String reason,
    required DateTime consentDate,
    required String clientOperationId,
  }) async =>
      await _client.rpc(
            'amend_installment_due_date',
            params: {
              'p_loan_id': loanId,
              'p_sequence': sequence,
              'p_new_due_date': _date(newDueDate),
              'p_reason': reason,
              'p_consent_date': _date(consentDate),
              'p_supporting_document_id': null,
              'p_client_operation_id': clientOperationId,
            },
          )
          as String;

  Future<String> refinance({
    required String sourceLoanId,
    required LoanQuote quote,
    required String reason,
    required DateTime consentDate,
    required String clientOperationId,
  }) async =>
      await _client.rpc(
            'refinance_loan',
            params: {
              'p_source_loan_id': sourceLoanId,
              'p_principal_centavos': quote.principalCentavos,
              'p_monthly_rate_basis_points': quote.monthlyRateBasisPoints,
              'p_term_months': quote.termMonths,
              'p_installments': [
                for (final installment in quote.installments)
                  {
                    'sequence': installment.sequence,
                    'due_date': _date(installment.dueDate),
                    'principal_centavos': installment.principalCentavos,
                    'interest_centavos': installment.interestCentavos,
                    'scheduled_centavos': installment.amountCentavos,
                  },
              ],
              'p_reason': reason,
              'p_consent_date': _date(consentDate),
              'p_supporting_document_id': null,
              'p_client_operation_id': clientOperationId,
            },
          )
          as String;

  Future<EarlyPayoffQuote> earlyPayoffQuote(
    String loanId,
    DateTime date,
  ) async {
    final row = Map<String, dynamic>.from(
      await _client.rpc(
            'early_payoff_quote',
            params: {'p_loan_id': loanId, 'p_payoff_date': _date(date)},
          )
          as Map,
    );
    return EarlyPayoffQuote(
      principalCentavos: row['principal_centavos'] as int,
      earnedInterestCentavos: row['earned_interest_centavos'] as int,
      payoffCentavos: row['payoff_centavos'] as int,
      payoffDate: DateTime.parse(row['payoff_date'] as String),
    );
  }

  /// Returns the settlement payment id.
  Future<String> recordEarlyPayoff({
    required String loanId,
    required DateTime date,
    required String method,
    required String reference,
    required String clientOperationId,
    required String deviceId,
  }) async =>
      await _client.rpc(
            'record_early_payoff',
            params: {
              'p_loan_id': loanId,
              'p_payoff_date': _date(date),
              'p_method': method,
              'p_reference': reference,
              'p_client_operation_id': clientOperationId,
              'p_device_id': deviceId,
            },
          )
          as String;

  // Undo (see migration 202611070033_transaction_undo.sql).
  Future<void> undoActivation(String loanId) =>
      _client.rpc('undo_loan_activation', params: {'p_loan_id': loanId});

  Future<void> undoDueDateAmendment(String amendmentId) => _client.rpc(
    'undo_due_date_amendment',
    params: {'p_amendment_id': amendmentId},
  );

  Future<void> undoEarlyPayoff(String paymentId) =>
      _client.rpc('undo_early_payoff', params: {'p_payment_id': paymentId});

  Future<List<PaymentSummary>> fetchLoanPayments(String loanId) async {
    final rows = await _client
        .from('payments')
        .select('id, amount_centavos, received_at, method, reference, status')
        .eq('organization_id', await organizationId())
        .eq('loan_id', loanId)
        .order('received_at', ascending: false);
    return [
      for (final row in rows)
        PaymentSummary(
          id: row['id'] as String,
          loanId: loanId,
          borrowerName: '',
          amountCentavos: row['amount_centavos'] as int,
          receivedAt: DateTime.parse(row['received_at'] as String),
          method: row['method'] as String,
          reference: row['reference'] as String? ?? '',
          status: row['status'] as String,
        ),
    ];
  }

  Future<List<AuditEventSummary>> fetchLoanActivity(String loanId) async {
    final rows = await _client
        .from('audit_events')
        .select('id, action, record_type, record_id, payload, created_at')
        .eq('organization_id', await organizationId())
        .or('record_id.eq.$loanId,payload->>loan_id.eq.$loanId')
        .order('created_at', ascending: false)
        .limit(100);
    return [
      for (final row in rows)
        AuditEventSummary(
          id: row['id'] as String,
          action: row['action'] as String,
          recordType: row['record_type'] as String,
          recordId: row['record_id'] as String,
          createdAt: DateTime.parse(row['created_at'] as String),
          payload: Map<String, dynamic>.from(
            row['payload'] as Map<String, dynamic>,
          ),
        ),
    ];
  }

  /// The installment sequence that received the largest share (earliest on
  /// a tie), or null if nothing was applied.
  static int? _largestShare(Map<int, int>? perSequence) {
    if (perSequence == null || perSequence.isEmpty) return null;
    final entries = perSequence.entries.toList()
      ..sort(
        (a, b) => b.value != a.value
            ? b.value.compareTo(a.value)
            : a.key.compareTo(b.key),
      );
    return entries.first.key;
  }

  LoanSummary _fromRow(Map<String, dynamic> row) {
    final borrower = row['borrower'] as Map<String, dynamic>;
    // A loan has at most one active disbursement; undone ones are voided.
    final rawDisbursement = row['disbursement'];
    final disbursements = rawDisbursement is List
        ? rawDisbursement.cast<Map>()
        : [if (rawDisbursement is Map) rawDisbursement];
    final disbursement = disbursements
        .where((item) => item['voided_at'] == null)
        .firstOrNull;
    final disbursedOn = disbursement?['disbursed_on'] as String?;
    final status = row['status'] as String;
    DateTime? paidOn;
    if (status == 'fully_paid') {
      for (final payment in (row['payments'] as List?) ?? const []) {
        if ((payment as Map)['status'] != 'verified') continue;
        final receivedAt = DateTime.parse(payment['received_at'] as String);
        if (paidOn == null || receivedAt.isAfter(paidOn)) paidOn = receivedAt;
      }
    }
    return LoanSummary(
      id: row['id'] as String,
      organizationId: row['organization_id'] as String,
      borrowerId: row['borrower_id'] as String,
      borrowerName: '${borrower['last_name']}, ${borrower['first_name']}',
      principalCentavos: row['principal_centavos'] as int,
      totalCentavos: row['total_centavos'] as int,
      monthlyRateBasisPoints: row['monthly_rate_basis_points'] as int,
      termMonths: row['term_months'] as int,
      status: status,
      createdAt: DateTime.parse(row['created_at'] as String),
      isPersonal: row['is_personal'] as bool? ?? false,
      borrowedOn: disbursedOn == null ? null : DateTime.parse(disbursedOn),
      paidOn: paidOn,
    );
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
