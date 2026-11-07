import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';
import '../../core/config/app_config.dart';
import '../../data/repositories/demo_repository.dart';
import '../../data/repositories/supabase_loans_repository.dart';
import '../../domain/models/models.dart';

final loansControllerProvider =
    AsyncNotifierProvider<LoansController, List<LoanSummary>>(
      LoansController.new,
    );

class LoansController extends AsyncNotifier<List<LoanSummary>> {
  SupabaseLoansRepository? _repository;
  final List<LoanSummary> _localLoans = [];
  final Map<String, LoanQuote> _localQuotes = {};
  final Set<String> _demoLinks = {};

  bool get isLive =>
      AppConfig.hasSupabase &&
      Supabase.instance.client.auth.currentUser != null;

  @override
  Future<List<LoanSummary>> build() async {
    if (!isLive) return List.unmodifiable(_localLoans);
    _repository = SupabaseLoansRepository(Supabase.instance.client);
    return _repository!.fetchLoans();
  }

  Future<void> refresh() async {
    if (!isLive) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repository!.fetchLoans());
  }

  /// Demo-mode mutators must wait for the first async build; otherwise a
  /// build that finishes after the mutation overwrites it with the stale
  /// (empty) list it captured. Happens when a screen's first use of this
  /// provider is `ref.read(...notifier)` followed straight by a mutation.
  Future<void> _initialBuild() async {
    try {
      await future;
    } catch (_) {}
  }

  /// Returns the new loan id, or null on failure.
  Future<String?> createDraft({
    required Borrower borrower,
    required LoanQuote quote,
    required DateTime firstDueDate,
    required List<int> paydayPattern,
  }) async {
    // Before AsyncLoading: once loading is set, `future` would not resolve.
    if (!isLive) await _initialBuild();
    state = const AsyncLoading();
    try {
      final operationId = const Uuid().v4();
      String createdId = operationId;
      if (isLive) {
        createdId = await _repository!.createDraft(
          borrowerId: borrower.id,
          quote: quote,
          firstDueDate: firstDueDate,
          paydayPattern: paydayPattern,
          clientOperationId: operationId,
        );
        state = AsyncData(await _repository!.fetchLoans());
      } else {
        _localLoans.insert(
          0,
          LoanSummary(
            id: operationId,
            organizationId: demoOrganizationId,
            borrowerId: borrower.id,
            borrowerName: borrower.displayName,
            principalCentavos: quote.principalCentavos,
            totalCentavos: quote.totalCentavos,
            monthlyRateBasisPoints: quote.monthlyRateBasisPoints,
            termMonths: quote.termMonths,
            status: 'draft',
            createdAt: DateTime.now(),
            isPersonal: false,
          ),
        );
        _localQuotes[operationId] = quote;
        state = AsyncData(List.unmodifiable(_localLoans));
      }
      return createdId;
    } catch (error, stackTrace) {
      state = AsyncError<List<LoanSummary>>(error, stackTrace);
      return null;
    }
  }

  Future<LoanDetail> fetchDetail(String id) async {
    if (isLive) return _repository!.fetchLoan(id);
    final summary = _localLoans.firstWhere((loan) => loan.id == id);
    final quote = _localQuotes[id]!;
    return LoanDetail(summary: summary, installments: quote.installments);
  }

  Future<bool> activate({
    required String loanId,
    required DateTime disbursedOn,
    required String method,
    required String reference,
  }) async {
    try {
      if (isLive) {
        await _repository!.activate(
          loanId: loanId,
          disbursedOn: disbursedOn,
          method: method,
          reference: reference,
          clientOperationId: const Uuid().v4(),
        );
        state = AsyncData(await _repository!.fetchLoans());
      } else {
        await _initialBuild();
        final index = _localLoans.indexWhere((loan) => loan.id == loanId);
        final old = _localLoans[index];
        _localLoans[index] = old.copyWith(
          status: 'active',
          borrowedOn: disbursedOn,
        );
        state = AsyncData(List.unmodifiable(_localLoans));
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// The loan's customer link (existing one reused; created if none).
  Future<CustomerLink?> createShareLink(String loanId) async {
    if (!isLive) {
      final reused = _demoLinks.contains(loanId);
      _demoLinks.add(loanId);
      return (
        id: 'local-demo-$loanId',
        token: 'local-demo-$loanId',
        reused: reused,
      );
    }
    try {
      return await _repository!.createShareLink(loanId: loanId);
    } catch (_) {
      return null;
    }
  }

  Future<List<LoanShareLinkSummary>> fetchShareLinks(String loanId) async {
    if (!isLive) return const [];
    return _repository!.fetchShareLinks(loanId);
  }

  Future<bool> revokeShareLink(String linkId) async {
    if (!isLive) return true;
    try {
      await _repository!.revokeShareLink(linkId);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> cancelDraft({
    required String loanId,
    required String reason,
  }) async {
    try {
      if (isLive) {
        await _repository!.cancelDraft(loanId: loanId, reason: reason);
        state = AsyncData(await _repository!.fetchLoans());
      } else {
        await _initialBuild();
        final index = _localLoans.indexWhere((loan) => loan.id == loanId);
        if (index < 0 || _localLoans[index].status != 'draft') return false;
        final old = _localLoans[index];
        _localLoans[index] = old.copyWith(status: 'cancelled');
        state = AsyncData(List.unmodifiable(_localLoans));
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<PaymentSummary>> fetchLoanPayments(String loanId) async {
    if (!isLive) return const [];
    return _repository!.fetchLoanPayments(loanId);
  }

  Future<bool> setPersonal(String loanId, bool personal) async {
    try {
      if (isLive) {
        await _repository!.setPersonal(loanId: loanId, personal: personal);
        state = AsyncData(await _repository!.fetchLoans());
      } else {
        await _initialBuild();
        final index = _localLoans.indexWhere((loan) => loan.id == loanId);
        if (index < 0) return false;
        final old = _localLoans[index];
        _localLoans[index] = old.copyWith(isPersonal: personal);
        state = AsyncData(List.unmodifiable(_localLoans));
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Returns the amendment id, or null on failure.
  Future<String?> amendInstallmentDueDate({
    required String loanId,
    required int sequence,
    required DateTime newDueDate,
    required String reason,
    required DateTime consentDate,
  }) async {
    if (!isLive) return null;
    try {
      final id = await _repository!.amendInstallmentDueDate(
        loanId: loanId,
        sequence: sequence,
        newDueDate: newDueDate,
        reason: reason,
        consentDate: consentDate,
        clientOperationId: const Uuid().v4(),
      );
      state = AsyncData(await _repository!.fetchLoans());
      return id;
    } catch (_) {
      return null;
    }
  }

  Future<String?> refinance({
    required String sourceLoanId,
    required LoanQuote quote,
    required String reason,
    required DateTime consentDate,
  }) async {
    if (!isLive) return null;
    try {
      final id = await _repository!.refinance(
        sourceLoanId: sourceLoanId,
        quote: quote,
        reason: reason,
        consentDate: consentDate,
        clientOperationId: const Uuid().v4(),
      );
      state = AsyncData(await _repository!.fetchLoans());
      return id;
    } catch (_) {
      return null;
    }
  }

  Future<List<AuditEventSummary>> fetchLoanActivity(String loanId) async {
    if (!isLive) return const [];
    return _repository!.fetchLoanActivity(loanId);
  }

  Future<EarlyPayoffQuote?> earlyPayoffQuote(
    String loanId,
    DateTime date,
  ) async {
    if (!isLive) return null;
    try {
      return await _repository!.earlyPayoffQuote(loanId, date);
    } catch (_) {
      return null;
    }
  }

  /// Returns the settlement payment id, or null on failure.
  Future<String?> recordEarlyPayoff({
    required String loanId,
    required DateTime date,
    required String method,
    required String reference,
  }) async {
    if (!isLive) return null;
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final id = await _repository!.recordEarlyPayoff(
        loanId: loanId,
        date: date,
        method: method,
        reference: reference,
        clientOperationId: const Uuid().v4(),
        deviceId: '${kIsWeb ? 'web' : 'android'}-$userId',
      );
      state = AsyncData(await _repository!.fetchLoans());
      return id;
    } catch (_) {
      return null;
    }
  }

  // ---- Undo (single level; see UndoController) ----

  Future<bool> undoCreateDraft(String loanId) =>
      cancelDraft(loanId: loanId, reason: 'Undone right after creation.');

  Future<bool> undoActivation(String loanId) => _undo(
    live: () => _repository!.undoActivation(loanId),
    local: () {
      final index = _localLoans.indexWhere((loan) => loan.id == loanId);
      if (index < 0 || _localLoans[index].status != 'active') return false;
      _localLoans[index] = _localLoans[index].copyWith(
        status: 'draft',
        clearBorrowedOn: true,
      );
      return true;
    },
  );

  Future<bool> undoDueDateAmendment(String amendmentId) => _undo(
    live: () => _repository!.undoDueDateAmendment(amendmentId),
    local: () => false,
  );

  Future<bool> undoEarlyPayoff(String paymentId) => _undo(
    live: () => _repository!.undoEarlyPayoff(paymentId),
    local: () => false,
  );

  Future<bool> _undo({
    required Future<void> Function() live,
    required bool Function() local,
  }) async {
    try {
      if (isLive) {
        await live();
        state = AsyncData(await _repository!.fetchLoans());
        return true;
      }
      await _initialBuild();
      if (!local()) return false;
      state = AsyncData(List.unmodifiable(_localLoans));
      return true;
    } catch (_) {
      return false;
    }
  }
}
