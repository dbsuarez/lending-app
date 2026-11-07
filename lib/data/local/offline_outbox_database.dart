import 'dart:convert';
import 'package:drift/drift.dart';

class OfflineOperation {
  const OfflineOperation({
    required this.id,
    required this.operationType,
    required this.payload,
    required this.state,
    required this.attempts,
    required this.createdAt,
    this.lastError,
  });
  final String id, operationType, state;
  final Map<String, dynamic> payload;
  final int attempts;
  final DateTime createdAt;
  final String? lastError;
}

class OfflineOutboxDatabase extends GeneratedDatabase {
  OfflineOutboxDatabase(super.executor);
  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) => _ensureSchema(),
    beforeOpen: (_) => _ensureSchema(),
  );

  Future<void> _ensureSchema() => customStatement('''
    CREATE TABLE IF NOT EXISTS sync_outbox (
      id TEXT PRIMARY KEY,
      operation_type TEXT NOT NULL,
      payload_json TEXT NOT NULL,
      state TEXT NOT NULL DEFAULT 'pending' CHECK (state IN ('pending','syncing','needs_attention')),
      attempts INTEGER NOT NULL DEFAULT 0,
      last_error TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');

  Future<void> enqueue({
    required String id,
    required String operationType,
    required Map<String, dynamic> payload,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await customInsert(
      'INSERT OR IGNORE INTO sync_outbox (id, operation_type, payload_json, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
      variables: [
        Variable(id),
        Variable(operationType),
        Variable(jsonEncode(payload)),
        Variable(now),
        Variable(now),
      ],
    );
  }

  Future<List<OfflineOperation>> pending() async {
    final rows = await customSelect(
      "SELECT * FROM sync_outbox WHERE state IN ('pending','needs_attention') ORDER BY created_at",
    ).get();
    return [for (final row in rows) _fromRow(row)];
  }

  Future<int> pendingCount() async {
    final row = await customSelect(
      "SELECT COUNT(*) AS total FROM sync_outbox WHERE state IN ('pending','needs_attention')",
    ).getSingle();
    return row.read<int>('total');
  }

  Future<void> markSyncing(String id) => customStatement(
    "UPDATE sync_outbox SET state='syncing', attempts=attempts+1, updated_at=? WHERE id=?",
    [DateTime.now().toUtc().toIso8601String(), id],
  );
  Future<void> acknowledge(String id) =>
      customStatement('DELETE FROM sync_outbox WHERE id=?', [id]);
  Future<void> markFailed(String id, Object error) {
    final message = error.toString();
    return customStatement(
      "UPDATE sync_outbox SET state='needs_attention', last_error=?, updated_at=? WHERE id=?",
      [
        message.substring(0, message.length.clamp(0, 500)),
        DateTime.now().toUtc().toIso8601String(),
        id,
      ],
    );
  }

  OfflineOperation _fromRow(QueryRow row) => OfflineOperation(
    id: row.read<String>('id'),
    operationType: row.read<String>('operation_type'),
    payload: Map<String, dynamic>.from(
      jsonDecode(row.read<String>('payload_json')) as Map,
    ),
    state: row.read<String>('state'),
    attempts: row.read<int>('attempts'),
    createdAt: DateTime.parse(row.read<String>('created_at')),
    lastError: row.readNullable<String>('last_error'),
  );
}
