import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Lending Manager backup archive, format v2. The same format is written and
/// read by the command-line tools in tool/backup (backup, drill, restore).
///
/// A zip holding:
///   manifest.json          per-table count + sha256, per-file size + sha256,
///                          loan balances at export
///   tables/TABLE.json      all rows of that table
///   files/BUCKET/PATH      uploaded documents/evidence (optional)
const backupFormat = 'lending-manager-backup-v2';

/// Restore order: parents first.
const backupTables = [
  'organizations',
  'organization_members',
  'borrowers',
  'loans',
  'installments',
  'penalty_charges',
  'loan_documents',
  'loan_disbursements',
  'loan_amendments',
  'payments',
  'payment_allocations',
  'payment_corrections',
  'collection_activities',
  'loan_share_links',
  'staff_invitations',
  'audit_events',
];

const _evidenceBucket = 'loan-evidence';

/// Tables added later; backups made before them simply have none.
const _optionalTables = {'penalty_charges'};

List<String> _pkOf(String table) => table == 'organization_members'
    ? const ['organization_id', 'user_id']
    : const ['id'];
String _orgColumnOf(String table) =>
    table == 'organizations' ? 'id' : 'organization_id';

typedef Rows = List<Map<String, dynamic>>;

class BackupFile {
  const BackupFile(this.bucket, this.path, this.bytes);
  final String bucket, path;
  final Uint8List bytes;
}

class BackupData {
  const BackupData({
    required this.organizationId,
    required this.organizationName,
    required this.tables,
    this.files,
  });
  final String organizationId, organizationName;
  final Map<String, Rows> tables;

  /// Null when files were not included.
  final List<BackupFile>? files;
}

class LoanBalance {
  const LoanBalance(this.status, this.total, this.paid, this.outstanding);
  final String status;
  final int total, paid, outstanding;

  Map<String, dynamic> toJson() => {
    'status': status,
    'total': total,
    'paid': paid,
    'outstanding': outstanding,
  };

  static LoanBalance fromJson(Map<String, dynamic> j) => LoanBalance(
    '${j['status']}',
    (j['total'] as num).toInt(),
    (j['paid'] as num).toInt(),
    (j['outstanding'] as num).toInt(),
  );

  @override
  bool operator ==(Object other) =>
      other is LoanBalance &&
      other.status == status &&
      other.total == total &&
      other.paid == paid &&
      other.outstanding == outstanding;

  @override
  int get hashCode => Object.hash(status, total, paid, outstanding);
}

int _int(Object? v) => v == null ? 0 : (v as num).toInt();

/// Per loan, like the dashboard and aging reports: per installment,
/// outstanding = max(scheduled - verified allocations, 0).
Map<String, LoanBalance> computeBalances(Map<String, Rows> tables) {
  final status = {
    for (final p in tables['payments'] ?? const <Map<String, dynamic>>[])
      p['id']: p['status'],
  };
  final paidByInstallment = <Object?, int>{};
  for (final a in tables['payment_allocations'] ?? const []) {
    if (status[a['payment_id']] != 'verified') continue;
    paidByInstallment[a['installment_id']] =
        (paidByInstallment[a['installment_id']] ?? 0) +
        _int(a['principal_centavos']) +
        _int(a['interest_centavos']) +
        _int(a['penalty_centavos']);
  }
  final totals = <String, List<int>>{};
  final statuses = <String, String>{};
  for (final l in tables['loans'] ?? const []) {
    final id = l['id'] as String;
    totals[id] = [_int(l['total_centavos']), 0, 0];
    statuses[id] = '${l['status']}';
  }
  for (final i in tables['installments'] ?? const []) {
    final t = totals[i['loan_id']];
    if (t == null) continue;
    final paid = paidByInstallment[i['id']] ?? 0;
    t[1] += paid;
    final left = _int(i['scheduled_centavos']) - paid;
    t[2] += left > 0 ? left : 0;
  }
  return {
    for (final e in totals.entries)
      e.key: LoanBalance(statuses[e.key]!, e.value[0], e.value[1], e.value[2]),
  };
}

String _keyOf(String table, Map<String, dynamic> row) =>
    _pkOf(table).map((c) => '${row[c]}').join('|');

