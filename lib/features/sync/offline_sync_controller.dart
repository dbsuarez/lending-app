import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/local/offline_database.dart';
import '../../data/local/offline_outbox_database.dart';

class OfflineSyncState {
  const OfflineSyncState({
    required this.available,
    required this.pending,
    required this.syncing,
    this.lastError,
  });
  final bool available, syncing;
  final int pending;
  final String? lastError;
}

final offlineSyncControllerProvider =
    AsyncNotifierProvider<OfflineSyncController, OfflineSyncState>(
      OfflineSyncController.new,
    );

class OfflineSyncController extends AsyncNotifier<OfflineSyncState> {
  OfflineOutboxDatabase? _database;
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  @override
  Future<OfflineSyncState> build() async {
    if (!supported) {
      return const OfflineSyncState(
        available: false,
        pending: 0,
        syncing: false,
      );
    }
    try {
      _database = await openOfflineDatabase();
      final initial = OfflineSyncState(
        available: true,
        pending: await _database!.pendingCount(),
        syncing: false,
      );
      Future<void>.delayed(Duration.zero, retry);
      return initial;
    } catch (error) {
      return OfflineSyncState(
        available: false,
        pending: 0,
        syncing: false,
        lastError: error.toString(),
      );
    }
  }

  Future<void> enqueueCollectionActivity({
    required String id,
    required Map<String, dynamic> payload,
  }) async {
    final database = _database;
    if (database == null) throw StateError('Offline storage is unavailable.');
    await database.enqueue(
      id: id,
      operationType: 'collection_activity',
      payload: payload,
    );
    state = AsyncData(
      OfflineSyncState(
        available: true,
        pending: await database.pendingCount(),
        syncing: false,
      ),
    );
  }

  Future<void> retry() async {
    final database = _database;
    if (database == null || Supabase.instance.client.auth.currentUser == null) {
      return;
    }
    final current = state.value;
    if (current?.syncing == true) return;
    state = AsyncData(
      OfflineSyncState(
        available: true,
        pending: current?.pending ?? 0,
        syncing: true,
      ),
    );
    String? lastError;
    for (final operation in await database.pending()) {
      try {
        await database.markSyncing(operation.id);
        if (operation.operationType == 'collection_activity') {
          await Supabase.instance.client.rpc(
            'record_collection_activity',
            params: operation.payload,
          );
        } else {
          throw StateError(
            'Unsupported offline operation: ${operation.operationType}',
          );
        }
        await database.acknowledge(operation.id);
      } catch (error) {
        lastError = error.toString();
        await database.markFailed(operation.id, error);
      }
    }
    state = AsyncData(
      OfflineSyncState(
        available: true,
        pending: await database.pendingCount(),
        syncing: false,
        lastError: lastError,
      ),
    );
  }
}
