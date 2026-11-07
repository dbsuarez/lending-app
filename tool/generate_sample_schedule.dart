import 'dart:io';
import 'package:lending_manager/domain/models/models.dart';
import 'package:lending_manager/domain/services/loan_calculator.dart';
import 'package:lending_manager/features/documents/loan_schedule_pdf.dart';

Future<void> main() async {
  final quote = const LoanCalculator().calculate(
    principalCentavos: 2000000,
    monthlyRateBasisPoints: 600,
    termMonths: 5,
    firstDueDate: DateTime(2026, 11, 15),
    paydayPattern: const [15, 30],
  );
  final detail = LoanDetail(
    summary: LoanSummary(
      id: '6f28a011-3a90-4d24-8888-123456789abc',
      organizationId: '00000000-0000-4000-8000-000000000001',
      borrowerId: '11111111-1111-4111-8111-111111111111',
      borrowerName: 'Origino, Maricar',
      principalCentavos: quote.principalCentavos,
      totalCentavos: quote.totalCentavos,
      monthlyRateBasisPoints: quote.monthlyRateBasisPoints,
      termMonths: quote.termMonths,
      status: 'active',
      createdAt: DateTime(2026, 11, 6),
    ),
    installments: quote.installments,
  );
  final bytes = await LoanSchedulePdf.build(
    detail,
    generatedOn: DateTime(2026, 11, 7),
  );
  final output = File('output/pdf/maricar_origino_loan_schedule_sample.pdf');
  await output.parent.create(recursive: true);
  await output.writeAsBytes(bytes, flush: true);
}