/// Builds the zip.
Uint8List encodeBackup(BackupData data, {String source = 'app'}) {
  final archive = Archive();
  final balances = computeBalances(data.tables);
  final tableMeta = <String, dynamic>{};
  for (final t in backupTables) {
    final rows = [...?data.tables[t]]
      ..sort((a, b) => _keyOf(t, a).compareTo(_keyOf(t, b)));
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(rows)));
    archive.addFile(ArchiveFile.bytes('tables/$t.json', bytes));
    tableMeta[t] = {'count': rows.length, 'sha256': '${sha256.convert(bytes)}'};
  }
  final fileMeta = <Map<String, dynamic>>[];
  for (final f in data.files ?? const <BackupFile>[]) {
    archive.addFile(
      ArchiveFile.bytes('files/${f.bucket}/${f.path}', f.bytes)
        ..compression = CompressionType.none,
    );
    fileMeta.add({
      'bucket': f.bucket,
      'path': f.path,
      'size': f.bytes.length,
      'sha256': '${sha256.convert(f.bytes)}',
    });
  }
  var active = 0;
  for (final b in balances.values) {
    if (b.status == 'active') active += b.outstanding;
  }
  final manifest = {
    'format': backupFormat,
    'source': source,
    'exported_at': DateTime.now().toUtc().toIso8601String(),
    'organization_id': data.organizationId,
    'organization_name': data.organizationName,
    'schema_version': null,
    'tables': tableMeta,
    'files_included': data.files != null,
    'files': fileMeta,
    'balances': {for (final e in balances.entries) e.key: e.value.toJson()},
    'totals': {'loans': balances.length, 'outstanding_active_centavos': active},
  };
  archive.addFile(
    ArchiveFile.bytes(
      'manifest.json',
      utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest)),
    ),
  );
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

class BackupCheck {
  BackupCheck({
    required this.problems,
    this.manifest,
    this.tables = const {},
    this.balances = const {},
    this.files = const [],
  });
  final List<String> problems;
  final Map<String, dynamic>? manifest;
  final Map<String, Rows> tables;
  final Map<String, LoanBalance> balances;
  final List<BackupFile> files;

  bool get ok => problems.isEmpty;
  int get recordCount =>
      tables.values.fold(0, (sum, rows) => sum + rows.length);
  String get exportedAt => '${manifest?['exported_at'] ?? ''}';
  String get organizationName => '${manifest?['organization_name'] ?? ''}';
  bool get filesIncluded => manifest?['files_included'] == true;
  int get activeOutstanding {
    var sum = 0;
    for (final b in balances.values) {
      if (b.status == 'active') sum += b.outstanding;
    }
    return sum;
  }
}

