import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/widgets/window_title.dart';
import '../../app/data_refresh.dart';
import '../../core/formatting.dart';
import '../../core/undo/undo_controller.dart';
import '../documents/evidence_counts.dart';
import 'backup_archive.dart';

String _ref(String id) => 'LN-${id.substring(0, 8).toUpperCase()}';

/// Settings → Restore a loan from a backup (owner).
///
/// Pick a backup file, choose a loan that differs from the backup, review
/// exactly what will change (a dry run on the server), give a reason, and
/// restore. Only that loan's records change; it can be undone right after.
Future<void> restoreLoanFromBackup(BuildContext context) async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['zip'],
  );
  if (file == null || !context.mounted) return;
  final check = readBackup(await file.readAsBytes());
  if (!context.mounted) return;
  if (!check.ok) {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const WindowTitle(Text('This backup cannot be used')),
        content: Text(check.problems.take(10).map((p) => '• $p').join('\n')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    return;
  }
  final entry = await showDialog<_LoanEntry>(
    context: context,
    builder: (_) => _PickLoanDialog(check: check),
  );
  if (entry == null || !context.mounted) return;
  final restoreId = await showDialog<String>(
    context: context,
    builder: (_) => _PreviewDialog(entry: entry, check: check),
  );
  if (restoreId == null || !context.mounted) return;
  final container = ProviderScope.containerOf(context, listen: false);
  void refresh() {
    refreshAllMoneyViews(container);
    container.invalidate(evidenceCountsProvider);
  }

  refresh();
  undoOf(context).offer(
    '${_ref(entry.loanId)} restored from the backup. The restore is in the history.',
    () async {
      try {
        await Supabase.instance.client.rpc(
          'undo_loan_restore',
          params: {'p_restore_id': restoreId},
        );
        refresh();
        return true;
      } catch (_) {
        return false;
      }
    },
  );
}

enum _Kind { changed, addedAfter, missingNow, same }

class _LoanEntry {
  _LoanEntry({
    required this.loanId,
    required this.borrower,
    required this.kind,
    required this.backupStatus,
    required this.liveStatus,
    required this.backupState,
  });
  final String loanId, borrower;
  final _Kind kind;
  final String? backupStatus, liveStatus;
  final Map<String, dynamic>? backupState;
}

/// Compares states without fields that change on their own (a customer
/// opening their link).
String _fingerprint(Map<String, dynamic>? state) {
  if (state == null) return 'null';
  final copy = {...state};
  copy['loan_share_links'] = [
    for (final l in (state['loan_share_links'] as List))
      {...(l as Map)}..remove('last_accessed_at'),
  ];
  return canonicalJson(copy);
}

class _PickLoanDialog extends StatefulWidget {
  const _PickLoanDialog({required this.check});
  final BackupCheck check;
  @override
  State<_PickLoanDialog> createState() => _PickLoanDialogState();
}

