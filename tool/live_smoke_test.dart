import 'dart:io';
import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';
import 'package:lending_manager/domain/services/loan_calculator.dart';

Future<void> main() async {
  final url = Platform.environment['SMOKE_SUPABASE_URL']!;
  final key = Platform.environment['SMOKE_SUPABASE_KEY']!;
  final email = Platform.environment['SMOKE_EMAIL']!;
  final password = Platform.environment['SMOKE_PASSWORD']!;
  final client = SupabaseClient(url, key);
  await client.auth.signInWithPassword(email: email, password: password);
  String? borrowerId;
  String? loanId;
  try {
    final membership = await client
        .from('organization_members')
        .select('organization_id')
        .eq('user_id', client.auth.currentUser!.id)
        .eq('status', 'active')
        .limit(1)
        .single();
    final organizationId = membership['organization_id'] as String;
    final operationId = const Uuid().v4();
    borrowerId =
        await client.rpc(
              'save_borrower',
              params: {
                'p_id': null,
                'p_first_name': 'Automated',
                'p_last_name': 'Smoke ${operationId.substring(0, 8)}',
                'p_phone':
                    '0999${DateTime.now().microsecondsSinceEpoch.toString().substring(5, 12)}',
                'p_email': null,
                'p_address':
                    'Automated production smoke test - safe to archive',
              },
            )
            as String;

    final now = DateTime.now();
    final firstDue = _nextPayday(now, const [15, 30]);
    final quote = const LoanCalculator().calculate(
      principalCentavos: 10000,
      monthlyRateBasisPoints: 0,
      termMonths: 1,
      firstDueDate: firstDue,
      paydayPattern: const [15, 30],
    );
    loanId =
        await client.rpc(
              'create_loan_draft',
              params: {
                'p_organization_id': organizationId,
                'p_borrower_id': borrowerId,
                'p_principal_centavos': quote.principalCentavos,
                'p_monthly_rate_basis_points': quote.monthlyRateBasisPoints,
                'p_term_months': quote.termMonths,
                'p_first_due_date': _date(firstDue),
                'p_payday_pattern': [15, 30],
                'p_installments': [
                  for (final installment in quote.installments)
                    {
                      'sequence': installment.sequence,
                      'due_date': _date(installment.dueDate),
                      'principal_centavos': installment.principalCentavos,
                      'interest_centavos': installment.interestCentavos,
                      'scheduled_centavos': installment.amountCentavos,
                    },
                ],
                'p_client_operation_id': const Uuid().v4(),
              },
            )
            as String;
    await client.rpc(
      'cancel_loan_draft',
      params: {
        'p_loan_id': loanId,
        'p_reason': 'Automated production smoke test completed',
      },
    );
    await client.rpc(
      'set_borrower_archived',
      params: {'p_borrower_id': borrowerId, 'p_archived': true},
    );
    final loan = await client
        .from('loans')
        .select('status')
        .eq('id', loanId)
        .single();
    final borrower = await client
        .from('borrowers')
        .select('archived_at')
        .eq('id', borrowerId)
        .single();
    if (loan['status'] != 'cancelled' || borrower['archived_at'] == null) {
      throw StateError('Smoke-test cleanup state was not confirmed.');
    }
    stdout.writeln(
      'Live borrower write, draft write, cancellation, and archive verified.',
    );
  } finally {
    if (loanId == null && borrowerId != null) {
      await client.rpc(
        'set_borrower_archived',
        params: {'p_borrower_id': borrowerId, 'p_archived': true},
      );
    }
    await client.auth.signOut();
  }
}

DateTime _nextPayday(DateTime from, List<int> days) {
  for (var offset = 0; offset < 62; offset++) {
    final candidate = DateTime(from.year, from.month, from.day + offset);
    if (candidate.isAfter(from) && days.contains(candidate.day)) {
      return candidate;
    }
  }
  throw StateError('No payday found.');
}

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