/// Opens and fully checks a backup. Never throws for a bad file.
BackupCheck readBackup(Uint8List bytes) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    return BackupCheck(problems: ['Not a readable backup (zip) file']);
  }
  Uint8List? entry(String name) => archive.findFile(name)?.readBytes();
  final manifestBytes = entry('manifest.json');
  if (manifestBytes == null) {
    return BackupCheck(problems: ['manifest.json is missing']);
  }
  final Map<String, dynamic> manifest;
  try {
    manifest = jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
  } catch (_) {
    return BackupCheck(problems: ['manifest.json is not valid']);
  }
  if (manifest['format'] != backupFormat) {
    return BackupCheck(problems: ['Unsupported format ${manifest['format']}']);
  }
  final problems = <String>[];
  final tables = <String, Rows>{};
  final meta = (manifest['tables'] as Map?) ?? const {};
  for (final t in backupTables) {
    final bytes = entry('tables/$t.json');
    final m = meta[t] as Map?;
    tables[t] = [];
    if (bytes == null && m == null && _optionalTables.contains(t)) continue;
    if (bytes == null || m == null) {
      problems.add('$t: missing');
      continue;
    }
    if ('${sha256.convert(bytes)}' != m['sha256']) {
      problems.add('$t: checksum mismatch (file damaged or edited)');
    }
    try {
      tables[t] = (jsonDecode(utf8.decode(bytes)) as List)
          .cast<Map<String, dynamic>>();
    } catch (_) {
      problems.add('$t: not valid');
      continue;
    }
    if (tables[t]!.length != m['count']) {
      problems.add(
        '$t: ${tables[t]!.length} rows, manifest says ${m['count']}',
      );
    }
  }
  for (final t in const ['organizations', 'organization_members']) {
    if (tables[t]!.isEmpty) problems.add('$t: no rows');
  }
  final orgId = manifest['organization_id'];
  for (final t in backupTables) {
    final col = _orgColumnOf(t);
    final strays = tables[t]!.where((r) => r[col] != orgId).length;
    if (strays > 0) problems.add('$t: $strays rows from another organization');
    final keys = tables[t]!.map((r) => _keyOf(t, r)).toSet();
    if (keys.length != tables[t]!.length) problems.add('$t: duplicate rows');
  }
  Set<Object?> ids(String t) => tables[t]!.map((r) => r['id']).toSet();
  final loans = ids('loans');
  final refs = <(String, String, Set<Object?>)>[
    ('loans', 'borrower_id', ids('borrowers')),
    ('installments', 'loan_id', loans),
    ('loan_documents', 'loan_id', loans),
    ('loan_disbursements', 'loan_id', loans),
    ('loan_amendments', 'loan_id', loans),
    ('loan_amendments', 'supporting_document_id', ids('loan_documents')),
    ('payments', 'loan_id', loans),
    ('payment_allocations', 'payment_id', ids('payments')),
    ('payment_allocations', 'installment_id', ids('installments')),
    ('payment_corrections', 'payment_id', ids('payments')),
    ('collection_activities', 'loan_id', loans),
    ('loan_share_links', 'loan_id', loans),
    ('penalty_charges', 'loan_id', loans),
    ('penalty_charges', 'installment_id', ids('installments')),
  ];
  for (final (t, col, set) in refs) {
    final broken = tables[t]!
        .where((r) => r[col] != null && !set.contains(r[col]))
        .length;
    if (broken > 0) {
      problems.add('$t.$col: $broken rows point to records not in the backup');
    }
  }
  final balances = computeBalances(tables);
  final recorded = (manifest['balances'] as Map?)?.cast<String, dynamic>();
  if (recorded != null) {
    final diffs = diffBalances({
      for (final e in recorded.entries)
        e.key: LoanBalance.fromJson((e.value as Map).cast<String, dynamic>()),
    }, balances);
    problems.addAll(diffs.take(10).map((d) => 'balance: $d'));
  }
  final files = <BackupFile>[];
  if (manifest['files_included'] == true) {
    final listed = <String>{};
    for (final f in (manifest['files'] as List? ?? const [])) {
      final path = '${f['path']}';
      listed.add(path);
      final bytes = entry('files/${f['bucket']}/$path');
      if (bytes == null) {
        problems.add('file missing: $path');
        continue;
      }
      if ('${sha256.convert(bytes)}' != f['sha256'] ||
          bytes.length != f['size']) {
        problems.add('file damaged: $path');
      }
      files.add(BackupFile('${f['bucket']}', path, bytes));
    }
    for (final d in tables['loan_documents']!) {
      if (!listed.contains(d['storage_path'])) {
        problems.add('document without its file: ${d['storage_path']}');
      }
    }
  }
  return BackupCheck(
    problems: problems,
    manifest: manifest,
    tables: tables,
    balances: balances,
    files: files,
  );
}

List<String> diffBalances(
  Map<String, LoanBalance> expected,
  Map<String, LoanBalance> actual,
) {
  final diffs = <String>[];
  for (final id in {...expected.keys, ...actual.keys}) {
    final e = expected[id], a = actual[id];
    if (e == null || a == null) {
      diffs.add('loan $id: ${e == null ? 'not in backup' : 'missing'}');
    } else if (e != a) {
      diffs.add(
        'loan $id: outstanding ${e.outstanding} vs ${a.outstanding}, '
        'paid ${e.paid} vs ${a.paid}, status ${e.status} vs ${a.status}',
      );
    }
  }
  return diffs;
}

// ---- Reading from the live project ----------------------------------------

const _page = 500;

Future<Rows> _fetchAll(
  SupabaseClient client,
  String table,
  String orgId,
) async {
  final col = _orgColumnOf(table);
  final expected = await client.from(table).count().eq(col, orgId);
  final rows = <Map<String, dynamic>>[];
  while (rows.length < expected) {
    var query = client.from(table).select().eq(col, orgId);
    final ordered = _pkOf(table).fold<PostgrestTransformBuilder<Rows>>(
      query,
      (q, c) => q.order(c, ascending: true),
    );
    final page = await ordered.range(rows.length, rows.length + _page - 1);
    if (page.isEmpty) break;
    rows.addAll(page);
  }
  if (rows.length != expected) {
    throw StateError('$table: read ${rows.length} of $expected rows');
  }
  return rows;
}

