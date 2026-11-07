import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/undo/undo_controller.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/theme_preferences_panel.dart';
import 'operations_config_provider.dart';
import 'business_profile_provider.dart';
import '../sync/offline_sync_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_saver/file_saver.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:typed_data';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text('Settings', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 16),
      Card(
        child: Column(
          children: [
            const ThemePreferencesPanel(),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.backup_outlined),
              title: const Text('Export encrypted-storage backup source'),
              subtitle: const Text(
                'Download organization data as JSON; store it in an encrypted location',
              ),
              trailing: const Icon(Icons.download_outlined),
              onTap: AppConfig.hasSupabase
                  ? () => _exportBackup(context)
                  : null,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.restore_page_outlined),
              title: const Text('Validate backup restore drill'),
              subtitle: const Text(
                'Owner checks an exported backup without changing live data',
              ),
              trailing: const Icon(Icons.fact_check_outlined),
              onTap: AppConfig.hasSupabase
                  ? () => _validateBackup(context)
                  : null,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Operational presets'),
              subtitle: const Text(
                'Interest rates, payday patterns, and payment methods',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: AppConfig.hasSupabase
                  ? () => showDialog<void>(
                      context: context,
                      builder: (_) => _OperationsDialog(
                        initial:
                            ref.read(operationsConfigProvider).value ??
                            OperationsConfig.defaults,
                        controller: ref.read(operationsConfigProvider.notifier),
                      ),
                    )
                  : null,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Audit history'),
              subtitle: const Text('Review important financial record events'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/settings/audit'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.business_outlined),
              title: const Text('Business profile'),
              subtitle: const Text('Name and contact details'),
              trailing: const Icon(Icons.chevron_right),
              onTap: AppConfig.hasSupabase
                  ? () => showDialog<void>(
                      context: context,
                      builder: (_) => const _BusinessProfileDialog(),
                    )
                  : null,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.manage_accounts_outlined),
              title: const Text('Staff roles'),
              subtitle: const Text(
                'Review members and assign operational access',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: AppConfig.hasSupabase
                  ? () => showDialog<void>(
                      context: context,
                      builder: (_) => const _StaffRolesDialog(),
                    )
                  : null,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.sync_outlined),
              title: const Text('Android offline sync'),
              subtitle: Text(
                ref
                    .watch(offlineSyncControllerProvider)
                    .when(
                      loading: () => 'Checking encrypted outbox…',
                      error: (_, _) => 'Sync status unavailable',
                      data: (status) => !status.available
                          ? 'Web is online-only; Android uses an encrypted outbox'
                          : status.syncing
                          ? 'Synchronizing ${status.pending} queued operation(s)…'
                          : status.pending == 0
                          ? 'Synced · no pending operations'
                          : '${status.pending} operation(s) pending or needing attention',
                    ),
              ),
              trailing:
                  ref.watch(offlineSyncControllerProvider).value?.available ==
                      true
                  ? IconButton(
                      tooltip: 'Retry sync',
                      onPressed: () => ref
                          .read(offlineSyncControllerProvider.notifier)
                          .retry(),
                      icon: const Icon(Icons.sync),
                    )
                  : null,
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                AppConfig.hasSupabase
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_off_outlined,
              ),
              title: const Text('Backend configuration'),
              subtitle: Text(
                AppConfig.hasSupabase
                    ? 'Supabase configured'
                    : 'Supabase not configured · local demo only',
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.security_outlined),
              title: const Text('Security'),
              subtitle: Text(
                AppConfig.hasSupabase
                    ? 'Supabase Auth enabled'
                    : 'Authentication unavailable until Supabase is configured',
              ),
              trailing:
                  AppConfig.hasSupabase &&
                      Supabase.instance.client.auth.currentUser != null
                  ? TextButton(
                      onPressed: () async {
                        await Supabase.instance.client.auth.signOut();
                        if (context.mounted) context.go('/login');
                      },
                      child: const Text('Sign out'),
                    )
                  : null,
            ),
            const Divider(height: 1),
            const ListTile(
              leading: Icon(Icons.gavel_outlined),
              title: Text('Default penalties'),
              subtitle: Text('None'),
            ),
          ],
        ),
      ),
    ],
  );

  Future<void> _exportBackup(BuildContext context) async {
    final client = Supabase.instance.client;
    final membership = await client
        .from('organization_members')
        .select('organization_id')
        .eq('user_id', client.auth.currentUser!.id)
        .eq('status', 'active')
        .limit(1)
        .single();
    final organizationId = membership['organization_id'] as String;
    final tables = [
      'organizations',
      'organization_members',
      'borrowers',
      'loans',
      'installments',
      'payments',
      'payment_allocations',
      'audit_events',
      'loan_share_links',
      'collection_activities',
      'loan_disbursements',
      'loan_documents',
      'staff_invitations',
    ];
    final data = <String, dynamic>{
      'format': 'lending-manager-backup-v1',
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'organization_id': organizationId,
    };
    for (final table in tables) {
      data[table] = await client
          .from(table)
          .select()
          .eq(
            table == 'organizations' ? 'id' : 'organization_id',
            organizationId,
          );
    }
    final bytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(data)),
    );
    await FileSaver.instance.saveFile(
      name:
          'lending-manager-backup-${DateTime.now().toIso8601String().substring(0, 10)}',
      bytes: bytes,
      fileExtension: 'json',
      mimeType: MimeType.json,
    );
    if (context.mounted) {
      undoOf(
        context,
      ).notify('Backup source exported. Keep it in encrypted storage.');
    }
  }

  Future<void> _validateBackup(BuildContext context) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (file == null) return;
    try {
      final decoded = jsonDecode(utf8.decode(await file.readAsBytes()));
      if (decoded is! Map<String, dynamic> ||
          decoded['format'] != 'lending-manager-backup-v1') {
        throw const FormatException('Unsupported backup format');
      }
      const required = [
        'organizations',
        'organization_members',
        'borrowers',
        'loans',
        'installments',
        'payments',
        'payment_allocations',
        'audit_events',
      ];
      var count = 0;
      for (final table in required) {
        final rows = decoded[table];
        if (rows is! List) throw FormatException('Missing $table records');
        count += rows.length;
      }
      await Supabase.instance.client.rpc(
        'record_backup_verification',
        params: {
          'p_exported_at': decoded['exported_at'],
          'p_record_count': count,
        },
      );
      if (context.mounted) {
        undoOf(context).notify(
          'Backup validated: $count records readable. Restore owner: organization owner.',
        );
      }
    } catch (_) {
      if (context.mounted) {
        undoOf(
          context,
        ).notify('Backup validation failed. No live data was changed.');
      }
    }
  }
}

