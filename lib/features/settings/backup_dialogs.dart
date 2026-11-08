import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/export_file.dart';
import '../../core/formatting.dart';
import '../../core/undo/undo_controller.dart';
import 'backup_archive.dart';

/// Settings → Back up: every record (all rows, page by page) and, by
/// default, every uploaded file, in one checked zip.
Future<void> exportBackup(BuildContext context) async {
  final bytes = await showDialog<Uint8List>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _ExportDialog(),
  );
  if (bytes == null || !context.mounted) return;
  final now = DateTime.now();
  final where = await saveExport(
    name:
        'lending-manager-backup-${now.toIso8601String().substring(0, 16).replaceAll(':', '').replaceAll('T', '_')}',
    bytes: bytes,
    extension: 'zip',
    mimeType: MimeType.zip,
  );
  if (context.mounted && where != null) {
    undoOf(context).notify(
      'Backup saved to $where. Keep a copy somewhere other than this device.',
    );
  }
}

class _ExportDialog extends StatefulWidget {
  const _ExportDialog();
  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  bool includeFiles = true;
  bool running = false;
  String step = '';
  String? error;

  Future<void> _run() async {
    setState(() {
      running = true;
      error = null;
    });
    try {
      final data = await fetchBackupData(
        Supabase.instance.client,
        includeFiles: includeFiles,
        onProgress: (s) {
          if (mounted) setState(() => step = s);
        },
      );
      setState(() => step = 'Checking the backup…');
      final bytes = encodeBackup(data);
      // Never hand over a file that does not pass its own check.
      final check = readBackup(bytes);
      if (!check.ok) throw StateError(check.problems.take(3).join('; '));
      if (mounted) Navigator.pop(context, bytes);
    } catch (e) {
      if (mounted) {
        setState(() {
          running = false;
          error = e is StateError ? e.message : '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Back up everything'),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Saves borrowers, loans, schedules, payments, releases, '
            'corrections, collection notes, staff and the full history in '
            'one file, with checksums so damage can be detected.',
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: includeFiles,
            onChanged: running ? null : (v) => setState(() => includeFiles = v),
            title: const Text('Include uploaded files'),
            subtitle: const Text('Receipts, agreements and other evidence'),
          ),
          if (running) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(step),
          ],
          if (error != null)
            Text(
              'Backup failed: $error',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: running ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: running ? null : _run,
        child: const Text('Back Up'),
      ),
    ],
  );
}

/// Settings → Check a backup: opens a backup file, verifies every checksum,
/// reference and balance, compares it with the live data, and records the
/// check in the history. Never changes live data.
Future<void> checkBackup(BuildContext context) async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['zip'],
  );
  if (file == null || !context.mounted) return;
  final bytes = await file.readAsBytes();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _CheckDialog(bytes: bytes),
  );
}

class _CheckDialog extends StatefulWidget {
  const _CheckDialog({required this.bytes});
  final Uint8List bytes;
  @override
  State<_CheckDialog> createState() => _CheckDialogState();
}

class _CheckDialogState extends State<_CheckDialog> {
  BackupCheck? check;
  int? changedSince;
  String? liveError;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    await Future<void>.delayed(Duration.zero);
    final result = readBackup(widget.bytes);
    setState(() => check = result);
    if (!result.ok) return;
    final client = Supabase.instance.client;
    try {
      final live = await fetchLiveBalances(client);
      final changed = {
        for (final id in {...live.keys, ...result.balances.keys})
          if (live[id] != result.balances[id]) id,
      };
      if (mounted) setState(() => changedSince = changed.length);
      await client.rpc(
        'record_backup_verification',
        params: {
          'p_exported_at': result.exportedAt,
          'p_record_count': result.recordCount,
        },
      );
    } catch (e) {
      if (mounted) setState(() => liveError = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = check;
    final theme = Theme.of(context);
    Widget line(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
    return AlertDialog(
      title: Text(
        c == null
            ? 'Checking backup…'
            : c.ok
            ? 'Backup is good'
            : 'Backup has problems',
      ),
      content: SizedBox(
        width: 520,
        child: c == null
            ? const LinearProgressIndicator()
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (c.manifest != null) ...[
                      line('Business', c.organizationName),
                      line('Made', _when(c.exportedAt)),
                      line('Records', '${c.recordCount}'),
                      line(
                        'Uploaded files',
                        c.filesIncluded ? '${c.files.length}' : 'Not included',
                      ),
                      line('Loans', '${c.balances.length}'),
                      line(
                        'Active outstanding',
                        formatPeso(c.activeOutstanding),
                      ),
                      const Divider(),
                    ],
                    if (c.ok) ...[
                      const Text(
                        '✓ Every checksum, link between records and loan '
                        'balance matches.',
                      ),
                      const SizedBox(height: 8),
                      if (changedSince == null && liveError == null)
                        const Text('Comparing with the live data…')
                      else if (changedSince != null)
                        Text(
                          changedSince == 0
                              ? '✓ Identical to the live data right now.'
                              : '$changedSince loan(s) changed since this '
                                    'backup was made (payments or edits '
                                    'after it). That is expected for an older '
                                    'backup.',
                        ),
                      if (liveError != null)
                        Text(
                          'Could not compare with live data: $liveError',
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        'Restoring is done into a new, empty project with '
                        'tool/backup/restore.mjs (see docs/BACKUP_AND_RESTORE.md). '
                        'This check never changes live data.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ] else
                      for (final p in c.problems.take(20))
                        Text(
                          '• $p',
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  static String _when(String iso) {
    final t = DateTime.tryParse(iso)?.toLocal();
    if (t == null) return iso;
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-'
        '${t.day.toString().padLeft(2, '0')} '
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }
}