Future<String> _ownerOrganization(SupabaseClient client) async {
  final m = await client
      .from('organization_members')
      .select('organization_id, role')
      .eq('user_id', client.auth.currentUser!.id)
      .eq('status', 'active')
      .limit(1)
      .single();
  if (m['role'] != 'owner') {
    throw StateError('Only the owner can make a full backup.');
  }
  return m['organization_id'] as String;
}

/// Reads every table (all rows, page by page) and, optionally, every file.
Future<BackupData> fetchBackupData(
  SupabaseClient client, {
  required bool includeFiles,
  void Function(String step)? onProgress,
}) async {
  final orgId = await _ownerOrganization(client);
  final tables = <String, Rows>{};
  for (final t in backupTables) {
    onProgress?.call('Reading ${t.replaceAll('_', ' ')}…');
    tables[t] = await _fetchAll(client, t, orgId);
  }
  List<BackupFile>? files;
  if (includeFiles) {
    files = [];
    final docs = tables['loan_documents']!;
    for (var i = 0; i < docs.length; i++) {
      onProgress?.call('Downloading files ${i + 1} of ${docs.length}…');
      final path = docs[i]['storage_path'] as String;
      files.add(
        BackupFile(
          _evidenceBucket,
          path,
          await client.storage.from(_evidenceBucket).download(path),
        ),
      );
    }
  }
  final org = tables['organizations']!.firstOrNull;
  return BackupData(
    organizationId: orgId,
    organizationName: '${org?['name'] ?? ''}',
    tables: tables,
    files: files,
  );
}

/// Live balances for comparing a backup with the app as it is now.
Future<Map<String, LoanBalance>> fetchLiveBalances(
  SupabaseClient client,
) async {
  final orgId = await _ownerOrganization(client);
  return computeBalances({
    for (final t in const [
      'loans',
      'installments',
      'payments',
      'payment_allocations',
    ])
      t: await _fetchAll(client, t, orgId),
  });
}

// ---- Per-loan restore -----------------------------------------------------

/// Tables that make up one loan's state (see restore_loan in the database).
const loanStateTables = [
  'loans',
  'installments',
  'loan_disbursements',
  'payments',
  'payment_allocations',
  'payment_corrections',
  'loan_amendments',
  'collection_activities',
  'loan_share_links',
  'penalty_charges',
];

/// One loan's records in the shape restore_loan expects; null when the loan
/// is not in [tables]. Mirrors loanStateFromTables in tool/backup.
Map<String, dynamic>? loanStateFromBackup(
  Map<String, Rows> tables,
  String loanId,
) {
  final loan = tables['loans']!.where((l) => l['id'] == loanId).firstOrNull;
  if (loan == null) return null;
  Rows byLoan(String t) =>
      tables[t]!.where((r) => r['loan_id'] == loanId).toList();
  final payments = byLoan('payments');
  final paymentIds = payments.map((p) => p['id']).toSet();
  return {
    'loan': loan,
    'installments': byLoan('installments'),
    'loan_disbursements': byLoan('loan_disbursements'),
    'payments': payments,
    'payment_allocations': tables['payment_allocations']!
        .where((a) => paymentIds.contains(a['payment_id']))
        .toList(),
    'payment_corrections': tables['payment_corrections']!
        .where((c) => paymentIds.contains(c['payment_id']))
        .toList(),
    'loan_amendments': byLoan('loan_amendments'),
    'collection_activities': byLoan('collection_activities'),
    'loan_share_links': byLoan('loan_share_links'),
    'penalty_charges': byLoan('penalty_charges'),
  };
}

/// A stable text form of any JSON value (map keys sorted), for comparing.
String canonicalJson(Object? value) {
  Object? sort(Object? v) => switch (v) {
    Map() => {
      for (final k in (v.keys.map((k) => '$k').toList()..sort())) k: sort(v[k]),
    },
    List() => [for (final x in v) sort(x)],
    _ => v,
  };
  return jsonEncode(sort(value));
}

/// The live rows of the loan-state tables (and borrowers, for names), for
/// comparing with a backup.
Future<Map<String, Rows>> fetchLiveLoanTables(SupabaseClient client) async {
  final orgId = await _ownerOrganization(client);
  return {
    for (final t in [...loanStateTables, 'borrowers'])
      t: await _fetchAll(client, t, orgId),
  };
}
