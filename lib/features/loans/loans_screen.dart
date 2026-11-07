import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/preferences/filter_defaults.dart';
import '../../core/formatting.dart';
import '../../core/widgets/responsive_card_list.dart';
import '../../core/widgets/app_status_badge.dart';
import '../../core/widgets/clearable_search_field.dart';
import '../../domain/models/models.dart';
import 'loans_controller.dart';

class LoansScreen extends ConsumerStatefulWidget {
  const LoansScreen({super.key, this.personalOnly = false});
  final bool personalOnly;

  @override
  ConsumerState<LoansScreen> createState() => _LoansScreenState();
}

class _LoansScreenState extends ConsumerState<LoansScreen> {
  String query = '';
  // Opens on the remembered default (long-press an option to change it);
  // Active unless the user picked another.
  String get _filterKey =>
      widget.personalOnly ? 'personal_loans.status' : 'loans.status';
  late String statusFilter = ref
      .read(filterDefaultsProvider)
      .get(_filterKey, 'active');
  int sortColumnIndex = 2;
  bool sortAscending = false;

  @override
  Widget build(BuildContext context) {
    final loans = ref.watch(loansControllerProvider);
    final controller = ref.read(loansControllerProvider.notifier);
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
                widget.personalOnly ? 'Personal Loans' : 'Loans',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (controller.isLive)
                    IconButton(
                      tooltip: 'Refresh loans',
                      onPressed: loans.isLoading ? null : controller.refresh,
                      icon: const Icon(Icons.refresh),
                    ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: loans.isLoading
                        ? null
                        : () => context.go('/loans/new'),
                    icon: const Icon(Icons.add),
                    label: const Text('New Loan'),
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
                  width: constraints.maxWidth < 430
                      ? constraints.maxWidth
                      : constraints.maxWidth - 192,
                  child: ClearableSearchField(
                    onChanged: (value) => setState(() => query = value),
                    hintText: 'Search borrower or loan reference',
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: DefaultableFilterDropdown(
                    listKey: _filterKey,
                    listName: widget.personalOnly ? 'Personal Loans' : 'Loans',
                    label: 'Status',
                    value: statusFilter,
                    fallback: 'active',
                    options: const [
                      ('all', 'All statuses'),
                      ('draft', 'Draft'),
                      ('active', 'Active'),
                      ('fully_paid', 'Paid'),
                      ('refinanced', 'Refinanced'),
                      ('cancelled', 'Cancelled'),
                    ],
                    onChanged: (value) => setState(() => statusFilter = value),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: loans.when(
              skipLoadingOnReload: true,
              data: _buildLoans,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => _LoansError(onRetry: controller.refresh),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoans(List<LoanSummary> allLoans) {
    final scopedLoans = allLoans
        .where((loan) => loan.isPersonal == widget.personalOnly)
        .toList();
    final normalized = query.trim().toLowerCase();
    final loans = scopedLoans
        .where(
          (loan) =>
              (statusFilter == 'all' || loan.status == statusFilter) &&
              (normalized.isEmpty ||
                  loan.borrowerName.toLowerCase().contains(normalized) ||
                  loan.id.toLowerCase().contains(normalized)),
        )
        .toList();
    loans.sort((left, right) {
      // Unpaid loans always sit below paid ones when sorting by paid date.
      if (sortColumnIndex == 3 &&
          (left.paidOn == null) != (right.paidOn == null)) {
        return left.paidOn == null ? 1 : -1;
      }
      final comparison = switch (sortColumnIndex) {
        0 => left.id.compareTo(right.id),
        1 => left.borrowerName.toLowerCase().compareTo(
          right.borrowerName.toLowerCase(),
        ),
        2 => left.borrowedSortDate.compareTo(right.borrowedSortDate),
        3 => left.paidOn == null ? 0 : left.paidOn!.compareTo(right.paidOn!),
        4 => left.principalCentavos.compareTo(right.principalCentavos),
        5 => left.totalCentavos.compareTo(right.totalCentavos),
        6 => left.status.compareTo(right.status),
        _ => 0,
      };
      if (comparison == 0 && sortColumnIndex != 2) {
        return right.borrowedSortDate.compareTo(left.borrowedSortDate);
      }
      return sortAscending ? comparison : -comparison;
    });

    if (loans.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.personalOnly
                  ? Icons.person_outline
                  : Icons.handshake_outlined,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              scopedLoans.isEmpty
                  ? widget.personalOnly
                        ? 'No personal loans.'
                        : 'No business loan records yet.'
                  : statusFilter != 'all' && normalized.isEmpty
                  ? 'No loans with this status. Change the Status filter to see others.'
                  : 'No loans match your search.',
            ),
            if (scopedLoans.isEmpty && !widget.personalOnly) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => context.go('/loans/new'),
                icon: const Icon(Icons.add),
                label: const Text('Create First Loan'),
              ),
            ],
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 760
          ? ResponsiveCardList(
              itemCount: loans.length,
              itemBuilder: (_, index) => _LoanCard(
                loans[index],
                onTap: () => context.go(
                  '/loans/${loans[index].id}?from=${widget.personalOnly ? 'personal' : 'loans'}',
                ),
              ),
            )
          : Card(
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                child: DataTable(
                  // Rows open on tap; there is nothing to select, so no checkboxes.
                  showCheckboxColumn: false,
                  sortColumnIndex: sortColumnIndex,
                  sortAscending: sortAscending,
                  columns: [
                    DataColumn(label: const Text('Reference'), onSort: _sort),
                    DataColumn(label: const Text('Borrower'), onSort: _sort),
                    DataColumn(label: const Text('Borrowed'), onSort: _sort),
                    DataColumn(label: const Text('Paid'), onSort: _sort),
                    DataColumn(
                      label: const Text('Principal'),
                      numeric: true,
                      onSort: _sort,
                    ),
                    DataColumn(
                      label: const Text('Total'),
                      numeric: true,
                      onSort: _sort,
                    ),
                    DataColumn(label: const Text('Status'), onSort: _sort),
                  ],
                  rows: [for (final loan in loans) _row(context, loan)],
                ),
              ),
            ),
    );
  }

  void _sort(int columnIndex, bool ascending) => setState(() {
    sortColumnIndex = columnIndex;
    sortAscending = ascending;
  });

  DataRow _row(BuildContext context, LoanSummary loan) => DataRow(
    onSelectChanged: (_) => context.go(
      '/loans/${loan.id}?from=${widget.personalOnly ? 'personal' : 'loans'}',
    ),
    cells: [
      DataCell(Text(_reference(loan.id))),
      DataCell(Text(loan.borrowerName)),
      DataCell(Text(_borrowedLabel(loan))),
      DataCell(Text(_paidLabel(loan))),
      DataCell(Text(formatPeso(loan.principalCentavos))),
      DataCell(Text(formatPeso(loan.totalCentavos))),
      DataCell(AppStatusBadge(loan.status)),
    ],
  );
}

class _LoanCard extends StatelessWidget {
  const _LoanCard(this.loan, {required this.onTap});
  final LoanSummary loan;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    loan.borrowerName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                AppStatusBadge(loan.status),
              ],
            ),
            const SizedBox(height: 8),
            Text('Reference: ${_reference(loan.id)}'),
            Text('Borrowed: ${_borrowedLabel(loan)}'),
            Text('Paid: ${_paidLabel(loan)}'),
            const SizedBox(height: 8),
            _amount('Principal', loan.principalCentavos),
            _amount('Total repayable', loan.totalCentavos),
          ],
        ),
      ),
    ),
  );

  Widget _amount(String label, int value) => Row(
    children: [
      Expanded(child: Text(label)),
      Text(
        formatPeso(value),
        textAlign: TextAlign.right,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ],
  );
}

class _LoansError extends StatelessWidget {
  const _LoansError({required this.onRetry});
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
        const Text('Loans could not be loaded.'),
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

String _reference(String id) => 'LN-${id.substring(0, 8).toUpperCase()}';

String _borrowedLabel(LoanSummary loan) => loan.borrowedOn == null
    ? 'Not released'
    : formatPhilippineDate(loan.borrowedOn!);

String _paidLabel(LoanSummary loan) =>
    loan.paidOn == null ? 'Not paid' : formatPhilippineDate(loan.paidOn!);
