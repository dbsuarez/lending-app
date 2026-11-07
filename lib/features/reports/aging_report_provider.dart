import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/app_config.dart';

class AgingReport {
  const AgingReport({
    required this.current,
    required this.days1to30,
    required this.days31to60,
    required this.days61to90,
    required this.days90Plus,
  });
  final int current, days1to30, days31to60, days61to90, days90Plus;
  int get total => current + days1to30 + days31to60 + days61to90 + days90Plus;
}

final agingReportProvider = FutureProvider<AgingReport?>((ref) async {
  if (!AppConfig.hasSupabase ||
      Supabase.instance.client.auth.currentUser == null) {
    return null;
  }
  final row = Map<String, dynamic>.from(
    await Supabase.instance.client.rpc('organization_aging_report') as Map,
  );
  return AgingReport(
    current: row['current'] as int,
    days1to30: row['days_1_30'] as int,
    days31to60: row['days_31_60'] as int,
    days61to90: row['days_61_90'] as int,
    days90Plus: row['days_90_plus'] as int,
  );
});
