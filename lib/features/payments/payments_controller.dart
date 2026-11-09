import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../app/data_refresh.dart';
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

  /// After a change: reload this list, then everything derived from it
  /// (loan status, Ongoing tags, Collections, Dashboard).
  Future<void> _reloadAll() async {
    state = AsyncData(await _repository!.fetchPayments());
    refreshMoneyViews(ref, payments: false);
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
    String? lateReason,
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
          lateReason: lateReason,
        );
        await _reloadAll();
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
            lateReason: (lateReason?.trim().isEmpty ?? true)
                ? null
                : lateReason!.trim(),
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
        await _reloadAll();
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
          lateReason: payment.lateReason,
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
        await _reloadAll();
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
        await _reloadAll();
      } else {
        _replaceLocal(payment, 'reversed');
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Why the last [correctDetails] failed, in words the user can act on.
  String? lastCorrectionError;

  /// Corrects when a payment was received, its method and reference.
  /// Returns the correction id (for undo), or null on failure (see
  /// [lastCorrectionError]).
  Future<String?> correctDetails(
    PaymentSummary payment, {
    required DateTime receivedAt,
    required String method,
    required String reference,
    required String reason,
  }) async {
    lastCorrectionError = null;
    try {
      if (isLive) {
        _repository ??= SupabasePaymentsRepository(Supabase.instance.client);
        final id = await _repository!.correctDetails(
          paymentId: payment.id,
          receivedAt: receivedAt,
          method: method,
          reference: reference,
          reason: reason,
        );
        await _reloadAll();
        return id;
      }
      await _initialBuild();
      final index = _localPayments.indexWhere((p) => p.id == payment.id);
      if (index < 0) return null;
      final old = _localPayments[index];
      _localPayments[index] = _copy(
        old,
        receivedAt: receivedAt,
        method: method,
        reference: reference,
      );
      _localCorrections[payment.id] = old;
      state = AsyncData(List.unmodifiable(_localPayments));
      return 'local-${payment.id}';
    } on PostgrestException catch (error) {
      lastCorrectionError = error.message.contains('early payoff')
          ? 'this is the early payoff payment. Open the loan, choose '
                'Undo Early Payoff, then record the payoff again with the '
                'right date.'
          : error.message;
      return null;
    } catch (error) {
      lastCorrectionError = '$error';
      return null;
    }
  }

  /// Sets or clears why [payment] came after its due date.
  Future<bool> setLateReason(PaymentSummary payment, String reason) async {
    try {
      if (isLive) {
        _repository ??= SupabasePaymentsRepository(Supabase.instance.client);
        await _repository!.setLateReason(payment.id, reason);
        await _reloadAll();
        return true;
      }
      await _initialBuild();
      final index = _localPayments.indexWhere((p) => p.id == payment.id);
      if (index < 0) return false;
      _localPayments[index] = _copy(
        _localPayments[index],
        receivedAt: _localPayments[index].receivedAt,
        method: _localPayments[index].method,
        reference: _localPayments[index].reference,
        lateReason: reason.trim().isEmpty ? null : reason.trim(),
      );
      state = AsyncData(List.unmodifiable(_localPayments));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Undo for [correctDetails].
  Future<bool> undoCorrection(String correctionId) async {
    try {
      if (isLive) {
        await _repository!.undoCorrection(correctionId);
        await _reloadAll();
        return true;
      }
      final paymentId = correctionId.replaceFirst('local-', '');
      final previous = _localCorrections.remove(paymentId);
      final index = _localPayments.indexWhere((p) => p.id == paymentId);
      if (previous == null || index < 0) return false;
      _localPayments[index] = _copy(
        _localPayments[index],
        receivedAt: previous.receivedAt,
        method: previous.method,
        reference: previous.reference,
      );
      state = AsyncData(List.unmodifiable(_localPayments));
      return true;
    } catch (_) {
      return false;
    }
  }

  final Map<String, PaymentSummary> _localCorrections = {};

  static PaymentSummary _copy(
    PaymentSummary p, {
    required DateTime receivedAt,
    required String method,
    required String reference,
    Object? lateReason = _keep,
  }) => PaymentSummary(
    id: p.id,
    loanId: p.loanId,
    borrowerName: p.borrowerName,
    amountCentavos: p.amountCentavos,
    receivedAt: receivedAt,
    method: method,
    reference: reference,
    status: p.status,
    unappliedCentavos: p.unappliedCentavos,
    lateReason: identical(lateReason, _keep)
        ? p.lateReason
        : lateReason as String?,
  );

  static const _keep = Object();

  /// Verifies several pending payments, oldest received first (so money is
  /// applied in the order it arrived). Returns the ids that were verified;
  /// ones that fail (e.g. no permission) are skipped.
  Future<List<String>> verifyMany(List<PaymentSummary> payments) async {
    final ordered = [...payments]
      ..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
    final verified = <String>[];
    for (final payment in ordered) {
      try {
        if (isLive) {
          await _repository!.verify(payment.id);
        } else {
          await _initialBuild();
          _replaceLocal(payment, 'verified');
        }
        verified.add(payment.id);
      } catch (_) {}
    }
    if (isLive) {
      state = await AsyncValue.guard(() => _repository!.fetchPayments());
      refreshMoneyViews(ref, payments: false);
    }
    return verified;
  }

  /// Undo for [verifyMany]: returns the payments to pending, newest first
  /// (the server only allows undoing the latest verification on a loan).
  Future<bool> undoVerifications(List<String> paymentIds) async {
    var allUndone = true;
    for (final id in paymentIds.reversed) {
      try {
        if (isLive) {
          await _repository!.undoVerification(id);
        } else {
          final payment = _localPayments.where((p) => p.id == id).firstOrNull;
          if (payment == null) {
            allUndone = false;
            continue;
          }
          _replaceLocal(payment, 'pending');
        }
      } catch (_) {
        allUndone = false;
      }
    }
    if (isLive) {
      state = await AsyncValue.guard(() => _repository!.fetchPayments());
      refreshMoneyViews(ref, payments: false);
    }
    return allUndone;
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
        await _reloadAll();
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
      lateReason: payment.lateReason,
    );
    state = AsyncData(List.unmodifiable(_localPayments));
  }
}
