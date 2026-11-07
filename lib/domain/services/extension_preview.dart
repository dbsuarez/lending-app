import '../models/models.dart';

/// What a borrower would owe if an overdue loan were extended to [asOf].
/// Read-only: nothing here is saved.
class ExtensionPreview {
  const ExtensionPreview({
    required this.asOf,
    required this.finalDueDate,
    required this.unpaidPrincipalCentavos,
    required this.unpaidInterestCentavos,
    required this.extensionMonths,
    required this.interestBaseCentavos,
    required this.extensionInterestCentavos,
  });

  /// Date the amount is computed for.
  final DateTime asOf;

  /// Last due date of the original schedule; extra interest starts here.
  final DateTime finalDueDate;

  /// Still unpaid from the original schedule (verified payments only).
  final int unpaidPrincipalCentavos, unpaidInterestCentavos;

  /// Months past [finalDueDate] that extra interest is charged for.
  final double extensionMonths;

  /// The amount the monthly rate is applied to for extra interest.
  final int interestBaseCentavos;
  final int extensionInterestCentavos;

  int get unpaidScheduleCentavos =>
      unpaidPrincipalCentavos + unpaidInterestCentavos;
  int get totalCentavos => unpaidScheduleCentavos + extensionInterestCentavos;
}

/// Which amount extra interest is charged on.
enum ExtensionInterestBase {
  /// Only the principal still unpaid (fairer when part was paid).
  unpaidPrincipal,

  /// The full original principal, like the loan's own flat interest.
  originalPrincipal,
}

class ExtensionCalculator {
  const ExtensionCalculator();

  /// Average month length, for pro-rating part of a month by days.
  static const daysPerMonth = 365.25 / 12;

  /// Payday days of the month used by [loan], read from its schedule.
  /// Month-end dates that were clamped (e.g. 30 -> Feb 28) count as one day.
  List<int> paydayPattern(LoanDetail loan) {
    final days = <int>{};
    int? monthEnd;
    for (final item in loan.installments) {
      final d = item.dueDate;
      final last = DateTime(d.year, d.month + 1, 0).day;
      if (d.day == last && d.day < 31) {
        monthEnd = monthEnd == null || d.day > monthEnd ? d.day : monthEnd;
      } else {
        days.add(d.day);
      }
    }
    if (monthEnd != null && !days.any((day) => day >= monthEnd!)) {
      days.add(monthEnd < 30 ? 30 : monthEnd);
    }
    return days.isEmpty ? const [15, 30] : (days.toList()..sort());
  }

  /// The first payday cutoff on or after [date] for [pattern].
  DateTime cutoffOnOrAfter(DateTime date, List<int> pattern) {
    final day = DateTime(date.year, date.month, date.day);
    for (var offset = 0; offset < 3; offset++) {
      final year = day.year, month = day.month + offset;
      final last = DateTime(year, month + 1, 0).day;
      for (final p in [...pattern]..sort()) {
        final candidate = DateTime(year, month, p > last ? last : p);
        if (!candidate.isBefore(day)) return candidate;
      }
    }
    return day;
  }

  /// Full payday periods from [from] (exclusive) to [to] (inclusive),
  /// converted to months (two periods = one month on a 15th/30th pattern).
  double cutoffMonths(DateTime from, DateTime to, List<int> pattern) {
    var periods = 0;
    var cursor = from;
    while (true) {
      final next = cutoffOnOrAfter(
        cursor.add(const Duration(days: 1)),
        pattern,
      );
      if (next.isAfter(to)) break;
      periods++;
      cursor = next;
    }
    return periods / pattern.length;
  }

  /// Days from [from] to [to] as a fraction of a month.
  double proratedMonths(DateTime from, DateTime to) {
    final days = DateTime(
      to.year,
      to.month,
      to.day,
    ).difference(DateTime(from.year, from.month, from.day)).inDays;
    return days <= 0 ? 0 : days / daysPerMonth;
  }

  ExtensionPreview preview(
    LoanDetail loan, {
    required DateTime asOf,
    required double extensionMonths,
    ExtensionInterestBase base = ExtensionInterestBase.unpaidPrincipal,
  }) {
    var unpaidPrincipal = 0, unpaidInterest = 0;
    DateTime? finalDue;
    for (final item in loan.installments) {
      // Payments are applied interest first, then principal.
      final paidInterest = item.paidCentavos.clamp(0, item.interestCentavos);
      final paidPrincipal = (item.paidCentavos - paidInterest).clamp(
        0,
        item.principalCentavos,
      );
      unpaidInterest += item.interestCentavos - paidInterest;
      unpaidPrincipal += item.principalCentavos - paidPrincipal;
      if (finalDue == null || item.dueDate.isAfter(finalDue)) {
        finalDue = item.dueDate;
      }
    }
    final months = extensionMonths < 0 ? 0.0 : extensionMonths;
    final interestBase = base == ExtensionInterestBase.unpaidPrincipal
        ? unpaidPrincipal
        : loan.summary.principalCentavos;
    final extraInterest =
        (interestBase * loan.summary.monthlyRateBasisPoints * months / 10000)
            .round();
    return ExtensionPreview(
      asOf: asOf,
      finalDueDate: finalDue ?? asOf,
      unpaidPrincipalCentavos: unpaidPrincipal,
      unpaidInterestCentavos: unpaidInterest,
      extensionMonths: months,
      interestBaseCentavos: interestBase,
      extensionInterestCentavos: extraInterest,
    );
  }

  /// Preview as of [date], pro-rating any part month by days.
  ExtensionPreview asOfDate(
    LoanDetail loan,
    DateTime date, {
    ExtensionInterestBase base = ExtensionInterestBase.unpaidPrincipal,
  }) {
    final finalDue = _finalDue(loan);
    return preview(
      loan,
      asOf: date,
      extensionMonths: finalDue == null ? 0 : proratedMonths(finalDue, date),
      base: base,
    );
  }

  /// Preview as of the payday cutoff on or after [date], counting whole
  /// payday periods past the final due date.
  ExtensionPreview asOfCutoff(
    LoanDetail loan,
    DateTime date, {
    ExtensionInterestBase base = ExtensionInterestBase.unpaidPrincipal,
  }) {
    final pattern = paydayPattern(loan);
    final cutoff = cutoffOnOrAfter(date, pattern);
    final finalDue = _finalDue(loan);
    return preview(
      loan,
      asOf: cutoff,
      extensionMonths: finalDue == null
          ? 0
          : cutoffMonths(finalDue, cutoff, pattern),
      base: base,
    );
  }

  DateTime? _finalDue(LoanDetail loan) => loan.installments.isEmpty
      ? null
      : loan.installments
            .map((item) => item.dueDate)
            .reduce((a, b) => a.isAfter(b) ? a : b);
}
