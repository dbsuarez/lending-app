import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/models/models.dart';

class SupabaseBorrowersRepository {
  SupabaseBorrowersRepository(this._client);

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

  Future<List<Borrower>> fetchActive() async {
    final orgId = await organizationId();
    final rows = await _client
        .from('borrowers')
        .select(
          'id, organization_id, first_name, last_name, phone, email, address, updated_at',
        )
        .eq('organization_id', orgId)
        .isFilter('archived_at', null)
        .order('last_name')
        .order('first_name');
    return rows.map(_fromRow).toList();
  }

  Future<List<Borrower>> fetchArchived() async {
    final rows = await _client
        .from('borrowers')
        .select(
          'id, organization_id, first_name, last_name, phone, email, address, updated_at',
        )
        .eq('organization_id', await organizationId())
        .not('archived_at', 'is', null)
        .order('last_name')
        .order('first_name');
    return rows.map(_fromRow).toList();
  }

  Future<String> save({
    String? id,
    required String firstName,
    required String lastName,
    required String phone,
    required String email,
    required String address,
    DateTime? expectedUpdatedAt,
  }) async {
    final params = <String, dynamic>{
      'p_id': id,
      'p_first_name': firstName.trim(),
      'p_last_name': lastName.trim(),
      'p_phone': _nullIfEmpty(phone),
      'p_email': _nullIfEmpty(email),
      'p_address': _nullIfEmpty(address),
    };
    if (id == null) {
      final borrowerId = await _client.rpc('save_borrower', params: params);
      return borrowerId as String;
    } else {
      final borrowerId = await _client.rpc(
        'update_borrower_if_current',
        params: {
          ...params,
          'p_expected_updated_at': expectedUpdatedAt?.toUtc().toIso8601String(),
        },
      );
      return borrowerId as String;
    }
  }

  Future<void> recordConsent(String borrowerId) => _client.rpc(
    'record_borrower_consent',
    params: {'p_borrower_id': borrowerId},
  );

  Future<void> archive(String id) async {
    await _client.rpc(
      'set_borrower_archived',
      params: {'p_borrower_id': id, 'p_archived': true},
    );
  }

  Future<void> restore(String id) async {
    await _client.rpc(
      'set_borrower_archived',
      params: {'p_borrower_id': id, 'p_archived': false},
    );
  }

  Borrower _fromRow(Map<String, dynamic> row) => Borrower(
    id: row['id'] as String,
    organizationId: row['organization_id'] as String,
    firstName: row['first_name'] as String,
    lastName: row['last_name'] as String,
    phone: row['phone'] as String? ?? '',
    email: row['email'] as String? ?? '',
    address: row['address'] as String? ?? '',
    updatedAt: row['updated_at'] == null
        ? null
        : DateTime.parse(row['updated_at'] as String),
  );

  String? _nullIfEmpty(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
