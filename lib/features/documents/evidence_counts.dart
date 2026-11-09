import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';

/// How many evidence files each loan has (loan id -> count), for the
/// paperclip markers in lists. Refreshed after every upload.
final evidenceCountsProvider = FutureProvider<Map<String, int>>((ref) async {
  if (!AppConfig.hasSupabase) return const {};
  const page = 1000;
  final counts = <String, int>{};
  for (var from = 0; ; from += page) {
    final rows = await Supabase.instance.client
        .from('loan_documents')
        .select('loan_id')
        .order('id')
        .range(from, from + page - 1);
    for (final row in rows) {
      final id = row['loan_id'] as String;
      counts[id] = (counts[id] ?? 0) + 1;
    }
    if (rows.length < page) break;
  }
  return counts;
});

/// A small paperclip with the number of evidence files; nothing when none.
class EvidenceBadge extends ConsumerWidget {
  const EvidenceBadge(this.loanId, {super.key});
  final String loanId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(evidenceCountsProvider).value?[loanId] ?? 0;
    if (count == 0) return const SizedBox.shrink();
    final color = Theme.of(context).colorScheme.primary;
    return Tooltip(
      message: count == 1 ? '1 evidence file' : '$count evidence files',
      child: Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.attach_file, size: 16, color: color),
            Text(
              '$count',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// A loan reference followed by its evidence marker.
class LoanReferenceWithEvidence extends StatelessWidget {
  const LoanReferenceWithEvidence(this.reference, this.loanId, {super.key});
  final String reference, loanId;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [Text(reference), EvidenceBadge(loanId)],
  );
}
