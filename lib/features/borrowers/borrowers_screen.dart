import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/table_columns.dart';
import '../../core/preferences/filter_defaults.dart';
import '../../core/undo/undo_controller.dart';
import '../../domain/models/models.dart';
import '../../core/widgets/clearable_search_field.dart';
import '../../core/widgets/responsive_card_list.dart';
import '../loans/loans_controller.dart';
import 'borrowers_controller.dart';

class BorrowersScreen extends ConsumerStatefulWidget {
  const BorrowersScreen({super.key});
  @override
  ConsumerState<BorrowersScreen> createState() => _BorrowersScreenState();
}

class _BorrowersScreenState extends ConsumerState<BorrowersScreen> {
  String query = '';
  late String loanFilter = ref
      .read(filterDefaultsProvider)
      .get('borrowers.loan', 'all');
  int sortColumnIndex = 0;
  bool sortAscending = true;
  @override
  Widget build(BuildContext context) {
    final borrowers = ref.watch(borrowersControllerProvider);
    final activeBorrowerIds =
        (ref.watch(loansControllerProvider).value ?? const <LoanSummary>[])
            .where((loan) => loan.status == 'active' && !loan.isPersonal)
            .map((loan) => loan.borrowerId)
            .toSet();
    final controller = ref.read(borrowersControllerProvider.notifier);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 12,
            children: [
              Text(
                'Borrowers',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (controller.isLive)
                    OutlinedButton.icon(
                      onPressed: borrowers.isLoading ? null : _showArchived,
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: const Text('Archived'),
                    ),
                  const SizedBox(width: 8),
                  if (controller.isLive)
                    IconButton(
                      tooltip: 'Refresh borrowers',
                      onPressed: borrowers.isLoading
                          ? null
                          : controller.refresh,
                      icon: const Icon(Icons.refresh),
                    ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: borrowers.isLoading
                        ? null
                        : () => _edit(context),
                    icon: const Icon(Icons.person_add_outlined),
                    label: const Text('Add borrower'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: constraints.maxWidth < 440
                      ? constraints.maxWidth
                      : constraints.maxWidth - 202,
                  child: ClearableSearchField(
                    onChanged: (v) => setState(() => query = v),
                    hintText: 'Search by name or phone',
                  ),
                ),
                SizedBox(
                  width: 190,
                  child: DefaultableFilterDropdown(
                    listKey: 'borrowers.loan',
                    listName: 'Borrowers',
                    label: 'Loan status',
                    value: loanFilter,
                    fallback: 'all',
                    options: const [
                      ('all', 'All borrowers'),
                      ('active', 'Has ongoing loan'),
                      ('none', 'No active loan'),
                    ],
                    onChanged: (value) => setState(() => loanFilter = value),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: borrowers.when(
              skipLoadingOnReload: true,
              data: (items) => _buildList(items, activeBorrowerIds),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => _BorrowersError(onRetry: controller.refresh),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(
    List<Borrower> allBorrowers,
    Set<String> activeBorrowerIds,
  ) {
    final normalizedQuery = query.trim().toLowerCase();
    final borrowers = allBorrowers.where((borrower) {
      final hasActive = activeBorrowerIds.contains(borrower.id);
      final matchesLoan =
          loanFilter == 'all' ||
          (loanFilter == 'active' && hasActive) ||
          (loanFilter == 'none' && !hasActive);
      return matchesLoan &&
          (normalizedQuery.isEmpty ||
              borrower.displayName.toLowerCase().contains(normalizedQuery) ||
              borrower.phone.toLowerCase().contains(normalizedQuery));
    }).toList();
    borrowers.sort((left, right) {
      final comparison = switch (sortColumnIndex) {
        0 => left.displayName.toLowerCase().compareTo(
          right.displayName.toLowerCase(),
        ),
        1 => left.phone.toLowerCase().compareTo(right.phone.toLowerCase()),
        2 => left.email.toLowerCase().compareTo(right.email.toLowerCase()),
        3 => left.address.toLowerCase().compareTo(right.address.toLowerCase()),
        _ => 0,
      };
      return sortAscending ? comparison : -comparison;
    });

    if (borrowers.isEmpty) {
      return Center(
        child: Text(
          allBorrowers.isEmpty
              ? 'No borrower records yet.'
              : 'No borrowers match your search.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 760
          ? RefreshIndicator(
              onRefresh: ref.read(borrowersControllerProvider.notifier).refresh,
              child: ResponsiveCardList(
                physics: const AlwaysScrollableScrollPhysics(),
                spacing: 10,
                itemCount: borrowers.length,
                itemBuilder: (_, i) => _BorrowerCard(
                  borrowers[i],
                  hasActiveLoan: activeBorrowerIds.contains(borrowers[i].id),
                  onOpen: () => context.go('/borrowers/${borrowers[i].id}'),
                  onEdit: () => _edit(context, borrowers[i]),
                  onArchive: () => _archive(borrowers[i]),
                ),
              ),
            )
          : ColumnToggle(
              tableId: 'borrowers',
              labels: const ['Name', 'Phone', 'Email', 'Address', 'Actions'],
              builder: (view) => Card(
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    // Rows open on tap; there is nothing to select, so no checkboxes.
                    showCheckboxColumn: false,
                    sortColumnIndex: view.sortIndex(sortColumnIndex),
                    sortAscending: sortAscending,
                    columns: view.columns([
                      DataColumn(label: const Text('Name'), onSort: _sort),
                      DataColumn(label: const Text('Phone'), onSort: _sort),
                      DataColumn(label: const Text('Email'), onSort: _sort),
                      DataColumn(label: const Text('Address'), onSort: _sort),
                      const DataColumn(
                        label: SizedBox(width: 220, child: Text('Actions')),
                      ),
                    ]),
                    rows: [
                      for (final borrower in borrowers)
                        DataRow(
                          onSelectChanged: (_) =>
                              context.go('/borrowers/${borrower.id}'),
                          cells: view.cells([
                            DataCell(
                              Row(
                                children: [
                                  Flexible(child: Text(borrower.displayName)),
                                  if (activeBorrowerIds.contains(
                                    borrower.id,
                                  )) ...[
                                    const SizedBox(width: 8),
                                    const _OngoingBadge(),
                                  ],
                                ],
                              ),
                            ),
                            DataCell(Text(_valueOrDash(borrower.phone))),
                            DataCell(Text(_valueOrDash(borrower.email))),
                            DataCell(Text(_valueOrDash(borrower.address))),
                            DataCell(
                              SizedBox(
                                width: 220,
                                child: Row(
                                  spacing: 4,
                                  children: [
                                    TextButton(
                                      onPressed: () => context.go(
                                        '/borrowers/${borrower.id}',
                                      ),
                                      child: const Text('View'),
                                    ),
                                    TextButton(
                                      onPressed: () => _edit(context, borrower),
                                      child: const Text('Edit'),
                                    ),
                                    TextButton(
                                      onPressed: () => _archive(borrower),
                                      child: const Text('Archive'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ]),
                        ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  void _sort(int columnIndex, bool ascending) => setState(() {
    sortColumnIndex = columnIndex;
    sortAscending = ascending;
  });

  Future<void> _edit(BuildContext context, [Borrower? borrower]) async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _BorrowerDialog(borrower),
    );
    if (result != null) {
      final controller = ref.read(borrowersControllerProvider.notifier);
      final saved = await controller.save(
        id: borrower?.id,
        firstName: result['first']!,
        lastName: result['last']!,
        phone: result['phone']!,
        email: result['email']!,
        address: result['address']!,
        consentConfirmed: result['consent'] == 'true',
        expectedUpdatedAt: borrower?.updatedAt,
      );
      if (!mounted) return;
      _showMessage(
        saved
            ? borrower == null
                  ? 'Borrower created.'
                  : 'Borrower changes saved.'
            : controller.lastSaveConflict
            ? 'This borrower changed on another device. Refresh the list, review the newer values, and try again.'
            : 'Borrower could not be saved. Check your connection and try again.',
      );
    }
  }

  Future<void> _archive(Borrower borrower) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Archive borrower?'),
        content: Text(
          '${borrower.displayName} will be removed from active borrower lists. The record can be restored later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Archive Borrower'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final borrowers = ref.read(borrowersControllerProvider.notifier);
    final archived = await borrowers.archive(borrower);
    if (!mounted) return;
    if (archived) {
      undoOf(
        context,
      ).offer('Borrower archived.', () => borrowers.restore(borrower));
    } else {
      _showMessage('Borrower could not be archived. Try again.');
    }
  }

  Future<void> _showArchived() async {
    final controller = ref.read(borrowersControllerProvider.notifier);
    var archived = await controller.fetchArchived();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Archived borrowers'),
          content: SizedBox(
            width: 620,
            child: archived.isEmpty
                ? const Text('No archived borrowers.')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: archived.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (_, index) {
                      final borrower = archived[index];
                      return ListTile(
                        leading: const Icon(Icons.person_off_outlined),
                        title: Text(borrower.displayName),
                        subtitle: Text(borrower.phone),
                        trailing: TextButton(
                          onPressed: () async {
                            if (await controller.restore(borrower)) {
                              archived = await controller.fetchArchived();
                              setDialogState(() {});
                            }
                          },
                          child: const Text('Restore'),
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
      ),
    );
  }

  /// Result of a borrower transaction without undo (ends any current undo).
  void _showMessage(String message) => undoOf(context).record(message);
}

class _BorrowerCard extends StatelessWidget {
  const _BorrowerCard(
    this.b, {
    required this.onOpen,
    required this.onEdit,
    required this.onArchive,
    required this.hasActiveLoan,
  });
  final Borrower b;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onArchive;
  final bool hasActiveLoan;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      onTap: onOpen,
      contentPadding: const EdgeInsets.all(14),
      leading: CircleAvatar(child: Text(_initials(b))),
      title: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            b.displayName,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (hasActiveLoan) const _OngoingBadge(),
        ],
      ),
      subtitle: Text(
        [
          b.phone,
          b.address,
        ].where((value) => value.trim().isNotEmpty).join('\n'),
      ),
      isThreeLine: true,
      trailing: PopupMenuButton<_BorrowerAction>(
        tooltip: 'Borrower actions',
        onSelected: (action) {
          switch (action) {
            case _BorrowerAction.edit:
              onEdit();
            case _BorrowerAction.archive:
              onArchive();
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: _BorrowerAction.edit,
            child: ListTile(
              leading: Icon(Icons.edit_outlined),
              title: Text('Edit'),
            ),
          ),
          PopupMenuItem(
            value: _BorrowerAction.archive,
            child: ListTile(
              leading: Icon(Icons.archive_outlined),
              title: Text('Archive'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _OngoingBadge extends StatelessWidget {
  const _OngoingBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      'Ongoing',
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onPrimaryContainer,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _BorrowerDialog extends StatefulWidget {
  const _BorrowerDialog(this.borrower);
  final Borrower? borrower;
  @override
  State<_BorrowerDialog> createState() => _BorrowerDialogState();
}

class _BorrowerDialogState extends State<_BorrowerDialog> {
  final key = GlobalKey<FormState>();
  bool consentConfirmed = false;
  late final fields = [
    TextEditingController(text: widget.borrower?.firstName),
    TextEditingController(text: widget.borrower?.lastName),
    TextEditingController(text: widget.borrower?.phone),
    TextEditingController(text: widget.borrower?.email),
    TextEditingController(text: widget.borrower?.address),
  ];
  @override
  void dispose() {
    for (final c in fields) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.borrower == null ? 'Add borrower' : 'Edit borrower'),
    content: SizedBox(
      width: 520,
      child: Form(
        key: key,
        child: SingleChildScrollView(
          child: Column(
            children: [
              _field(0, 'First name', true),
              _field(1, 'Last name', true),
              _field(2, 'Phone', false),
              _field(3, 'Email', false, email: true),
              _field(4, 'Address', false),
              if (widget.borrower == null)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: consentConfirmed,
                  onChanged: (value) =>
                      setState(() => consentConfirmed = value ?? false),
                  title: const Text('Borrower consent confirmed'),
                  subtitle: const Text(
                    'The borrower agreed to the interim privacy notice and 10-year financial-record retention policy.',
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (key.currentState!.validate() &&
              (widget.borrower != null || consentConfirmed)) {
            Navigator.pop(context, {
              'first': fields[0].text,
              'last': fields[1].text,
              'phone': fields[2].text,
              'email': fields[3].text,
              'address': fields[4].text,
              'consent': consentConfirmed.toString(),
            });
          }
        },
        child: Text(
          widget.borrower == null ? 'Create Borrower' : 'Save Changes',
        ),
      ),
    ],
  );
  Widget _field(int i, String label, bool required, {bool email = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: fields[i],
          decoration: InputDecoration(labelText: label),
          validator: (v) {
            if (required && (v?.trim().isEmpty ?? true)) {
              return '$label is required';
            }
            if (email && v!.isNotEmpty && !v.contains('@')) {
              return 'Enter a valid email';
            }
            return null;
          },
        ),
      );
}

enum _BorrowerAction { edit, archive }

String _valueOrDash(String value) => value.trim().isEmpty ? '—' : value;

String _initials(Borrower borrower) {
  final first = borrower.firstName.trim();
  final last = borrower.lastName.trim();
  return '${first.isEmpty ? '' : first[0]}${last.isEmpty ? '' : last[0]}'
      .toUpperCase();
}

class _BorrowersError extends StatelessWidget {
  const _BorrowersError({required this.onRetry});
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.cloud_off_outlined,
          size: 44,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(height: 12),
        const Text('Borrowers could not be loaded.'),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Try Again'),
        ),
      ],
    ),
  );
}
