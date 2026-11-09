import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_config.dart';
import '../core/preferences/filter_defaults.dart';
import '../core/update/page_reload.dart';
import 'theme/theme_mode_provider.dart';

class AppNotice {
  const AppNotice(this.id, this.title, this.detail, this.loanId, this.icon);
  final String id, title, detail, loanId;
  final IconData icon;
}

final appNoticesProvider = FutureProvider<List<AppNotice>>((ref) async {
  if (!AppConfig.hasSupabase ||
      Supabase.instance.client.auth.currentUser == null) {
    return const [];
  }
  final client = Supabase.instance.client;
  final today = DateTime.now();
  final date =
      '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
  final results = await Future.wait<dynamic>([
    client
        .from('payments')
        .select(
          'id,loan_id,amount_centavos,loan:loans!inner(is_personal,borrower:borrowers(first_name,last_name))',
        )
        .eq('status', 'pending')
        .eq('loan.is_personal', false)
        .order('received_at', ascending: false)
        .limit(20),
    client
        .from('installments')
        .select(
          'id,loan_id,due_date,scheduled_centavos,penalty_centavos,loan:loans!inner(status,is_personal,borrower:borrowers(first_name,last_name))',
        )
        .eq('loan.status', 'active')
        .eq('loan.is_personal', false)
        .lte('due_date', date)
        .order('due_date')
        .limit(100),
    client
        .from('payment_allocations')
        .select(
          'installment_id,principal_centavos,interest_centavos,penalty_centavos,payment:payments!inner(status)',
        )
        .eq('payment.status', 'verified'),
    client
        .from('collection_activities')
        .select(
          'id,loan_id,promised_on,loan:loans!inner(is_personal,borrower:borrowers(first_name,last_name))',
        )
        .isFilter('undone_at', null)
        .eq('activity_type', 'promise')
        .eq('promised_on', date)
        .eq('loan.is_personal', false)
        .limit(20),
  ]);
  String name(Map row) {
    final loan = Map<String, dynamic>.from(row['loan'] as Map);
    final b = Map<String, dynamic>.from(loan['borrower'] as Map);
    return '${b['last_name']}, ${b['first_name']}';
  }

  final notices = <AppNotice>[];
  for (final row in List<Map<String, dynamic>>.from(results[0])) {
    notices.add(
      AppNotice(
        'payment:${row['id']}',
        'Payment waiting for verification',
        name(row),
        '${row['loan_id']}',
        Icons.payments_outlined,
      ),
    );
  }
  final paid = <String, int>{};
  for (final row in List<Map<String, dynamic>>.from(results[2])) {
    paid['${row['installment_id']}'] =
        (paid['${row['installment_id']}'] ?? 0) +
        (row['principal_centavos'] as int) +
        (row['interest_centavos'] as int) +
        (row['penalty_centavos'] as int);
  }
  for (final row in List<Map<String, dynamic>>.from(results[1])) {
    final balance =
        (row['scheduled_centavos'] as int) +
        (row['penalty_centavos'] as int? ?? 0) -
        (paid['${row['id']}'] ?? 0);
    if (balance <= 0) continue;
    final due = '${row['due_date']}';
    notices.add(
      AppNotice(
        'due:${row['id']}',
        due == date ? 'Installment due today' : 'Overdue installment',
        name(row),
        '${row['loan_id']}',
        Icons.warning_amber_rounded,
      ),
    );
    if ((row['penalty_centavos'] as int? ?? 0) > 0) {
      notices.add(
        AppNotice(
          'penalty:${row['id']}',
          'Penalty charged',
          name(row),
          '${row['loan_id']}',
          Icons.gavel_outlined,
        ),
      );
    }
  }
  for (final row in List<Map<String, dynamic>>.from(results[3])) {
    notices.add(
      AppNotice(
        'promise:${row['id']}',
        'Promise due today',
        name(row),
        '${row['loan_id']}',
        Icons.event_available_outlined,
      ),
    );
  }
  return notices;
});

