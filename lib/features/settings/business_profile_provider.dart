import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/app_config.dart';

class BusinessProfile {
  const BusinessProfile({
    required this.name,
    this.phone = '',
    this.email = '',
    this.address = '',
    this.role = 'viewer',
  });
  final String name, phone, email, address, role;
  static const fallback = BusinessProfile(name: 'Lending Manager');
}

final businessProfileProvider = FutureProvider<BusinessProfile>((ref) async {
  if (!AppConfig.hasSupabase ||
      Supabase.instance.client.auth.currentUser == null) {
    return BusinessProfile.fallback;
  }
  final client = Supabase.instance.client;
  final membership = await client
      .from('organization_members')
      .select('organization_id, role')
      .eq('user_id', client.auth.currentUser!.id)
      .eq('status', 'active')
      .limit(1)
      .single();
  final row = await client
      .from('organizations')
      .select('name, phone, email, address')
      .eq('id', membership['organization_id'] as String)
      .single();
  return BusinessProfile(
    name: (row['name'] as String?)?.trim().isNotEmpty == true
        ? (row['name'] as String).trim()
        : BusinessProfile.fallback.name,
    phone: row['phone'] as String? ?? '',
    email: row['email'] as String? ?? '',
    address: row['address'] as String? ?? '',
    role: membership['role'] as String? ?? 'viewer',
  );
});
