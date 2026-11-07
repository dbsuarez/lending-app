import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/models/models.dart';

class SupabaseAuditRepository {
  SupabaseAuditRepository(this._client);
  final SupabaseClient _client;

  Future<List<AuditEventSummary>> fetchRecent() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const AuthException('Sign in is required.');
    final membership = await _client
        .from('organization_members')
        .select('organization_id')
        .eq('user_id', userId)
        .eq('status', 'active')
        .limit(1)
        .single();
    final rows = await _client
        .from('audit_events')
        .select('id, action, record_type, record_id, payload, created_at')
        .eq('organization_id', membership['organization_id'] as String)
        .order('created_at', ascending: false)
        .limit(200);
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
}
