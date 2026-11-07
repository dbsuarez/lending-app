import 'offline_outbox_database.dart';

Future<OfflineOutboxDatabase> openOfflineDatabase() =>
    throw UnsupportedError('Offline persistence is available on Android only.');
