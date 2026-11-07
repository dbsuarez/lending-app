import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/models/models.dart';

class SharedLoanRepository {
  const SharedLoanRepository(this._client);
  final SupabaseClient _client;

  Future<SharedLoanStatus> fetch(String token) async {
    final results = await Future.wait([
      _client.rpc('get_shared_loan_status', params: {'p_token': token}),
      _client.rpc('get_shared_business_name', params: {'p_token': token}),
    ]);
    final result = results[0];
    final row = Map<String, dynamic>.from(result as Map);
    return SharedLoanStatus(
      businessName: results[1] as String,
      borrower: row['borrower'] as String,
      loanReference: row['loan_reference'] as String,
      loanStatus: row['loan_status'] as String,
      principalCentavos: row['principal_centavos'] as int,
      totalCentavos: row['total_centavos'] as int,
      verifiedPaidCentavos: row['verified_paid_centavos'] as int,
      pendingCentavos: row['pending_centavos'] as int,
      outstandingCentavos: row['outstanding_centavos'] as int,
      schedule: [
        for (final item in row['schedule'] as List)
          SharedScheduleItem(
            sequence: item['sequence'] as int,
            dueDate: DateTime.parse(item['due_date'] as String),
            scheduledCentavos: item['scheduled_centavos'] as int,
            paidCentavos: item['paid_centavos'] as int,
            status: item['status'] as String,
          ),
      ],
      payments: [
        for (final item in row['payments'] as List)
          SharedPaymentItem(
            receivedAt: DateTime.parse(item['received_at'] as String),
            amountCentavos: item['amount_centavos'] as int,
            method: item['method'] as String,
            status: item['status'] as String,
          ),
      ],
    );
  }
}
