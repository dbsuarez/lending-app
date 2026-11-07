import '../models/models.dart';

class LoanCalculator {
  const LoanCalculator();
  LoanQuote calculate({
    required int principalCentavos,
    required int monthlyRateBasisPoints,
    required int termMonths,
    required DateTime firstDueDate,
    required List<int> paydayPattern,
  }) {
    if (principalCentavos <= 0) {
      throw ArgumentError.value(
        principalCentavos,
        'principalCentavos',
        'Must be positive',
      );
    }
    if (monthlyRateBasisPoints < 0) {
      throw ArgumentError.value(
        monthlyRateBasisPoints,
        'monthlyRateBasisPoints',
        'Cannot be negative',
      );
    }
    if (termMonths <= 0) {
      throw ArgumentError.value(termMonths, 'termMonths', 'Must be positive');
    }
    if (paydayPattern.isEmpty || paydayPattern.any((d) => d < 1 || d > 31)) {
      throw ArgumentError.value(
        paydayPattern,
        'paydayPattern',
        'Days must be 1 to 31',
      );
    }
    final interest =
        (principalCentavos * monthlyRateBasisPoints * termMonths / 10000)
            .round();
    final total = principalCentavos + interest,
        count = termMonths * paydayPattern.length,
        baseAmount = total ~/ count,
        basePrincipal = principalCentavos ~/ count;
    final dates = _dates(firstDueDate, paydayPattern, count);
    var usedAmount = 0, usedPrincipal = 0;
    final result = <Installment>[];
    for (var i = 0; i < count; i++) {
      final amount = i == count - 1 ? total - usedAmount : baseAmount;
      final principal = i == count - 1
          ? principalCentavos - usedPrincipal
          : basePrincipal;
      result.add(
        Installment(
          sequence: i + 1,
          dueDate: dates[i],
          amountCentavos: amount,
          principalCentavos: principal,
          interestCentavos: amount - principal,
        ),
      );
      usedAmount += amount;
      usedPrincipal += principal;
    }
    return LoanQuote(
      principalCentavos: principalCentavos,
      interestCentavos: interest,
      totalCentavos: total,
      monthlyRateBasisPoints: monthlyRateBasisPoints,
      termMonths: termMonths,
      installments: result,
    );
  }

  List<DateTime> _dates(DateTime first, List<int> pattern, int count) {
    final days = [...pattern]..sort();
    final dates = <DateTime>[];
    var year = first.year, month = first.month;
    while (dates.length < count) {
      for (final day in days) {
        final last = DateTime(year, month + 1, 0).day,
            value = DateTime(year, month, day > last ? last : day);
        if (!value.isBefore(DateTime(first.year, first.month, first.day))) {
          dates.add(value);
        }
        if (dates.length == count) {
          break;
        }
      }
      if (++month == 13) {
        month = 1;
        year++;
      }
    }
    return dates;
  }
}