class _StaffRolesDialog extends StatefulWidget {
  const _StaffRolesDialog();
  @override
  State<_StaffRolesDialog> createState() => _StaffRolesDialogState();
}

class _StaffRolesDialogState extends State<_StaffRolesDialog> {
  List<Map<String, dynamic>> members = const [];
  String? organizationId;
  bool loading = true;
  String get currentRole =>
      members.cast<Map<String, dynamic>>().firstWhere(
            (m) =>
                m['user_id'] == Supabase.instance.client.auth.currentUser!.id,
            orElse: () => const {'role': 'viewer'},
          )['role']
          as String;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = Supabase.instance.client;
    final row = await client
        .from('organization_members')
        .select('organization_id')
        .eq('user_id', client.auth.currentUser!.id)
        .eq('status', 'active')
        .limit(1)
        .single();
    organizationId = row['organization_id'] as String;
    final result = await client
        .from('organization_members')
        .select('user_id, role, status')
        .eq('organization_id', organizationId!)
        .order('role');
    if (mounted) {
      setState(() {
        members = List<Map<String, dynamic>>.from(result);
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Staff roles'),
    content: SizedBox(
      width: 620,
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              shrinkWrap: true,
              itemCount: members.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (_, index) {
                final member = members[index];
                final userId = member['user_id'] as String;
                final isCurrent =
                    userId == Supabase.instance.client.auth.currentUser!.id;
                return ListTile(
                  leading: const Icon(Icons.account_circle_outlined),
                  title: Text(
                    isCurrent ? 'Current user (you)' : 'Staff member',
                  ),
                  subtitle: Text(
                    '${userId.substring(0, 8)}… · ${member['status']}',
                  ),
                  trailing: DropdownButton<String>(
                    value: member['role'] as String,
                    items: const [
                      DropdownMenuItem(value: 'owner', child: Text('Owner')),
                      DropdownMenuItem(
                        value: 'manager',
                        child: Text('Manager'),
                      ),
                      DropdownMenuItem(
                        value: 'collector',
                        child: Text('Collector'),
                      ),
                      DropdownMenuItem(
                        value: 'auditor',
                        child: Text('Auditor'),
                      ),
                      DropdownMenuItem(value: 'viewer', child: Text('Viewer')),
                    ],
                    onChanged: (value) async {
                      if (value == null) return;
                      try {
                        await Supabase.instance.client.rpc(
                          'set_organization_member_role',
                          params: {
                            'p_organization_id': organizationId,
                            'p_user_id': userId,
                            'p_role': value,
                          },
                        );
                        await _load();
                      } catch (_) {
                        if (context.mounted) {
                          undoOf(context).record(
                            'Role could not be changed. The organization must retain an owner.',
                          );
                        }
                      }
                    },
                  ),
                );
              },
            ),
    ),
    actions: [
      if (!loading && (currentRole == 'owner' || currentRole == 'manager'))
        FilledButton.icon(
          onPressed: _invite,
          icon: const Icon(Icons.person_add_alt_1_outlined),
          label: const Text('Invite Staff'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );

  Future<void> _invite() async {
    final values = await showDialog<({String email, String role})>(
      context: context,
      builder: (_) => _InviteStaffDialog(isOwner: currentRole == 'owner'),
    );
    if (values == null) return;
    try {
      await Supabase.instance.client.functions.invoke(
        'invite-staff',
        body: {
          'organization_id': organizationId,
          'email': values.email,
          'role': values.role,
        },
      );
      await _load();
      if (mounted) {
        undoOf(
          context,
        ).record('Invitation email sent and staff access set up.');
      }
    } catch (_) {
      if (mounted) {
        undoOf(context).record(
          'Invitation could not be sent. Check the email and permissions.',
        );
      }
    }
  }
}

class _InviteStaffDialog extends StatefulWidget {
  const _InviteStaffDialog({required this.isOwner});
  final bool isOwner;
  @override
  State<_InviteStaffDialog> createState() => _InviteStaffDialogState();
}

class _InviteStaffDialogState extends State<_InviteStaffDialog> {
  final key = GlobalKey<FormState>();
  final email = TextEditingController();
  late String role = widget.isOwner ? 'collector' : 'collector';
  @override
  void dispose() {
    email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Invite staff member'),
    content: SizedBox(
      width: 460,
      child: Form(
        key: key,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: email,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email address'),
              validator: (value) => (value?.contains('@') ?? false)
                  ? null
                  : 'Enter a valid email',
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: role,
              decoration: const InputDecoration(labelText: 'Role'),
              items: [
                if (widget.isOwner) ...const [
                  DropdownMenuItem(value: 'owner', child: Text('Owner')),
                  DropdownMenuItem(value: 'manager', child: Text('Manager')),
                ],
                const DropdownMenuItem(
                  value: 'collector',
                  child: Text('Collector'),
                ),
                const DropdownMenuItem(
                  value: 'auditor',
                  child: Text('Auditor'),
                ),
              ],
              onChanged: (value) => setState(() => role = value!),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (key.currentState!.validate()) {
            Navigator.pop(context, (email: email.text.trim(), role: role));
          }
        },
        child: const Text('Send Invitation'),
      ),
    ],
  );
}

class _OperationsDialog extends StatefulWidget {
  const _OperationsDialog({required this.initial, required this.controller});
  final OperationsConfig initial;
  final OperationsConfigController controller;
  @override
  State<_OperationsDialog> createState() => _OperationsDialogState();
}

class _OperationsDialogState extends State<_OperationsDialog> {
  late final rates = TextEditingController(
    text: widget.initial.rates.join(', '),
  );
  late final paydays = TextEditingController(
    text: widget.initial.paydays.map((v) => v.join('/')).join(', '),
  );
  late final methods = TextEditingController(
    text: widget.initial.paymentMethods.join(', '),
  );
  bool saving = false;
  @override
  void dispose() {
    rates.dispose();
    paydays.dispose();
    methods.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Operational presets'),
    content: SizedBox(
      width: 560,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: rates,
            decoration: const InputDecoration(
              labelText: 'Monthly rate presets (%)',
              helperText: 'Comma-separated, for example 3, 6, 10',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: paydays,
            decoration: const InputDecoration(
              labelText: 'Payday patterns',
              helperText: 'Comma-separated patterns, for example 15/30, 5/20',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: methods,
            decoration: const InputDecoration(
              labelText: 'Payment methods',
              helperText: 'Comma-separated',
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: saving ? null : _save,
        child: const Text('Save Presets'),
      ),
    ],
  );
  Future<void> _save() async {
    final parsedRates = rates.text
        .split(',')
        .map((v) => num.tryParse(v.trim()))
        .whereType<num>()
        .where((v) => v >= 0)
        .toSet()
        .toList();
    final parsedPaydays = <List<int>>[];
    for (final group in paydays.text.split(',')) {
      final days =
          group
              .split('/')
              .map((v) => int.tryParse(v.trim()))
              .whereType<int>()
              .where((v) => v >= 1 && v <= 31)
              .toSet()
              .toList()
            ..sort();
      if (days.isNotEmpty) parsedPaydays.add(days);
    }
    final parsedMethods = methods.text
        .split(',')
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList();
    if (parsedRates.isEmpty || parsedPaydays.isEmpty || parsedMethods.isEmpty) {
      return;
    }
    setState(() => saving = true);
    final saved = await widget.controller.save(
      OperationsConfig(
        rates: parsedRates,
        paydays: parsedPaydays,
        paymentMethods: parsedMethods,
      ),
    );
    if (mounted && saved) Navigator.pop(context);
    if (mounted && !saved) setState(() => saving = false);
  }
}

class _BusinessProfileDialog extends ConsumerStatefulWidget {
  const _BusinessProfileDialog();
  @override
  ConsumerState<_BusinessProfileDialog> createState() =>
      _BusinessProfileDialogState();
}

class _BusinessProfileDialogState
    extends ConsumerState<_BusinessProfileDialog> {
  final key = GlobalKey<FormState>();
  final name = TextEditingController();
  final phone = TextEditingController();
  final email = TextEditingController();
  final address = TextEditingController();
  String? organizationId;
  bool loading = true, saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
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
        .select('name, phone, email, address')
        .eq('id', organizationId!)
        .single();
    name.text = row['name'] as String;
    phone.text = row['phone'] as String? ?? '';
    email.text = row['email'] as String? ?? '';
    address.text = row['address'] as String? ?? '';
    if (mounted) setState(() => loading = false);
  }

  Future<void> _save() async {
    if (!key.currentState!.validate()) return;
    setState(() => saving = true);
    await Supabase.instance.client
        .from('organizations')
        .update({
          'name': name.text.trim(),
          'phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
          'email': email.text.trim().isEmpty ? null : email.text.trim(),
          'address': address.text.trim().isEmpty ? null : address.text.trim(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', organizationId!);
    ref.invalidate(businessProfileProvider);
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    email.dispose();
    address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Business profile'),
    content: SizedBox(
      width: 520,
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: key,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Business name',
                    ),
                    validator: (v) => (v?.trim().isEmpty ?? true)
                        ? 'Business name is required'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: phone,
                    decoration: const InputDecoration(labelText: 'Phone'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: email,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: address,
                    decoration: const InputDecoration(labelText: 'Address'),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: loading || saving ? null : _save,
        child: const Text('Save Changes'),
      ),
    ],
  );
}
