import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/app_config.dart';
import '../../data/repositories/supabase_collections_repository.dart';
import '../../domain/models/models.dart';
import '../sync/offline_sync_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

final collectionsControllerProvider =
    AsyncNotifierProvider<CollectionsController, List<CollectionActivity>>(
      CollectionsController.new,
    );

class CollectionsController extends AsyncNotifier<List<CollectionActivity>> {
  SupabaseCollectionsRepository? _repository;
  final List<CollectionActivity> _local = [];
  bool lastRecordQueued = false;

  /// Id of the last activity saved online (null when queued offline,
  /// which cannot be undone until it syncs).
  String? lastRecordedId;
  bool get isLive =>
      AppConfig.hasSupabase &&
      Supabase.instance.client.auth.currentUser != null;

  @override
  Future<List<CollectionActivity>> build() async {
    if (!isLive) return List.unmodifiable(_local);
    _repository = SupabaseCollectionsRepository(Supabase.instance.client);
    return _repository!.fetchActivities();
  }

  Future<void> refresh() async {
    if (!isLive) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(_repository!.fetchActivities);
  }

  /// See LoansController._initialBuild: demo-mode inserts must wait for the
  /// first async build, or its stale empty result overwrites them.
  Future<void> _initialBuild() async {
    try {
      await future;
    } catch (_) {}
  }

  Future<bool> record({
    required LoanSummary loan,
    required String type,
    required String outcome,
    required String notes,
    DateTime? promisedOn,
    int? promisedAmountCentavos,
  }) async {
    if (!isLive) await _initialBuild();
    lastRecordQueued = false;
    lastRecordedId = null;
    final operationId = const Uuid().v4();
    final payload = <String, dynamic>{
      'p_loan_id': loan.id,
      'p_activity_type': type,
      'p_outcome': outcome,
      'p_notes': notes,
      'p_promised_on': promisedOn == null ? null : _date(promisedOn),
      'p_promised_amount_centavos': promisedAmountCentavos,
      'p_client_operation_id': operationId,
    };
    try {
      if (isLive) {
        lastRecordedId = await _repository!.record(
          loanId: loan.id,
          type: type,
          outcome: outcome,
          notes: notes,
          promisedOn: promisedOn,
          promisedAmountCentavos: promisedAmountCentavos,
          clientOperationId: operationId,
        );
        state = AsyncData(await _repository!.fetchActivities());
      } else {
        lastRecordedId = DateTime.now().microsecondsSinceEpoch.toString();
        _local.insert(
          0,
          CollectionActivity(
            id: lastRecordedId!,
            loanId: loan.id,
            borrowerName: loan.borrowerName,
            type: type,
            outcome: outcome,
            notes: notes,
            promisedOn: promisedOn,
            promisedAmountCentavos: promisedAmountCentavos,
            contactedAt: DateTime.now(),
          ),
        );
        state = AsyncData(List.unmodifiable(_local));
      }
      return true;
    } catch (_) {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        try {
          await ref
              .read(offlineSyncControllerProvider.notifier)
              .enqueueCollectionActivity(id: operationId, payload: payload);
          lastRecordQueued = true;
          _local.insert(
            0,
            CollectionActivity(
              id: operationId,
              loanId: loan.id,
              borrowerName: loan.borrowerName,
              type: type,
              outcome: '$outcome (Pending sync)',
              notes: notes,
              promisedOn: promisedOn,
              promisedAmountCentavos: promisedAmountCentavos,
              contactedAt: DateTime.now(),
            ),
          );
          state = AsyncData(List.unmodifiable(_local));
          return true;
        } catch (_) {}
      }
      return false;
    }
  }

  /// Undo "log collection activity" (marks it undone; hidden from lists).
  Future<bool> undoRecord(String activityId) async {
    try {
      if (isLive) {
        await _repository!.undo(activityId);
        state = AsyncData(await _repository!.fetchActivities());
        return true;
      }
      await _initialBuild();
      final before = _local.length;
      _local.removeWhere((item) => item.id == activityId);
      state = AsyncData(List.unmodifiable(_local));
      return _local.length < before;
    } catch (_) {
      return false;
    }
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
