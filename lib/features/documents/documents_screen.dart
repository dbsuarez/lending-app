import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/preferences/filter_defaults.dart';
import '../../core/undo/undo_controller.dart';
import '../../core/formatting.dart';
import '../../core/widgets/responsive_card_list.dart';
import '../../core/widgets/app_status_badge.dart';
import '../../data/repositories/supabase_documents_repository.dart';
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
          : Card(
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                child: DataTable(
                  sortColumnIndex: sortColumnIndex,
                  sortAscending: sortAscending,
                  columns: [
                    DataColumn(label: const Text('Reference'), onSort: _sort),
                    DataColumn(label: const Text('Borrower'), onSort: _sort),
                    DataColumn(
                      label: const Text('Total'),
                      numeric: true,
                      onSort: _sort,
                    ),
                    DataColumn(label: const Text('Status'), onSort: _sort),
                    const DataColumn(label: Text('Actions')),
                  ],
                  rows: [
                    for (final loan in items)
                      DataRow(
                        cells: [
                          DataCell(Text(_reference(loan.id))),
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
                        ],
                      ),
                  ],
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
    await printLoanDocument(detail, document);
  }

  Future<void> _uploadEvidence(BuildContext context, LoanSummary loan) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (file == null) return;
    final extension = file.extension?.toLowerCase();
    final mime = extension == 'pdf'
        ? 'application/pdf'
        : extension == 'png'
        ? 'image/png'
        : 'image/jpeg';
    try {
      final bytes = await file.readAsBytes();
      await SupabaseDocumentsRepository(
        Supabase.instance.client,
      ).uploadEvidence(
        organizationId: loan.organizationId,
        loanId: loan.id,
        documentType: 'disbursement_evidence',
        originalName: file.name,
        mimeType: mime,
        bytes: bytes,
      );
      if (context.mounted) {
        undoOf(context).record('Evidence uploaded to private storage.');
      }
    } catch (_) {
      if (context.mounted) {
        undoOf(context).record(
          'Evidence upload failed. Use a PDF, JPG, or PNG no larger than 10 MB.',
        );
      }
    }
  }

  Future<void> _manageEvidence(BuildContext context, LoanSummary loan) async {
    final repository = SupabaseDocumentsRepository(Supabase.instance.client);
    var documents = await repository.fetchForLoan(loan.id);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: const Text('Private loan evidence'),
          content: SizedBox(
            width: 620,
            child: documents.isEmpty
                ? const Text('No evidence has been uploaded for this loan.')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: documents.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (_, index) {
                      final document = documents[index];
                      return ListTile(
                        leading: Icon(
                          document.mimeType == 'application/pdf'
                              ? Icons.picture_as_pdf
                              : Icons.image_outlined,
                        ),
                        title: Text(document.name),
                        subtitle: Text(
                          '${(document.sizeBytes / 1048576).toStringAsFixed(2)} MB · ${formatPhilippineDateTime(document.createdAt)}',
                        ),
                        trailing: IconButton(
                          tooltip: 'Open for 5 minutes',
                          onPressed: () async => launchUrl(
                            await repository.signedUrl(document.storagePath),
                          ),
                          icon: const Icon(Icons.open_in_new),
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
            FilledButton.icon(
              onPressed: () async {
                await _uploadEvidence(dialogContext, loan);
                documents = await repository.fetchForLoan(loan.id);
                setDialogState(() {});
              },
              icon: const Icon(Icons.upload_file),
              label: const Text('Upload Evidence'),
            ),
          ],
        ),
      ),
    );
  }
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
      subtitle: Text(
        '${_reference(loan.id)} · ${formatPeso(loan.totalCentavos)}',
      ),
      trailing: PopupMenuButton<String>(
        tooltip: 'Document actions',
        onSelected: (value) => switch (value) {
          'schedule' => onPrint(LoanPrintDocument.schedule),
          'ledger' => onPrint(LoanPrintDocument.ledger),
          _ => onEvidence(),
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'evidence', child: Text('Evidence')),
          PopupMenuItem(value: 'schedule', child: Text('Print loan schedule')),
          PopupMenuItem(value: 'ledger', child: Text('Print payment ledger')),
        ],
      ),
    ),
  );
}

String _reference(String id) => 'LN-${id.substring(0, 8).toUpperCase()}';
