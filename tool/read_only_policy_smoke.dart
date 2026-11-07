import 'dart:io';
import 'package:supabase/supabase.dart';

Future<void> main() async {
  final url = Platform.environment['SMOKE_SUPABASE_URL'];
  final key = Platform.environment['SMOKE_SUPABASE_KEY'];
  final email = Platform.environment['SMOKE_EMAIL'];
  final password = Platform.environment['SMOKE_PASSWORD'];
  if ([
    url,
    key,
    email,
    password,
  ].any((value) => value == null || value.isEmpty)) {
    throw StateError('Read-only smoke environment is incomplete.');
  }
  final client = SupabaseClient(url!, key!);
  await client.auth.signInWithPassword(email: email!, password: password!);
  final aging = await client.rpc('organization_aging_report');
  if (aging is! Map || !aging.containsKey('total')) {
    throw StateError('Aging RPC returned an unexpected response.');
  }
  final membership = await client
      .from('organization_members')
      .select('organization_id')
      .eq('user_id', client.auth.currentUser!.id)
      .eq('status', 'active')
      .limit(1)
      .single();
  final organization = await client
      .from('organizations')
      .select('name, policy_preferences')
      .eq('id', membership['organization_id'] as String)
      .single();
  final policy = organization['policy_preferences'];
  if (policy is! Map || policy['retention_years'] != 10) {
    throw StateError('Approved policy preferences are unavailable.');
  }
  await client.auth.signOut();
  stdout.writeln('Read-only policy RPC and organization preferences verified.');
}
