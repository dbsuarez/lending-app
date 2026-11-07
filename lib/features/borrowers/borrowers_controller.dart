import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/app_config.dart';
import '../../data/repositories/demo_repository.dart';
import '../../data/repositories/supabase_borrowers_repository.dart';
import '../../domain/models/models.dart';

final borrowersControllerProvider =
    AsyncNotifierProvider<BorrowersController, List<Borrower>>(
      BorrowersController.new,
    );

class BorrowersController extends AsyncNotifier<List<Borrower>> {
  SupabaseBorrowersRepository? _repository;
  bool lastSaveConflict = false;

  bool get isLive =>
      AppConfig.hasSupabase &&
      Supabase.instance.client.auth.currentUser != null;

  @override
  Future<List<Borrower>> build() async {
    if (!isLive) return ref.watch(borrowersProvider);
    _repository = SupabaseBorrowersRepository(Supabase.instance.client);
    return _repository!.fetchActive();
  }

  Future<void> refresh() async {
    if (!isLive) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repository!.fetchActive());
  }

  Future<bool> save({
    String? id,
    required String firstName,
    required String lastName,
    required String phone,
    required String email,
    required String address,
    bool consentConfirmed = false,
    DateTime? expectedUpdatedAt,
  }) async {
    lastSaveConflict = false;
    if (!isLive) {
      ref
          .read(borrowersProvider.notifier)
          .save(
            id: id,
            firstName: firstName,
            lastName: lastName,
            phone: phone,
            email: email,
            address: address,
          );
      state = AsyncData(ref.read(borrowersProvider));
      return true;
    }

    state = const AsyncLoading<List<Borrower>>();
    try {
      final borrowerId = await _repository!.save(
        id: id,
        firstName: firstName,
        lastName: lastName,
        phone: phone,
        email: email,
        address: address,
        expectedUpdatedAt: expectedUpdatedAt,
      );
      if (id == null && consentConfirmed) {
        await _repository!.recordConsent(borrowerId);
      }
      state = AsyncData(await _repository!.fetchActive());
      return true;
    } catch (error, stackTrace) {
      lastSaveConflict = error is PostgrestException && error.code == '40001';
      state = AsyncError<List<Borrower>>(error, stackTrace);
      return false;
    }
  }

  Future<bool> archive(Borrower borrower) async {
    if (!isLive) {
      ref.read(borrowersProvider.notifier).archive(borrower.id);
      state = AsyncData(ref.read(borrowersProvider));
      return true;
    }

    state = const AsyncLoading<List<Borrower>>();
    try {
      await _repository!.archive(borrower.id);
      state = AsyncData(await _repository!.fetchActive());
      return true;
    } catch (error, stackTrace) {
      state = AsyncError<List<Borrower>>(error, stackTrace);
      return false;
    }
  }

  Future<List<Borrower>> fetchArchived() async {
    if (!isLive) return const [];
    return _repository!.fetchArchived();
  }

  Future<bool> restore(Borrower borrower) async {
    if (!isLive) return false;
    try {
      await _repository!.restore(borrower.id);
      state = AsyncData(await _repository!.fetchActive());
      return true;
    } catch (_) {
      return false;
    }
  }
}
