import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lending_manager/data/local/offline_outbox_database.dart';

void main() {
  test(
    'offline outbox keeps one operation per id and tracks retry state',
    () async {
      final database = OfflineOutboxDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      const payload = <String, dynamic>{
        'p_loan_id': 'loan-1',
        'p_activity_type': 'call',
        'p_outcome': 'No response',
      };
      await database.enqueue(
        id: 'operation-1',
        operationType: 'collection_activity',
        payload: payload,
      );
      await database.enqueue(
        id: 'operation-1',
        operationType: 'collection_activity',
        payload: payload,
      );
      expect(await database.pendingCount(), 1);
      await database.markSyncing('operation-1');
      await database.markFailed('operation-1', StateError('offline'));
      final pending = await database.pending();
      expect(pending, hasLength(1));
      expect(pending.single.attempts, 1);
      expect(pending.single.state, 'needs_attention');
      await database.acknowledge('operation-1');
      expect(await database.pendingCount(), 0);
    },
  );
}
