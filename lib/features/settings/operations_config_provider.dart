import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/app_config.dart';

class OperationsConfig {
  const OperationsConfig({
    required this.rates,
    required this.paydays,
    required this.paymentMethods,
  });
  final List<num> rates;
  final List<List<int>> paydays;
  final List<String> paymentMethods;
  static const defaults = OperationsConfig(
    rates: [3, 6, 10],
    paydays: [
      [15, 30],
      [5, 20],
    ],
    paymentMethods: ['Cash', 'GCash', 'AUB', 'MariBank', 'PalPay'],
  );
}

final operationsConfigProvider =
    AsyncNotifierProvider<OperationsConfigController, OperationsConfig>(
      OperationsConfigController.new,
    );

class OperationsConfigController extends AsyncNotifier<OperationsConfig> {
  String? organizationId;
  @override
  Future<OperationsConfig> build() async {
    if (!AppConfig.hasSupabase ||
        Supabase.instance.client.auth.currentUser == null) {
      return OperationsConfig.defaults;
    }
    final client = Supabase.instance.client;
    final membership = await client
        .from('organization_members')
        .select('organization_id')
        .eq('user_id', client.auth.currentUser!.id)
        .eq('status', 'active')
        .limit(1)
        .single();
    organizationId = membership['organization_id'] as String;
    final row = await client
        .from('organizations')
        .select('operational_preferences')
        .eq('id', organizationId!)
        .single();
    return _parse(
      Map<String, dynamic>.from(row['operational_preferences'] as Map),
    );
  }

  Future<bool> save(OperationsConfig config) async {
    if (organizationId == null) return false;
    try {
      await Supabase.instance.client
          .from('organizations')
          .update({
            'operational_preferences': {
              'rate_presets': config.rates,
              'payday_presets': config.paydays,
              'payment_methods': config.paymentMethods,
            },
          })
          .eq('id', organizationId!);
      state = AsyncData(config);
      return true;
    } catch (_) {
      return false;
    }
  }

  OperationsConfig _parse(Map<String, dynamic> value) {
    final rates = (value['rate_presets'] as List? ?? const [3, 6, 10])
        .whereType<num>()
        .where((v) => v >= 0)
        .toList();
    final paydays = <List<int>>[];
    for (final raw in value['payday_presets'] as List? ?? const []) {
      if (raw is List) {
        final days =
            raw
                .whereType<num>()
                .map((v) => v.toInt())
                .where((v) => v >= 1 && v <= 31)
                .toSet()
                .toList()
              ..sort();
        if (days.isNotEmpty) paydays.add(days);
      }
    }
    final methods = (value['payment_methods'] as List? ?? const [])
        .whereType<String>()
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList();
    return OperationsConfig(
      rates: rates.isEmpty ? OperationsConfig.defaults.rates : rates,
      paydays: paydays.isEmpty ? OperationsConfig.defaults.paydays : paydays,
      paymentMethods: methods.isEmpty
          ? OperationsConfig.defaults.paymentMethods
          : methods,
    );
  }
}
