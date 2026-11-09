import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import '../../core/preferences/filter_defaults.dart';
import '../../core/undo/undo_controller.dart';
import '../../core/formatting.dart';
import '../../domain/models/models.dart';
import '../loans/loans_controller.dart';
import 'collections_controller.dart';

final _queueFilterProvider = NotifierProvider<_QueueFilter, String>(
  _QueueFilter.new,
);

class _QueueFilter extends Notifier<String> {
  static const listKey = 'collections.queue';

  // Upcoming unless the user long-pressed another option as the default.
  @override
  String build() => ref.read(filterDefaultsProvider).get(listKey, 'upcoming');

  void select(String value) => state = value;
}

class CollectionsScreen extends ConsumerWidget {
  const CollectionsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loans = ref.watch(loansControllerProvider);
    final activities = ref.watch(collectionsControllerProvider);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final heading = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Collections',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Due dates, calls and visits, and promises to pay.',
                  ),
                ],
              );
              final actions = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _showTemplates(context),
                    icon: const Icon(Icons.mark_email_read_outlined),
                    label: const Text('Reminder Templates…'),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Refresh activity',
                    onPressed: () => ref
                        .read(collectionsControllerProvider.notifier)
                        .refresh(),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              );
              // Stack on narrow screens so the title is never squeezed.
              return constraints.maxWidth < 600
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [heading, const SizedBox(height: 10), actions],
                    )
                  : Row(
                      children: [
                        Expanded(child: heading),
                        actions,
                      ],
                    );
            },
          ),
          const SizedBox(height: 16),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final queue = _Queue(loans);
                final history = _History(activities);
                if (constraints.maxWidth < 900) {
                  return DefaultTabController(
                    length: 2,
                    child: Column(
                      children: [
                        const TabBar(
                          tabs: [
                            Tab(text: 'Due Queue'),
                            Tab(text: 'Activity'),
                          ],
                        ),
                        Expanded(child: TabBarView(children: [queue, history])),
                      ],
                    ),
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 3, child: queue),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: history),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showTemplates(BuildContext context) async {
    const templates = <String, String>{
      'Upcoming due date':
          'Hello, this is a friendly reminder that your scheduled loan payment is coming up. Please contact us if you need to confirm the amount or payment options. Thank you.',
      'Past due follow-up':
          'Hello, our records show a scheduled loan payment may be past its contractual due date. If you have already paid, please send the payment reference. Otherwise, please contact us so we can discuss your account respectfully.',
      'Promise follow-up':
          'Hello, this is a reminder about the payment date we discussed. Please let us know if your circumstances changed so we can update our records. Thank you.',
    };
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Respectful reminder templates'),
        content: SizedBox(
          width: 650,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: templates.length,
            separatorBuilder: (_, _) => const Divider(),
            itemBuilder: (_, index) {
              final item = templates.entries.elementAt(index);
              return ListTile(
                title: Text(item.key),
                subtitle: Text(item.value),
                trailing: IconButton(
                  tooltip: 'Copy template',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: item.value));
                    if (dialogContext.mounted) {
                      undoOf(dialogContext).notify('Template copied.');
                    }
                  },
                  icon: const Icon(Icons.copy),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _Queue extends ConsumerWidget {
  const _Queue(this.loans);
  final AsyncValue<List<LoanSummary>> loans;
  @override
  Widget build(BuildContext context, WidgetRef ref) => loans.when(
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (_, _) =>
        const Center(child: Text('Collections could not be loaded.')),
    data: (items) {
      final active = items
          .where((item) => item.status == 'active' && !item.isPersonal)
          .toList();
      if (active.isEmpty) return const Center(child: Text('No active loans.'));
      return FutureBuilder<List<LoanDetail>>(
        future: Future.wait([
          for (final loan in active)
            ref.read(loansControllerProvider.notifier).fetchDetail(loan.id),
        ]),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = [
            for (final detail in snapshot.data!)
              ...detail.installments.map((item) => (detail.summary, item)),
          ]..sort((a, b) => a.$2.dueDate.compareTo(b.$2.dueDate));
          final filter = ref.watch(_queueFilterProvider);
          final visibleRows = rows.where((row) {
            final overdue = row.$2.dueDate.isBefore(DateTime.now());
            return filter == 'all' ||
                (filter == 'overdue' && overdue) ||
                (filter == 'upcoming' && !overdue);
          }).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  children: [
                    // Long-press anywhere on a segment to make it the
                    // default. The detector wraps the whole control (the
                    // segments are equal width) so a finger beside the label
                    // still counts, which matters on phones.
                    Builder(
                      builder: (segmentsContext) {
                        const options = [
                          ('all', 'All'),
                          ('upcoming', 'Upcoming'),
                          ('overdue', 'Overdue'),
                        ];
                        final saved = ref
                            .read(filterDefaultsProvider)
                            .get(_QueueFilter.listKey, 'upcoming');
                        return GestureDetector(
                          onLongPressStart: (details) async {
                            final box =
                                segmentsContext.findRenderObject()
                                    as RenderBox?;
                            if (box == null || !box.hasSize) return;
                            final index =
                                (details.localPosition.dx /
                                        box.size.width *
                                        options.length)
                                    .floor()
                                    .clamp(0, options.length - 1);
                            final (value, label) = options[index];
                            HapticFeedback.mediumImpact();
                            await ref
                                .read(filterDefaultsProvider)
                                .set(_QueueFilter.listKey, value);
                            ref
                                .read(_queueFilterProvider.notifier)
                                .select(value);
                            if (context.mounted) {
                              undoOf(context).notify(
                                '"$label" is now the default for Collections.',
                              );
                            }
                          },
                          child: SegmentedButton<String>(
                            segments: [
                              for (final (value, label) in options)
                                ButtonSegment(
                                  value: value,
                                  label: Text(
                                    saved == value ? '$label •' : label,
                                  ),
                                ),
                            ],
                            selected: {filter},
                            onSelectionChanged: (value) => ref
                                .read(_queueFilterProvider.notifier)
                                .select(value.first),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Long-press an option to make it the default (•).',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: visibleRows.isEmpty
                    ? const Center(
                        child: Text('No installments match this filter.'),
                      )
                    : ListView.separated(
                        itemCount: visibleRows.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 7),
                        itemBuilder: (_, index) {
                          final row = visibleRows[index];
                          final overdue = row.$2.dueDate.isBefore(
                            DateTime.now(),
                          );
                          return Card(
                            child: ListTile(
                              leading: Icon(
                                overdue
                                    ? Icons.warning_amber
                                    : Icons.event_outlined,
                              ),
                              title: Text(row.$1.borrowerName),
                              subtitle: Text(
                                '${formatPhilippineDate(row.$2.dueDate)} · ${overdue ? 'Past due date' : 'Upcoming'}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    formatPeso(row.$2.amountCentavos),
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    tooltip: 'Log contact or promise',
                                    onPressed: () =>
                                        _record(context, ref, row.$1),
                                    icon: const Icon(
                                      Icons.add_comment_outlined,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      );
    },
  );

  Future<void> _record(
    BuildContext context,
    WidgetRef ref,
    LoanSummary loan,
  ) async {
    final values = await showDialog<_ActivityValues>(
      context: context,
      builder: (_) => _ActivityDialog(loan),
    );
    if (values == null) return;
    final collections = ref.read(collectionsControllerProvider.notifier);
    final saved = await collections.record(
      loan: loan,
      type: values.type,
      outcome: values.outcome,
      notes: values.notes,
      promisedOn: values.promisedOn,
      promisedAmountCentavos: values.promisedAmountCentavos,
    );
    final queued = collections.lastRecordQueued;
    final activityId = collections.lastRecordedId;
    if (!context.mounted) return;
    final undo = undoOf(context);
    if (saved && !queued && activityId != null) {
      undo.offer(
        'Collection activity recorded.',
        () => collections.undoRecord(activityId),
      );
    } else {
      undo.record(
        saved
            ? 'Saved offline. It will sync automatically when the connection returns.'
            : 'Activity could not be recorded.',
      );
    }
  }
}

class _History extends StatelessWidget {
  const _History(this.activities);
  final AsyncValue<List<CollectionActivity>> activities;
  @override
  Widget build(BuildContext context) => activities.when(
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (_, _) =>
        const Center(child: Text('Activity history could not be loaded.')),
    data: (items) => items.isEmpty
        ? const Center(child: Text('No contact attempts or promises yet.'))
        : Card(
            child: ListView.separated(
              padding: const EdgeInsets.all(8),
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final item = items[index];
                final promise = item.promisedOn == null
                    ? ''
                    : '\nPromise: ${formatPeso(item.promisedAmountCentavos!)} on ${formatPhilippineDate(item.promisedOn!)}';
                return ListTile(
                  leading: Icon(switch (item.type) {
                    'call' => Icons.call_outlined,
                    'sms' => Icons.sms_outlined,
                    'visit' => Icons.home_work_outlined,
                    'email' => Icons.email_outlined,
                    _ => Icons.event_available_outlined,
                  }),
                  title: Text('${item.borrowerName} · ${item.outcome}'),
                  subtitle: Text(
                    '${formatPhilippineDateTime(item.contactedAt)}$promise${item.notes.isEmpty ? '' : '\n${item.notes}'}',
                  ),
                  isThreeLine: promise.isNotEmpty || item.notes.isNotEmpty,
                );
              },
            ),
          ),
  );
}

class _ActivityDialog extends StatefulWidget {
  const _ActivityDialog(this.loan);
  final LoanSummary loan;
  @override
  State<_ActivityDialog> createState() => _ActivityDialogState();
}

class _ActivityDialogState extends State<_ActivityDialog> {
  String type = 'call';
  final outcome = TextEditingController();
  final notes = TextEditingController();
  final amount = TextEditingController();
  DateTime promisedOn = DateTime.now().add(const Duration(days: 7));
  @override
  void dispose() {
    outcome.dispose();
    notes.dispose();
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Collection activity · ${widget.loan.borrowerName}'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: type,
              decoration: const InputDecoration(labelText: 'Activity type'),
              items: const [
                DropdownMenuItem(value: 'call', child: Text('Phone call')),
                DropdownMenuItem(value: 'sms', child: Text('SMS / message')),
                DropdownMenuItem(value: 'visit', child: Text('Visit')),
                DropdownMenuItem(value: 'email', child: Text('Email')),
                DropdownMenuItem(
                  value: 'promise',
                  child: Text('Promise to pay'),
                ),
              ],
              onChanged: (value) => setState(() => type = value!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: outcome,
              decoration: const InputDecoration(
                labelText: 'Outcome',
                hintText: 'Reached, no response, follow-up needed…',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notes,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            if (type == 'promise') ...[
              const SizedBox(height: 12),
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Promised amount'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Promised date'),
                subtitle: Text(formatPhilippineDate(promisedOn)),
                trailing: const Icon(Icons.calendar_month_outlined),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 730)),
                    initialDate: promisedOn,
                  );
                  if (picked != null) setState(() => promisedOn = picked);
                },
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Save Activity')),
    ],
  );

  void _submit() {
    final cents = ((double.tryParse(amount.text.trim()) ?? 0) * 100).round();
    if (outcome.text.trim().length < 2 || (type == 'promise' && cents <= 0)) {
      return;
    }
    Navigator.pop(
      context,
      _ActivityValues(
        type,
        outcome.text.trim(),
        notes.text.trim(),
        type == 'promise' ? promisedOn : null,
        type == 'promise' ? cents : null,
      ),
    );
  }
}

class _ActivityValues {
  const _ActivityValues(
    this.type,
    this.outcome,
    this.notes,
    this.promisedOn,
    this.promisedAmountCentavos,
  );
  final String type, outcome, notes;
  final DateTime? promisedOn;
  final int? promisedAmountCentavos;
}
