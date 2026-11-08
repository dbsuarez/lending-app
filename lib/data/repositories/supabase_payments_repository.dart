import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/models/models.dart';

class SupabasePaymentsRepository {
  SupabasePaymentsRepository(this._client);
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

  Future<List<PaymentSummary>> fetchPayments() async {
    final rows = await _client
        .from('payments')
        .select(
          'id, loan_id, amount_centavos, received_at, method, reference, status, unapplied_centavos, loan:loans(borrower:borrowers(first_name,last_name))',
        )
        .eq('organization_id', await organizationId())
        .order('received_at', ascending: false);
    return [for (final row in rows) _fromRow(row)];
  }

  Future<String> recordPending({
    required String loanId,
    required int amountCentavos,
    required DateTime receivedAt,
    required String method,
    required String reference,
    required String clientOperationId,
    required String deviceId,
  }) async {
    final result = await _client.rpc(
      'record_pending_payment',
      params: {
        'p_loan_id': loanId,
        'p_amount_centavos': amountCentavos,
        'p_received_at': receivedAt.toUtc().toIso8601String(),
        'p_method': method,
        'p_reference': reference,
        'p_client_operation_id': clientOperationId,
        'p_device_id': deviceId,
      },
    );
    return result as String;
  }

  Future<void> reject({required String paymentId, required String reason}) =>
      _client.rpc(
        'reject_payment',
        params: {'p_payment_id': paymentId, 'p_reason': reason},
      );

  Future<void> verify(String paymentId) =>
      _client.rpc('verify_payment', params: {'p_payment_id': paymentId});

  Future<void> reverse({required String paymentId, required String reason}) =>
      _client.rpc(
        'reverse_payment',
        params: {'p_payment_id': paymentId, 'p_reason': reason},
      );

  /// Returns the correction id (see 202611070035_payment_corrections.sql).
  Future<String> correctDetails({
    required String paymentId,
    required DateTime receivedAt,
    required String method,
    required String reference,
    required String reason,
  }) async =>
      await _client.rpc(
            'correct_payment_details',
            params: {
              'p_payment_id': paymentId,
              'p_received_at': receivedAt.toUtc().toIso8601String(),
              'p_method': method,
              'p_reference': reference,
              'p_reason': reason,
            },
          )
          as String;

  Future<void> undoCorrection(String correctionId) => _client.rpc(
    'undo_payment_correction',
    params: {'p_correction_id': correctionId},
  );

  // Undo (see migration 202611070033_transaction_undo.sql).
  Future<void> undoRecord(String paymentId) =>
      _client.rpc('undo_payment_record', params: {'p_payment_id': paymentId});

  Future<void> undoVerification(String paymentId) => _client.rpc(
    'undo_payment_verification',
    params: {'p_payment_id': paymentId},
  );

  PaymentSummary _fromRow(Map<String, dynamic> row) {
    final loan = row['loan'] as Map<String, dynamic>;
    final borrower = loan['borrower'] as Map<String, dynamic>;
    return PaymentSummary(
      id: row['id'] as String,
      loanId: row['loan_id'] as String,
      borrowerName: '${borrower['last_name']}, ${borrower['first_name']}',
      amountCentavos: row['amount_centavos'] as int,
      receivedAt: DateTime.parse(row['received_at'] as String),
      method: row['method'] as String,
      reference: row['reference'] as String? ?? '',
      status: row['status'] as String,
      unappliedCentavos: row['unapplied_centavos'] as int? ?? 0,
    );
  }
}
