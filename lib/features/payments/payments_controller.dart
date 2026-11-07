import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../core/config/app_config.dart';
import '../../data/repositories/supabase_payments_repository.dart';
import '../../domain/models/models.dart';

final paymentsControllerProvider =
    AsyncNotifierProvider<PaymentsController, List<PaymentSummary>>(
      PaymentsController.new,
    );

class PaymentsController extends AsyncNotifier<List<PaymentSummary>> {
  SupabasePaymentsRepository? _repository;
  final List<PaymentSummary> _localPayments = [];

  bool get isLive =>
      AppConfig.hasSupabase &&
      Supabase.instance.client.auth.currentUser != null;

  @override
  Future<List<PaymentSummary>> build() async {
    if (!isLive) return List.unmodifiable(_localPayments);
    _repository = SupabasePaymentsRepository(Supabase.instance.client);
    return _repository!.fetchPayments();
  }

  Future<void> refresh() async {
    if (!isLive) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repository!.fetchPayments());
  }

  /// See LoansController._initialBuild: demo-mode inserts must wait for the
  /// first async build, or its stale empty result overwrites them.
  Future<void> _initialBuild() async {
    try {
      await future;
    } catch (_) {}
  }

  /// Returns the new payment id, or null on failure.
  Future<String?> recordPending({
    required LoanSummary loan,
    required int amountCentavos,
    required DateTime receivedAt,
    required String method,
    required String reference,
  }) async {
    if (!isLive) await _initialBuild();
    state = const AsyncLoading();
    try {
      final id = const Uuid().v4();
      if (isLive) {
        final userId = Supabase.instance.client.auth.currentUser!.id;
        final saved = await _repository!.recordPending(
          loanId: loan.id,
          amountCentavos: amountCentavos,
          receivedAt: receivedAt,
          method: method,
          reference: reference,
          clientOperationId: id,
          deviceId: '${kIsWeb ? 'web' : 'android'}-$userId',
        );
        state = AsyncData(await _repository!.fetchPayments());
        return saved;
      } else {
        _localPayments.insert(
          0,
          PaymentSummary(
            id: id,
            loanId: loan.id,
            borrowerName: loan.borrowerName,
            amountCentavos: amountCentavos,
            receivedAt: receivedAt,
            method: method,
            reference: reference,
            status: method == 'Cash' ? 'verified' : 'pending',
            unappliedCentavos: 0,
          ),
        );
        state = AsyncData(List.unmodifiable(_localPayments));
      }
      return id;
    } catch (error, stackTrace) {
      state = AsyncError<List<PaymentSummary>>(error, stackTrace);
      return null;
    }
  }

  Future<bool> reject(PaymentSummary payment, String reason) async {
    try {
      if (isLive) {
        await _repository!.reject(paymentId: payment.id, reason: reason);
        state = AsyncData(await _repository!.fetchPayments());
      } else {
        final index = _localPayments.indexWhere(
          (item) => item.id == payment.id,
        );
        _localPayments[index] = PaymentSummary(
          id: payment.id,
          loanId: payment.loanId,
          borrowerName: payment.borrowerName,
          amountCentavos: payment.amountCentavos,
          receivedAt: payment.receivedAt,
          method: payment.method,
          reference: payment.reference,
          status: 'rejected',
          unappliedCentavos: payment.unappliedCentavos,
        );
        state = AsyncData(List.unmodifiable(_localPayments));
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> verify(PaymentSummary payment) async {
    try {
      if (isLive) {
        await _repository!.verify(payment.id);
        state = AsyncData(await _repository!.fetchPayments());
      } else {
        _replaceLocal(payment, 'verified');
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> reverse(PaymentSummary payment, String reason) async {
    try {
      if (isLive) {
        await _repository!.reverse(paymentId: payment.id, reason: reason);
        state = AsyncData(await _repository!.fetchPayments());
      } else {
        _replaceLocal(payment, 'reversed');
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---- Undo (single level; see UndoController) ----

  /// Undo "record payment": the payment becomes rejected (and, for Cash,
  /// its automatic verification and allocation are removed).
  Future<bool> undoRecord(String paymentId) =>
      _undo(paymentId, () => _repository!.undoRecord(paymentId), 'rejected');

  /// Undo "verify": the payment returns to pending.
  Future<bool> undoVerification(String paymentId) => _undo(
    paymentId,
    () => _repository!.undoVerification(paymentId),
    'pending',
  );

  Future<bool> _undo(
    String paymentId,
    Future<void> Function() live,
    String localStatus,
  ) async {
    try {
      if (isLive) {
        await live();
        state = AsyncData(await _repository!.fetchPayments());
        return true;
      }
      await _initialBuild();
      final payment = _localPayments
          .where((p) => p.id == paymentId)
          .firstOrNull;
      if (payment == null) return false;
      _replaceLocal(payment, localStatus);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _replaceLocal(PaymentSummary payment, String status) {
    final index = _localPayments.indexWhere((item) => item.id == payment.id);
    _localPayments[index] = PaymentSummary(
      id: payment.id,
      loanId: payment.loanId,
      borrowerName: payment.borrowerName,
      amountCentavos: payment.amountCentavos,
      receivedAt: payment.receivedAt,
      method: payment.method,
      reference: payment.reference,
      status: status,
      unappliedCentavos: status == 'verified' ? payment.unappliedCentavos : 0,
    );
    state = AsyncData(List.unmodifiable(_localPayments));
  }
}
