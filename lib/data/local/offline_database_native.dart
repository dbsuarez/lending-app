import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'offline_outbox_database.dart';

Future<OfflineOutboxDatabase> openOfflineDatabase() async {
  const storage = FlutterSecureStorage(
    aOptions: AndroidOptions(storageNamespace: 'lending_manager'),
  );
  var key = await storage.read(key: 'offline_database_key');
  if (key == null) {
    final random = Random.secure();
    key = base64UrlEncode(List<int>.generate(32, (_) => random.nextInt(256)));
    await storage.write(key: 'offline_database_key', value: key);
  }
  final directory = await getApplicationDocumentsDirectory();
  final file = File(p.join(directory.path, 'lending_manager.sqlite'));
  final escaped = key.replaceAll("'", "''");
  return OfflineOutboxDatabase(
    NativeDatabase(
      file,
      setup: (database) {
        database.execute("PRAGMA key = '$escaped'");
        database.execute('PRAGMA foreign_keys = ON');
        if (database.select('PRAGMA cipher_version').isEmpty) {
          throw StateError('Encrypted SQLite is unavailable.');
        }
      },
    ),
  );
}
