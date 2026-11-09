import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/app_config.dart';

const paymentQrBucket = 'payment-qrs';

class PaymentQrCode {
  const PaymentQrCode({
    required this.id,
    required this.organizationId,
    required this.label,
    required this.storagePath,
    required this.mimeType,
    required this.enabled,
    required this.sortOrder,
  });
  final String id, organizationId, label, storagePath, mimeType;
  final bool enabled;
  final int sortOrder;
}

final paymentQrProvider =
    AsyncNotifierProvider<PaymentQrController, List<PaymentQrCode>>(
      PaymentQrController.new,
    );

class PaymentQrController extends AsyncNotifier<List<PaymentQrCode>> {
  SupabaseClient get _client => Supabase.instance.client;
  String? organizationId;
  String role = 'viewer';
  bool get canManage => role == 'owner' || role == 'manager';

  @override
  Future<List<PaymentQrCode>> build() async {
    if (!AppConfig.hasSupabase || _client.auth.currentUser == null) {
      return const [];
    }
    final member = await _client
        .from('organization_members')
        .select('organization_id,role')
        .eq('user_id', _client.auth.currentUser!.id)
        .eq('status', 'active')
        .limit(1)
        .single();
    organizationId = '${member['organization_id']}';
    role = '${member['role']}';
    return _fetch();
  }

  Future<List<PaymentQrCode>> _fetch() async {
    final rows = await _client
        .from('payment_qr_codes')
        .select()
        .eq('organization_id', organizationId!)
        .order('sort_order')
        .order('created_at');
    return [
      for (final r in rows)
        PaymentQrCode(
          id: '${r['id']}',
          organizationId: '${r['organization_id']}',
          label: '${r['label']}',
          storagePath: '${r['storage_path']}',
          mimeType: '${r['mime_type']}',
          enabled: r['enabled'] as bool,
          sortOrder: r['sort_order'] as int,
        ),
    ];
  }

  Future<Uint8List> download(PaymentQrCode qr) =>
      _client.storage.from(paymentQrBucket).download(qr.storagePath);
  Future<void> seedBundledDefaults() async {
    if (!canManage || (state.value?.isNotEmpty ?? true)) return;
    for (final item in _bundledQrs) {
      final data = await rootBundle.load(item.$2);
      await add(
        label: item.$1,
        name: item.$2,
        mimeType: 'image/png',
        bytes: data.buffer.asUint8List(),
      );
    }
  }

  Future<bool> add({
    required String label,
    required String name,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    if (!canManage ||
        bytes.isEmpty ||
        bytes.length > 5242880 ||
        !const {'image/png', 'image/jpeg'}.contains(mimeType)) {
      return false;
    }
    final ext = mimeType == 'image/png' ? 'png' : 'jpg';
    final path = '$organizationId/${const Uuid().v4()}.$ext';
    try {
      await _client.storage
          .from(paymentQrBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mimeType, upsert: false),
          );
      final current = state.value ?? const <PaymentQrCode>[];
      await _client.from('payment_qr_codes').insert({
        'organization_id': organizationId,
        'label': label.trim(),
        'storage_path': path,
        'mime_type': mimeType,
        'enabled': true,
        'sort_order': current.length,
        'created_by': _client.auth.currentUser!.id,
      });
      state = AsyncData(await _fetch());
      return true;
    } catch (_) {
      try {
        await _client.storage.from(paymentQrBucket).remove([path]);
      } catch (_) {}
      return false;
    }
  }

  Future<bool> rename(PaymentQrCode qr, String label) =>
      _update(qr, {'label': label.trim()});
  Future<bool> setEnabled(PaymentQrCode qr, bool enabled) =>
      _update(qr, {'enabled': enabled});
  Future<bool> _update(PaymentQrCode qr, Map<String, Object> values) async {
    try {
      await _client.from('payment_qr_codes').update(values).eq('id', qr.id);
      state = AsyncData(await _fetch());
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> replace(
    PaymentQrCode qr, {
    required String mimeType,
    required Uint8List bytes,
  }) async {
    if (!canManage || bytes.isEmpty || bytes.length > 5242880) return false;
    final ext = mimeType == 'image/png' ? 'png' : 'jpg';
    final path = '$organizationId/${const Uuid().v4()}.$ext';
    try {
      await _client.storage
          .from(paymentQrBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mimeType),
          );
      await _client
          .from('payment_qr_codes')
          .update({'storage_path': path, 'mime_type': mimeType})
          .eq('id', qr.id);
      await _client.storage.from(paymentQrBucket).remove([qr.storagePath]);
      state = AsyncData(await _fetch());
      return true;
    } catch (_) {
      try {
        await _client.storage.from(paymentQrBucket).remove([path]);
      } catch (_) {}
      return false;
    }
  }

  Future<bool> delete(PaymentQrCode qr) async {
    try {
      await _client.from('payment_qr_codes').delete().eq('id', qr.id);
      await _client.storage.from(paymentQrBucket).remove([qr.storagePath]);
      state = AsyncData(await _fetch());
      return true;
    } catch (_) {
      return false;
    }
  }
}

const _bundledQrs = [
  ('GCash', 'assets/payment_qr/gcash.png'),
  ('AUB HelloMoney', 'assets/payment_qr/aub.png'),
  ('MariBank', 'assets/payment_qr/maribank.png'),
];

Future<List<(String, Uint8List)>> loadEnabledPaymentQrs() async {
  if (AppConfig.hasSupabase &&
      Supabase.instance.client.auth.currentUser != null) {
    try {
      final rows = await Supabase.instance.client
          .from('payment_qr_codes')
          .select('label,storage_path')
          .eq('enabled', true)
          .order('sort_order')
          .order('created_at');
      if (rows.isNotEmpty) {
        final out = <(String, Uint8List)>[];
        for (final row in rows) {
          try {
            out.add((
              '${row['label']}',
              await Supabase.instance.client.storage
                  .from(paymentQrBucket)
                  .download('${row['storage_path']}'),
            ));
          } catch (_) {}
        }
        if (out.isNotEmpty) return out;
      }
    } catch (_) {}
  }
  final out = <(String, Uint8List)>[];
  for (final item in _bundledQrs) {
    final data = await rootBundle.load(item.$2);
    out.add((item.$1, data.buffer.asUint8List()));
  }
  return out;
}