class _PickLoanDialogState extends State<_PickLoanDialog> {
  List<_LoanEntry>? entries;
  String? error;
  bool showAll = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final live = await fetchLiveLoanTables(Supabase.instance.client);
      final backup = widget.check.tables;
      final names = <Object?, String>{
        for (final b in [...backup['borrowers']!, ...live['borrowers']!])
          b['id']: '${b['last_name']}, ${b['first_name']}',
      };
      final ids = {
        ...backup['loans']!.map((l) => l['id'] as String),
        ...live['loans']!.map((l) => l['id'] as String),
      };
      final list = <_LoanEntry>[];
      for (final id in ids) {
        final b = loanStateFromBackup(backup, id);
        final l = loanStateFromBackup(live, id);
        final loan = (b ?? l)!['loan'] as Map<String, dynamic>;
        list.add(
          _LoanEntry(
            loanId: id,
            borrower: names[loan['borrower_id']] ?? 'Unknown borrower',
            kind: b == null
                ? _Kind.addedAfter
                : l == null
                ? _Kind.missingNow
                : _fingerprint(b) == _fingerprint(l)
                ? _Kind.same
                : _Kind.changed,
            backupStatus: (b?['loan'] as Map?)?['status'] as String?,
            liveStatus: (l?['loan'] as Map?)?['status'] as String?,
            backupState: b,
          ),
        );
      }
      list.sort((x, y) {
        final k = x.kind.index.compareTo(y.kind.index);
        return k != 0 ? k : x.borrower.compareTo(y.borrower);
      });
      if (mounted) setState(() => entries = list);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = entries;
    final shown = all?.where((e) => showAll || e.kind != _Kind.same).toList();
    return AlertDialog(
      title: const WindowTitle(Text('Restore a loan')),
      content: SizedBox(
        width: 620,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Backup of ${widget.check.organizationName}, made '
              '${_when(widget.check.exportedAt)}. Choose the loan to put back '
              'as it was in the backup.',
            ),
            if (all != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: showAll,
                onChanged: (v) => setState(() => showAll = v),
                title: Text(
                  'Show unchanged loans '
                  '(${all.where((e) => e.kind == _Kind.same).length})',
                ),
              ),
            const SizedBox(height: 4),
            Expanded(
              child: error != null
                  ? Text(
                      'Live data could not be loaded: $error',
                      style: TextStyle(color: theme.colorScheme.error),
                    )
                  : shown == null
                  ? const Center(child: CircularProgressIndicator())
                  : shown.isEmpty
                  ? const Center(
                      child: Text('Every loan is the same as in this backup.'),
                    )
                  : ListView.separated(
                      itemCount: shown.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final e = shown[i];
                        return ListTile(
                          title: Text(e.borrower),
                          subtitle: Text(
                            '${_ref(e.loanId)} · ${switch (e.kind) {
                              _Kind.changed => 'Changed since the backup: ${_status(e.backupStatus)} then, ${_status(e.liveStatus)} now',
                              _Kind.addedAfter => 'Created after the backup (${_status(e.liveStatus)}); restoring removes it',
                              _Kind.missingNow => 'Missing now; restoring brings it back',
                              _Kind.same => 'Same as the backup',
                            }}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          enabled: e.kind != _Kind.same,
                          onTap: () => Navigator.pop(context, e),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _PreviewDialog extends StatefulWidget {
  const _PreviewDialog({required this.entry, required this.check});
  final _LoanEntry entry;
  final BackupCheck check;
  @override
  State<_PreviewDialog> createState() => _PreviewDialogState();
}

class _PreviewDialogState extends State<_PreviewDialog> {
  Map<String, dynamic>? now, after;
  bool loaded = false, saving = false;
  String? error;
  final reason = TextEditingController();
  final operationId = const Uuid().v4();

  @override
  void initState() {
    super.initState();
    _preview();
  }

  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  Future<void> _preview() async {
    try {
      final result =
          await Supabase.instance.client.rpc(
                'loan_restore_preview',
                params: {
                  'p_loan_id': widget.entry.loanId,
                  'p_state': widget.entry.backupState,
                },
              )
              as Map<String, dynamic>;
      setState(() {
        now = (result['now'] as Map?)?.cast<String, dynamic>();
        after = (result['after'] as Map?)?.cast<String, dynamic>();
        loaded = true;
      });
    } catch (e) {
      setState(() {
        loaded = true;
        error = e is PostgrestException ? e.message : '$e';
      });
    }
  }

  Future<void> _restore() async {
    if (reason.text.trim().length < 3) {
      setState(() => error = 'Enter a short reason (kept in the history).');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final id = await Supabase.instance.client.rpc(
        'restore_loan',
        params: {
          'p_loan_id': widget.entry.loanId,
          'p_state': widget.entry.backupState,
          'p_reason': reason.text.trim(),
          'p_backup_exported_at': widget.check.exportedAt,
          'p_client_operation_id': operationId,
        },
      );
      if (mounted) Navigator.pop(context, id as String);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = e is PostgrestException ? e.message : '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = loaded && error == null ? _changes(now, after) : <String>[];
    final owedNow = _owed(now), owedAfter = _owed(after);
    return AlertDialog(
      title: WindowTitle(
        Text('Restore ${_ref(widget.entry.loanId)}?'),
        onBack: saving ? () {} : null,
      ),
      content: SizedBox(
        width: 560,
        child: !loaded
            ? const LinearProgressIndicator()
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.entry.borrower,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (now != null || after != null) ...[
                      _row(
                        'Status',
                        _status((now?['loan'] as Map?)?['status'] as String?),
                        after == null
                            ? 'Removed'
                            : _status(
                                (after!['loan'] as Map)['status'] as String?,
                              ),
                      ),
                      _row(
                        'Still owed',
                        now == null ? '—' : formatPeso(owedNow),
                        after == null ? '—' : formatPeso(owedAfter),
                      ),
                      const Divider(),
                      Text('What changes', style: theme.textTheme.labelLarge),
                      const SizedBox(height: 4),
                      if (lines.isEmpty)
                        const Text(
                          'Nothing; this loan already matches the backup.',
                        )
                      else
                        for (final l in lines) Text('• $l'),
                      const SizedBox(height: 12),
                      TextField(
                        controller: reason,
                        enabled: !saving,
                        decoration: const InputDecoration(
                          labelText: 'Reason',
                          hintText: 'e.g. Undo test changes',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Only this loan changes. Uploaded evidence stays. The '
                        'restore is added to the history and can be undone '
                        'right after.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        error!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
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
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed:
              !loaded ||
                  saving ||
                  lines.isEmpty ||
                  (error != null && now == null && after == null)
              ? null
              : _restore,
          child: Text(saving ? 'Restoring…' : 'Restore'),
        ),
      ],
    );
  }

  Widget _row(String label, String before, String afterText) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        SizedBox(width: 110, child: Text(label)),
        Expanded(child: Text('$before  →  $afterText')),
      ],
    ),
  );
}

int _owed(Map<String, dynamic>? state) {
  if (state == null) return 0;
  final b = computeBalances({
    'loans': [(state['loan'] as Map).cast<String, dynamic>()],
    'installments': (state['installments'] as List)
        .cast<Map<String, dynamic>>(),
    'payments': (state['payments'] as List).cast<Map<String, dynamic>>(),
    'payment_allocations': (state['payment_allocations'] as List)
        .cast<Map<String, dynamic>>(),
  });
  return b.values.firstOrNull?.outstanding ?? 0;
}

const _sectionNames = {
  'installments': 'schedule entries',
  'loan_disbursements': 'money release records',
  'payments': 'payments',
  'payment_allocations': 'payment allocations',
  'payment_corrections': 'payment corrections',
  'loan_amendments': 'loan corrections / refinance records',
  'collection_activities': 'collection notes',
  'loan_share_links': 'customer links',
  'penalty_charges': 'penalties',
};

/// Readable list of differences between the loan now and after the restore.
List<String> _changes(Map<String, dynamic>? now, Map<String, dynamic>? after) {
  if (now == null && after == null) return const [];
  if (now == null) return ['The loan is brought back with all its records.'];
  if (after == null) {
    return ['The loan is removed (it did not exist when the backup was made).'];
  }
  final out = <String>[];
  final loanNow = now['loan'] as Map, loanAfter = after['loan'] as Map;
  final changedFields = [
    for (final k in loanNow.keys)
      if (canonicalJson(loanNow[k]) != canonicalJson(loanAfter[k])) k,
  ];
  if (changedFields.isNotEmpty) {
    out.add(
      'Loan details: ${changedFields.map((f) => '$f'.replaceAll('_', ' ')).join(', ')}',
    );
  }
  for (final section in _sectionNames.keys) {
    final a = {
      for (final r in (now[section] as List))
        (r as Map)['id']: canonicalJson(r),
    };
    final b = {
      for (final r in (after[section] as List))
        (r as Map)['id']: canonicalJson(r),
    };
    final removed = a.keys.where((k) => !b.containsKey(k)).length;
    final added = b.keys.where((k) => !a.containsKey(k)).length;
    final changed = a.keys
        .where((k) => b.containsKey(k) && a[k] != b[k])
        .length;
    if (removed + added + changed == 0) continue;
    out.add(
      '${_sectionNames[section]}: ${[if (added > 0) '$added put back', if (removed > 0) '$removed removed', if (changed > 0) '$changed changed back'].join(', ')}',
    );
  }
  // Payment details, since those matter most.
  final paymentsNow = <Object?, Map>{
    for (final p in (now['payments'] as List).cast<Map>()) p['id']: p,
  };
  for (final p in (after['payments'] as List).cast<Map>()) {
    final before = paymentsNow[p['id']];
    if (before == null) {
      out.add(
        'Payment ${formatPeso((p['amount_centavos'] as num).toInt())} (${_day(p['received_at'])}) put back as ${p['status']}',
      );
    } else if (canonicalJson(before) != canonicalJson(p)) {
      out.add(
        'Payment ${formatPeso((p['amount_centavos'] as num).toInt())}: ${before['status']}, ${_day(before['received_at'])} → ${p['status']}, ${_day(p['received_at'])}',
      );
    }
  }
  final paymentsAfter = {
    for (final p in (after['payments'] as List)) (p as Map)['id'],
  };
  for (final p in (now['payments'] as List).cast<Map>()) {
    if (!paymentsAfter.contains(p['id'])) {
      out.add(
        'Payment ${formatPeso((p['amount_centavos'] as num).toInt())} (${_day(p['received_at'])}, ${p['status']}) removed',
      );
    }
  }
  return out;
}

String _day(Object? iso) =>
    '$iso'.length >= 10 ? '$iso'.substring(0, 10) : '$iso';

String _status(String? s) => switch (s) {
  null => 'none',
  'fully_paid' => 'Paid',
  'draft' => 'Draft',
  'active' => 'Active',
  'refinanced' => 'Refinanced',
  'cancelled' => 'Cancelled',
  _ => s,
};

String _when(String iso) {
  final t = DateTime.tryParse(iso)?.toLocal();
  if (t == null) return iso;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}
