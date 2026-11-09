import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'evidence_counts.dart';
import 'loan_evidence_section.dart';
import '../../core/widgets/table_columns.dart';
import '../../core/preferences/filter_defaults.dart';
import '../../core/formatting.dart';
import '../../core/widgets/responsive_card_list.dart';
import '../../core/widgets/app_status_badge.dart';
import '../../domain/models/models.dart';
import '../loans/loans_controller.dart';
import 'loan_print_menu.dart';

class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key});

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  int sortColumnIndex = 1;
  bool sortAscending = true;
  // Documents are almost always for active loans; long-press an option to
  // change the remembered default.
  late String statusFilter = ref
      .read(filterDefaultsProvider)
      .get('documents.status', 'active');

  @override
  Widget build(BuildContext context) {
    final loans = ref.watch(loansControllerProvider);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Documents', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          const Text('Generate an A4 payment schedule from stored loan terms.'),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 190,
              child: DefaultableFilterDropdown(
                listKey: 'documents.status',
                listName: 'Documents',
                label: 'Loan status',
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
          ),
          const SizedBox(height: 16),
          Expanded(
            child: loans.when(
              data: _buildLoans,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) =>
                  const Center(child: Text('Documents could not be loaded.')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoans(List<LoanSummary> source) {
    if (source.isEmpty) {
      return const Center(child: Text('No loans available.'));
    }
    final items =
        source
            .where(
              (loan) => statusFilter == 'all' || loan.status == statusFilter,
            )
            .toList()
          ..sort((left, right) {
            final comparison = switch (sortColumnIndex) {
              0 => left.id.compareTo(right.id),
              1 => left.borrowerName.toLowerCase().compareTo(
                right.borrowerName.toLowerCase(),
              ),
              2 => left.totalCentavos.compareTo(right.totalCentavos),
              3 => left.status.compareTo(right.status),
              _ => 0,
            };
            return sortAscending ? comparison : -comparison;
          });
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 760
          ? ResponsiveCardList(
              itemCount: items.length,
              itemBuilder: (_, index) => _DocumentLoanCard(
                items[index],
                onEvidence: () => _manageEvidence(context, items[index]),
                onPrint: (document) => _print(items[index], document),
              ),
            )
          : ColumnToggle(
              tableId: 'documents',
              labels: const [
                'Reference',
                'Borrower',
                'Total',
                'Status',
                'Actions',
              ],
              builder: (view) => Card(
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  child: DataTable(
                    sortColumnIndex: view.sortIndex(sortColumnIndex),
                    sortAscending: sortAscending,
                    columns: view.columns([
                      DataColumn(label: const Text('Reference'), onSort: _sort),
                      DataColumn(label: const Text('Borrower'), onSort: _sort),
                      DataColumn(
                        label: const Text('Total'),
                        numeric: true,
                        onSort: _sort,
                      ),
                      DataColumn(label: const Text('Status'), onSort: _sort),
                      const DataColumn(label: Text('Actions')),
                    ]),
                    rows: [
                      for (final loan in items)
                        DataRow(
                          cells: view.cells([
                            DataCell(
                              LoanReferenceWithEvidence(
                                _reference(loan.id),
                                loan.id,
                              ),
                            ),
                            DataCell(Text(loan.borrowerName)),
                            DataCell(Text(formatPeso(loan.totalCentavos))),
                            DataCell(AppStatusBadge(loan.status)),
                            DataCell(
                              Wrap(
                                spacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () =>
                                        _manageEvidence(context, loan),
                                    icon: const Icon(Icons.attach_file),
                                    label: const Text('Evidence'),
                                  ),
                                  LoanPrintMenu(
                                    filled: true,
                                    loadLoan: () => ref
                                        .read(loansControllerProvider.notifier)
                                        .fetchDetail(loan.id),
                                  ),
                                ],
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

  Future<void> _print(LoanSummary loan, LoanPrintDocument document) async {
    final detail = await ref
        .read(loansControllerProvider.notifier)
        .fetchDetail(loan.id);
    if (!mounted) return;
    await printFromContext(
      context,
      (container) => printLoanDocument(container, detail, document),
    );
  }

  Future<void> _manageEvidence(BuildContext context, LoanSummary loan) =>
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('${loan.borrowerName} · ${_reference(loan.id)}'),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: LoanEvidenceSection(loan: loan),
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

class _DocumentLoanCard extends StatelessWidget {
  const _DocumentLoanCard(
    this.loan, {
    required this.onEvidence,
    required this.onPrint,
  });
  final LoanSummary loan;
  final VoidCallback onEvidence;
  final void Function(LoanPrintDocument document) onPrint;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.picture_as_pdf_outlined),
      title: Text(loan.borrowerName),
      subtitle: Row(
        children: [
          Flexible(
            child: Text(
              '${_reference(loan.id)} · ${formatPeso(loan.totalCentavos)}',
            ),
          ),
          EvidenceBadge(loan.id),
        ],
      ),
      trailing: PopupMenuButton<String>(
        tooltip: 'Document actions',
        onSelected: (value) => value == 'evidence'
            ? onEvidence()
            : onPrint(LoanPrintDocument.values.byName(value)),
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'evidence', child: Text('Evidence')),
          for (final d in LoanPrintDocument.values)
            PopupMenuItem(value: d.name, child: Text('Print ${d.label}')),
        ],
      ),
    ),
  );
}

String _reference(String id) => 'LN-${id.substring(0, 8).toUpperCase()}';
