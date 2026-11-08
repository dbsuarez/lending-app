import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lending_manager/features/settings/backup_archive.dart';
import 'package:supabase/supabase.dart';

const org = 'org-1';

BackupData sample({List<BackupFile>? files}) => BackupData(
  organizationId: org,
  organizationName: 'Test',
  tables: {
    for (final t in backupTables) t: <Map<String, dynamic>>[],
    'organizations': [
      {'id': org, 'name': 'Test'},
    ],
    'organization_members': [
      {'organization_id': org, 'user_id': 'u1', 'role': 'owner'},
    ],
    'borrowers': [
      {'id': 'b1', 'organization_id': org},
    ],
    'loans': [
      {
        'id': 'l1',
        'organization_id': org,
        'borrower_id': 'b1',
        'status': 'active',
        'total_centavos': 3000,
      },
    ],
    'installments': [
      for (var i = 1; i <= 3; i++)
        {
          'id': 'i$i',
          'organization_id': org,
          'loan_id': 'l1',
          'scheduled_centavos': 1000,
        },
    ],
    'payments': [
      {
        'id': 'p1',
        'organization_id': org,
        'loan_id': 'l1',
        'status': 'verified',
      },
      {
        'id': 'p2',
        'organization_id': org,
        'loan_id': 'l1',
        'status': 'reversed',
      },
    ],
    'payment_allocations': [
      {
        'id': 'a1',
        'organization_id': org,
        'payment_id': 'p1',
        'installment_id': 'i1',
        'principal_centavos': 800,
        'interest_centavos': 200,
        'penalty_centavos': 0,
      },
      {
        'id': 'a2',
        'organization_id': org,
        'payment_id': 'p2',
        'installment_id': 'i2',
        'principal_centavos': 1000,
        'interest_centavos': 0,
        'penalty_centavos': 0,
      },
    ],
    'loan_documents': [
      if (files != null)
        {
          'id': 'd1',
          'organization_id': org,
          'loan_id': 'l1',
          'storage_path': 'org-1/l1/r.jpg',
        },
    ],
  },
  files: files,
);

Uint8List tamper(
  Uint8List zip,
  String name,
  List<int> Function(List<int>) change,
) {
  final a = ZipDecoder().decodeBytes(zip);
  final out = Archive();
  for (final f in a.files) {
    out.addFile(
      ArchiveFile.bytes(
        f.name,
        f.name == name ? change(f.readBytes()!) : f.readBytes()!,
      ),
    );
  }
  return Uint8List.fromList(ZipEncoder().encode(out));
}

void main() {
  test('round trip passes every check; balances ignore reversed payments', () {
    final check = readBackup(encodeBackup(sample()));
    expect(check.problems, isEmpty);
    expect(check.balances['l1']!.paid, 1000);
    expect(check.balances['l1']!.outstanding, 2000);
    expect(check.activeOutstanding, 2000);
    expect(check.recordCount, 11);
  });

  test('edited, missing or broken content is caught', () {
    final zip = encodeBackup(sample());
    final edited = readBackup(
      tamper(
        zip,
        'tables/payments.json',
        (b) => utf8.encode(utf8.decode(b).replaceFirst('reversed', 'verified')),
      ),
    );
    expect(
      edited.problems.any((p) => p.contains('payments: checksum')),
      isTrue,
    );
    expect(readBackup(Uint8List.fromList([1, 2, 3])).ok, isFalse);
  });

  test('uploaded files are included and verified', () {
    final file = BackupFile(
      'loan-evidence',
      'org-1/l1/r.jpg',
      Uint8List.fromList([9, 9, 9]),
    );
    final zip = encodeBackup(sample(files: [file]));
    final check = readBackup(zip);
    expect(check.problems, isEmpty);
    expect(check.files.single.bytes, [9, 9, 9]);
    final damaged = readBackup(
      tamper(zip, 'files/loan-evidence/org-1/l1/r.jpg', (_) => [1]),
    );
    expect(damaged.problems.any((p) => p.contains('file damaged')), isTrue);
  });

  // Live, read-only: the app's own reader against the real project.
  //   LIVE_BACKUP_TEST=1 flutter test test/backup_archive_test.dart
  test('reads every row of the live project and the result checks out', () async {
    if (Platform.environment['LIVE_BACKUP_TEST'] != '1') return;
    final env = {
      for (final l in File('.env').readAsLinesSync())
        if (l.contains('='))
          l.substring(0, l.indexOf('=')).trim(): l
              .substring(l.indexOf('=') + 1)
              .trim(),
    };
    final client = SupabaseClient(
      env['SUPABASE_URL']!,
      env['SUPABASE_ANON_KEY']!,
    );
    await client.auth.signInWithPassword(
      email: env['DEV_LOGIN_EMAIL']!,
      password: env['DEV_LOGIN_PASSWORD']!,
    );
    final steps = <String>[];
    final data = await fetchBackupData(
      client,
      includeFiles: true,
      onProgress: steps.add,
    );
    final check = readBackup(encodeBackup(data));
    expect(check.problems, isEmpty);
    for (final t in backupTables) {
      final n = await client
          .from(t)
          .count()
          .eq(
            t == 'organizations' ? 'id' : 'organization_id',
            data.organizationId,
          );
      expect(check.tables[t]!.length, n, reason: t);
    }
    final live = await fetchLiveBalances(client);
    expect(diffBalances(live, check.balances), isEmpty);
    // ignore: avoid_print
    print(
      'live: ${check.recordCount} records, ${check.files.length} files, ${check.balances.length} loans',
    );
    await client.auth.signOut();
  });

  // Cross-check with the command-line tools on a real backup:
  //   BACKUP_XCHECK_IN=backups/x.zip BACKUP_XCHECK_OUT=out.zip flutter test test/backup_archive_test.dart
  // then: node tool/backup/restore.mjs out.zip --drill
  test('reads a backup made by the weekly tool and writes one it accepts', () {
    final input = Platform.environment['BACKUP_XCHECK_IN'];
    final output = Platform.environment['BACKUP_XCHECK_OUT'];
    if (input == null || output == null) return;
    final check = readBackup(File(input).readAsBytesSync());
    expect(check.problems, isEmpty);
    final again = encodeBackup(
      BackupData(
        organizationId: '${check.manifest!['organization_id']}',
        organizationName: check.organizationName,
        tables: check.tables,
        files: check.filesIncluded ? check.files : null,
      ),
    );
    File(output).writeAsBytesSync(again);
    expect(readBackup(again).balances.length, check.balances.length);
  });
}
