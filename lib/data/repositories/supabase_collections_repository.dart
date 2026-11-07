import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/models/models.dart';

class SupabaseCollectionsRepository {
  SupabaseCollectionsRepository(this._client);
  final SupabaseClient _client;

  Future<List<CollectionActivity>> fetchActivities() async {
    final rows = await _client
        .from('collection_activities')
        .select(
          'id, loan_id, activity_type, outcome, notes, promised_on, promised_amount_centavos, contacted_at, loan:loans(borrower:borrowers(first_name,last_name))',
        )
        .isFilter('undone_at', null)
        .order('contacted_at', ascending: false)
        .limit(100);
    return [
      for (final row in rows)
        CollectionActivity(
          id: row['id'] as String,
          loanId: row['loan_id'] as String,
          borrowerName: _borrowerName(row),
          type: row['activity_type'] as String,
          outcome: row['outcome'] as String,
          notes: row['notes'] as String? ?? '',
          promisedOn: row['promised_on'] == null
              ? null
              : DateTime.parse(row['promised_on'] as String),
          promisedAmountCentavos: row['promised_amount_centavos'] as int?,
          contactedAt: DateTime.parse(row['contacted_at'] as String),
        ),
    ];
  }

  /// Returns the activity id.
  Future<String> record({
    required String loanId,
    required String type,
    required String outcome,
    required String notes,
    DateTime? promisedOn,
    int? promisedAmountCentavos,
    required String clientOperationId,
  }) async =>
      await _client.rpc(
            'record_collection_activity',
            params: {
              'p_loan_id': loanId,
              'p_activity_type': type,
              'p_outcome': outcome,
              'p_notes': notes,
              'p_promised_on': promisedOn == null ? null : _date(promisedOn),
              'p_promised_amount_centavos': promisedAmountCentavos,
              'p_client_operation_id': clientOperationId,
            },
          )
          as String;

  Future<void> undo(String activityId) => _client.rpc(
    'undo_collection_activity',
    params: {'p_activity_id': activityId},
  );

  String _borrowerName(Map<String, dynamic> row) {
    final loan = row['loan'] as Map<String, dynamic>;
    final borrower = loan['borrower'] as Map<String, dynamic>;
    return '${borrower['last_name']}, ${borrower['first_name']}';
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