class NotificationButton extends ConsumerWidget {
  const NotificationButton({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notices = ref.watch(appNoticesProvider);
    final prefs = ref.watch(sharedPreferencesProvider);
    final items = notices.value ?? const <AppNotice>[];
    final seen =
        prefs?.getStringList('notifications.seen')?.toSet() ?? <String>{};
    final unread = items.where((n) => !seen.contains(n.id)).length;
    return Badge(
      isLabelVisible: unread > 0,
      label: Text(unread > 99 ? '99+' : '$unread'),
      child: IconButton(
        tooltip: 'Notifications',
        onPressed: () => _show(context, ref, items),
        icon: const Icon(Icons.notifications_none),
      ),
    );
  }

  Future<void> _show(
    BuildContext context,
    WidgetRef ref,
    List<AppNotice> items,
  ) async {
    await ref
        .read(sharedPreferencesProvider)
        ?.setStringList('notifications.seen', items.map((n) => n.id).toList());
    if (context.mounted) {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheet) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .65,
            child: Column(
              children: [
                ListTile(
                  title: const Text(
                    'Notifications',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  trailing: IconButton(
                    tooltip: 'Refresh',
                    onPressed: () {
                      ref.invalidate(appNoticesProvider);
                      Navigator.pop(sheet);
                    },
                    icon: const Icon(Icons.refresh),
                  ),
                ),
                Expanded(
                  child: items.isEmpty
                      ? const Center(child: Text('You are all caught up.'))
                      : ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final n = items[i];
                            return ListTile(
                              leading: Icon(n.icon),
                              title: Text(n.title),
                              subtitle: Text(n.detail),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                Navigator.pop(sheet);
                                context.go('/loans/${n.loanId}');
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    ref.invalidate(appNoticesProvider);
  }
}

class AccountButton extends ConsumerWidget {
  const AccountButton({
    super.key,
    required this.initials,
    required this.label,
    required this.role,
    this.compact = false,
  });
  final String initials, label, role;
  final bool compact;
  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<String>(
    tooltip: 'Account menu',
    onSelected: (v) => _select(context, ref, v),
    itemBuilder: (_) => [
      PopupMenuItem(
        enabled: false,
        child: SizedBox(
          width: 260,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(child: Text(initials)),
            title: Text(label, overflow: TextOverflow.ellipsis),
            subtitle: Text(role),
          ),
        ),
      ),
      const PopupMenuDivider(),
      const PopupMenuItem(
        value: 'appearance',
        child: ListTile(
          leading: Icon(Icons.palette_outlined),
          title: Text('Appearance'),
        ),
      ),
      const PopupMenuItem(
        value: 'whats_new',
        child: ListTile(
          leading: Icon(Icons.new_releases_outlined),
          title: Text("What's new"),
        ),
      ),
      const PopupMenuItem(
        value: 'updates',
        child: ListTile(
          leading: Icon(Icons.system_update_alt),
          title: Text('Check for updates'),
        ),
      ),
      const PopupMenuItem(
        value: 'account',
        child: ListTile(
          leading: Icon(Icons.password_outlined),
          title: Text('My account…'),
        ),
      ),
      const PopupMenuItem(
        value: 'settings',
        child: ListTile(
          leading: Icon(Icons.settings_outlined),
          title: Text('Settings'),
        ),
      ),
      const PopupMenuDivider(),
      const PopupMenuItem(
        value: 'signout',
        child: ListTile(leading: Icon(Icons.logout), title: Text('Sign out')),
      ),
    ],
    child: compact
        ? SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: CircleAvatar(
                radius: 16,
                child: Text(initials, style: const TextStyle(fontSize: 10)),
              ),
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 18,
                child: Text(initials, style: const TextStyle(fontSize: 11)),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(role, style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
            ],
          ),
  );
  Future<void> _select(
    BuildContext context,
    WidgetRef ref,
    String value,
  ) async {
    switch (value) {
      case 'appearance':
        await showDialog<void>(
          context: context,
          builder: (d) => SimpleDialog(
            title: const Text('Appearance'),
            children: [
              for (final m in ThemeMode.values)
                ListTile(
                  title: Text(m.name[0].toUpperCase() + m.name.substring(1)),
                  trailing: ref.read(themeModeProvider) == m
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () {
                    ref.read(themeModeProvider.notifier).select(m);
                    Navigator.pop(d);
                  },
                ),
            ],
          ),
        );
      case 'whats_new':
        if (context.mounted) {
          await showDialog<void>(
            context: context,
            builder: (d) => AlertDialog(
              title: const Text("What's new"),
              content: const Text(
                '• Loan and payment corrections with audit history\n• Early-payoff and penalty policies\n• Receipts, statements, agreements and acknowledgments\n• Backups, restore tools and safer updates\n• Personal loans and richer customer status',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(d),
                  child: const Text('Close'),
                ),
              ],
            ),
          );
        }
      case 'updates':
        await _checkUpdates(context);
      case 'account':
        await _changePassword(context);
      case 'settings':
        if (context.mounted) context.go('/settings');
      case 'signout':
        if (AppConfig.hasSupabase) {
          await Supabase.instance.client.auth.signOut();
        }
        if (context.mounted) context.go('/login');
    }
  }

  Future<void> _checkUpdates(BuildContext context) async {
    String message = 'This app is up to date (build ${AppConfig.buildId}).';
    bool newer = false;
    if (kIsWeb) {
      try {
        final r = await http.get(
          Uri.base.resolve(
            '/app_build.json?t=${DateTime.now().millisecondsSinceEpoch}',
          ),
        );
        if (r.statusCode == 200) {
          final latest = (jsonDecode(r.body) as Map)['build_id'];
          newer =
              latest is String &&
              latest.isNotEmpty &&
              latest != AppConfig.buildId;
          if (newer) message = 'Build $latest is available.';
        }
      } catch (_) {
        message =
            'Updates could not be checked. Try again when you are online.';
      }
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('App update'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('Close'),
          ),
          if (newer)
            FilledButton(onPressed: reloadPage, child: const Text('Update')),
        ],
      ),
    );
  }

  Future<void> _changePassword(BuildContext context) async {
    final c = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Change password'),
        content: TextField(
          controller: c,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'New password',
            helperText: 'Use at least 8 characters.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, c.text),
            child: const Text('Change Password'),
          ),
        ],
      ),
    );
    c.dispose();
    if (password == null || password.length < 8 || !AppConfig.hasSupabase) {
      return;
    }
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: password),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Password changed.')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password could not be changed.')),
        );
      }
    }
  }
}
